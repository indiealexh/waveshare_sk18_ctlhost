import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../domain/models/sk18_device_info.dart';
import '../../domain/models/sk18_geometry.dart';
import 'protocol_v2_codec.dart';

abstract class Sk18Transport {
  Stream<Uint8List> get incomingBytes;
  bool get isConnected;
  bool get isSimulator;
  String get activePortPath;

  Future<void> connect(String portPath);
  Future<void> disconnect();
  Future<void> writeBytes(Uint8List bytes);
  void dispose();
}

class SerialPortDiscovery {
  static const String simulatorPortUri = 'simulator://sk18';
  static const String mk10SimulatorPortUri = 'simulator://mk10';

  const SerialPortDiscovery._();

  static bool isSimulatorUri(String port) =>
      port.trim().toLowerCase().startsWith('simulator://');

  static String simulatorPortForModel(WaveshareModel model) =>
      model == WaveshareModel.mk10 ? mk10SimulatorPortUri : simulatorPortUri;

  /// Normalizes macOS `/dev/tty.*` dial-in device paths to `/dev/cu.*` call-out
  /// paths so `open(2)` never blocks waiting for hardware Data Carrier Detect (DCD).
  static String normalizeDevicePath(String path) {
    final trimmed = path.trim();
    if (trimmed.startsWith('/dev/tty.')) {
      return trimmed.replaceFirst('/dev/tty.', '/dev/cu.');
    }
    return trimmed;
  }

  /// Discovers candidate SK18 / MK10 serial ports across macOS (`/dev/cu.usbmodem*`)
  /// and Linux (`/dev/ttyACM*`), always including the virtual simulator options.
  static Future<List<String>> discoverPorts() async {
    final ports = <String>[];
    try {
      if (Platform.isMacOS) {
        final devDir = Directory('/dev');
        if (devDir.existsSync()) {
          for (final entity in devDir.listSync(followLinks: false)) {
            final name = entity.path.split('/').last;
            if (name.startsWith('cu.usbmodem')) {
              ports.add(entity.path);
            }
          }
        }
      } else if (Platform.isLinux) {
        final devDir = Directory('/dev');
        if (devDir.existsSync()) {
          for (final entity in devDir.listSync(followLinks: false)) {
            final name = entity.path.split('/').last;
            if (name.startsWith('ttyACM')) {
              ports.add(entity.path);
            }
          }
        }
      }
    } catch (_) {
      // Ignore filesystem permission errors in restricted environments
    }

    ports.sort();
    if (!ports.contains(simulatorPortUri)) {
      ports.add(simulatorPortUri);
    }
    if (!ports.contains(mk10SimulatorPortUri)) {
      ports.add(mk10SimulatorPortUri);
    }
    return ports;
  }
}

/// Hardware POSIX USB CDC-ACM serial transport adhering to all `pocflutter`
/// production guardrails:
/// 1. Opens with `FileMode.write` (never `FileMode.append` which fails with `ESPIPE`).
/// 2. Opens and holds the file descriptor BEFORE running `stty` so macOS does not reset `termios`.
/// 3. Never uses `File.openRead()`; polls non-blocking `readSync` (`min 0 time 0`) on a single descriptor.
class PosixSerialTransport implements Sk18Transport {
  final StreamController<Uint8List> _incomingController =
      StreamController<Uint8List>.broadcast();
  RandomAccessFile? _raf;
  Timer? _pollTimer;
  String _activePortPath = '';

  @override
  Stream<Uint8List> get incomingBytes => _incomingController.stream;

  @override
  bool get isConnected => _raf != null;

  @override
  bool get isSimulator => false;

  @override
  String get activePortPath => _activePortPath;

  @override
  Future<void> connect(String portPath) async {
    await disconnect();
    final normalizedPath = SerialPortDiscovery.normalizeDevicePath(portPath);
    final file = File(normalizedPath);

    // 1. Open descriptor FIRST with FileMode.write (avoids lseek ESPIPE on character devices)
    final raf = await file.open(mode: FileMode.write);
    _raf = raf;
    _activePortPath = normalizedPath;

    // 2. Configure 115200 raw non-blocking (VMIN=0, VTIME=0) WHILE holding descriptor open
    final sttyFlag = Platform.isMacOS ? '-f' : '-F';
    try {
      await Process.run('stty', [
        sttyFlag,
        normalizedPath,
        '115200',
        'raw',
        '-echo',
        'clocal',
        'cread',
        'cs8',
        '-cstopb',
        '-parenb',
        'min',
        '0',
        'time',
        '0',
      ]);
    } catch (_) {
      // Continue if stty is unavailable in test environment
    }

    // 3. Drain any stale unread bytes buffered by the kernel driver
    try {
      while (raf.readSync(4096).isNotEmpty) {}
    } catch (_) {}

    // 4. Poll non-blocking readSync on a managed periodic timer
    _pollTimer = Timer.periodic(const Duration(milliseconds: 5), (_) {
      final activeRaf = _raf;
      if (activeRaf == null) return;
      try {
        final chunk = activeRaf.readSync(65536);
        if (chunk.isNotEmpty && !_incomingController.isClosed) {
          _incomingController.add(chunk);
        }
      } catch (_) {
        // Disconnect cleanly if USB cable is unplugged
        disconnect();
      }
    });
  }

  @override
  Future<void> writeBytes(Uint8List bytes) async {
    final activeRaf = _raf;
    if (activeRaf == null) {
      throw StateError('Serial port is not connected.');
    }
    activeRaf.writeFromSync(bytes);
    activeRaf.flushSync();
  }

  @override
  Future<void> disconnect() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    final activeRaf = _raf;
    _raf = null;
    _activePortPath = '';
    if (activeRaf != null) {
      try {
        await activeRaf.close();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    try {
      _raf?.closeSync();
    } catch (_) {}
    _raf = null;
    if (!_incomingController.isClosed) {
      _incomingController.close();
    }
  }
}

class SimulatedWavFile {
  final String filePath;
  final BytesBuilder dataBuilder = BytesBuilder(copy: false);
  String crc;

  SimulatedWavFile({
    required this.filePath,
    this.crc = '0',
    List<int>? initialBytes,
  }) {
    if (initialBytes != null && initialBytes.isNotEmpty) {
      dataBuilder.add(initialBytes);
    }
  }
}

/// In-memory Protocol V2 Waveshare SK18 virtual hardware simulator.
/// Responds to the 37-byte V1 abort sequence, all 10 stock V2 JSON-RPC methods,
/// custom firmware layout config RPCs, and `CMD_VALUE_SHOW_JPG` frame streaming.
class SimulatorSerialTransport implements Sk18Transport {
  final StreamController<Uint8List> _incomingController =
      StreamController<Uint8List>.broadcast();
  final ProtocolV2StreamDecoder _hostToDeviceDecoder =
      ProtocolV2StreamDecoder();

  bool _connected = false;
  String _activePortPath = '';
  final bool simulatePortraitScanout;
  WaveshareModel? simulatedModel;

  int simulatedBacklight = 85;
  int simulatedVolume = 5;
  int framesReceivedCount = 0;
  Uint8List? lastFrameJpegBytes;
  String? lastPlayedAudioPath;
  bool isAudioPlaying = false;
  final List<String> typedStrings = <String>[];
  Map<String, dynamic> storedLayoutConfig = <String, dynamic>{};

  /// If true, the simulator intentionally drops `CMD_VALUE_SHOW_JPG` ACKs
  /// to allow unit testing the 500 ms watchdog timer.
  bool dropFrameAcks = false;

  /// If true, the simulator emulates stock `V2.32` factory firmware by rejecting
  /// custom companion RPCs (`setLayoutConfig`, `getLayoutConfig`) with the exact
  /// `Unknown method` error string returned by `/data/KeyboardDevice`.
  bool simulateStockV232Only = false;

  final Map<String, SimulatedWavFile> _wavFiles = <String, SimulatedWavFile>{
    '/data/sound/click.wav': SimulatedWavFile(
      filePath: '/data/sound/click.wav',
      crc: '2713489012',
    ),
    '/data/sound/chime.wav': SimulatedWavFile(
      filePath: '/data/sound/chime.wav',
      crc: '1982374610',
    ),
  };

  SimulatorSerialTransport({
    this.simulatePortraitScanout = true,
    this.simulatedModel,
  });

  WaveshareModel get effectiveModel {
    if (simulatedModel != null) {
      return simulatedModel!;
    }
    final lowerPort = _activePortPath.trim().toLowerCase();
    if (lowerPort == SerialPortDiscovery.mk10SimulatorPortUri ||
        lowerPort.contains('mk10')) {
      return WaveshareModel.mk10;
    }
    return WaveshareModel.sk18;
  }

  @override
  Stream<Uint8List> get incomingBytes => _incomingController.stream;

  @override
  bool get isConnected => _connected;

  @override
  bool get isSimulator => true;

  @override
  String get activePortPath => _activePortPath;

  Map<String, SimulatedWavFile> get wavFiles => _wavFiles;

  @override
  Future<void> connect(String portPath) async {
    _connected = true;
    _activePortPath = portPath.isEmpty
        ? SerialPortDiscovery.simulatorPortUri
        : portPath;
    _hostToDeviceDecoder.reset();
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _activePortPath = '';
    _hostToDeviceDecoder.reset();
  }

  @override
  Future<void> writeBytes(Uint8List bytes) async {
    if (!_connected) {
      throw StateError('Simulator transport is not connected.');
    }

    // Check if the host sent the 37-byte V1 abort sequence
    final rawText = latin1.decode(bytes, allowInvalid: true);
    if (rawText.contains(ProtocolV2Codec.v1AbortCommand)) {
      _emitToHost(
        Uint8List.fromList(ascii.encode(ProtocolV2Codec.v1AbortAck)),
      );
    }

    final packets = _hostToDeviceDecoder.addChunk(bytes);
    for (final pkt in packets) {
      _handleHostPacket(pkt);
    }
  }

  void _handleHostPacket(ProtocolV2Packet pkt) {
    if (pkt.isShowJpg) {
      framesReceivedCount++;
      lastFrameJpegBytes = pkt.payload;
      if (!dropFrameAcks) {
        // Send V2 empty-payload SHOW_JPG ACK (cmd = 100, size = 0, size_crc = 0x2144DF1C)
        final ackFrame = ProtocolV2Codec.encodePacket(
          id: pkt.id,
          cmd: ProtocolV2Codec.cmdShowJpg,
          payload: const [],
        );
        _emitToHost(ackFrame);
      }
      return;
    }

    if (pkt.isJson) {
      final request = pkt.decodeJson();
      if (request == null) return;
      final method = request['method'] as String? ?? '';
      final params =
          (request['parameters'] as Map<String, dynamic>?) ??
          const <String, dynamic>{};

      switch (method) {
        case 'getInfo':
          final Sk18DeviceInfo info;
          if (effectiveModel == WaveshareModel.mk10) {
            info = simulatePortraitScanout
                ? Sk18DeviceInfo.defaultMk10Portrait()
                : Sk18DeviceInfo.defaultMk10Landscape();
          } else {
            info = simulatePortraitScanout
                ? Sk18DeviceInfo.defaultPortrait()
                : Sk18DeviceInfo.defaultLandscape();
          }
          _sendJsonResponse(
            id: pkt.id,
            ackMethod: 'getInfo',
            result: info.toJson(),
          );
          break;

        case 'setBacklight':
          final level = (params['level'] as num?)?.toInt();
          if (level == null || level < 0 || level > 100) {
            _sendJsonError(
              id: pkt.id,
              ackMethod: 'setBacklight',
              errorString: 'Backlight level must be between 0 and 100',
            );
          } else {
            simulatedBacklight = level;
            _sendJsonResponse(
              id: pkt.id,
              ackMethod: 'setBacklight',
              result: {'level': level},
            );
          }
          break;

        case 'setVolume':
          final level = (params['level'] as num?)?.toInt();
          if (level == null || level < 0 || level > 7) {
            _sendJsonError(
              id: pkt.id,
              ackMethod: 'setVolume',
              errorString: 'Volume level must be between 0 and 7',
            );
          } else {
            simulatedVolume = level;
            _sendJsonResponse(
              id: pkt.id,
              ackMethod: 'setVolume',
              result: {'level': level},
            );
          }
          break;

        case 'keyboardInput':
          final inputString = params['inputString'] as String? ?? '';
          if (inputString.isEmpty) {
            _sendJsonError(
              id: pkt.id,
              ackMethod: 'keyboardInput',
              errorString: "'inputString' cannot be empty",
            );
          } else {
            typedStrings.add(inputString);
            _sendJsonResponse(
              id: pkt.id,
              ackMethod: 'keyboardInput',
              result: {
                'inputLength': inputString.length,
                'inputString': inputString,
              },
            );
          }
          break;

        case 'getFilesBySuffix':
          final suffixs = params['suffixs'];
          if (suffixs is! List) {
            _sendJsonError(
              id: pkt.id,
              ackMethod: 'getFilesBySuffix',
              errorString: "Missing 'suffixs' parameter",
            );
          } else {
            final matching = _wavFiles.values
                .map((f) => {'filePath': f.filePath, 'crc': f.crc})
                .toList();
            _sendJsonResponse(
              id: pkt.id,
              ackMethod: 'getFilesBySuffix',
              result: {'filePaths': matching},
            );
          }
          break;

        case 'saveToFile':
          final filePath = params['filePath'] as String? ?? '';
          final seek = (params['seek'] as num?)?.toInt() ?? 0;
          final b64Data = params['data'] as String? ?? '';
          final chunkBytes = base64Decode(b64Data);
          final entry = _wavFiles.putIfAbsent(
            filePath,
            () => SimulatedWavFile(filePath: filePath),
          );
          if (seek == 0) {
            entry.dataBuilder.clear();
          }
          entry.dataBuilder.add(chunkBytes);
          _sendJsonResponse(
            id: pkt.id,
            ackMethod: 'saveToFile',
            result: {'filePath': filePath, 'seek': seek},
          );
          break;

        case 'setFileCRC':
          final filePath = params['filePath'] as String? ?? '';
          final crc = (params['crc'] ?? '').toString();
          final entry = _wavFiles.putIfAbsent(
            filePath,
            () => SimulatedWavFile(filePath: filePath),
          );
          entry.crc = crc;
          _sendJsonResponse(
            id: pkt.id,
            ackMethod: 'setFileCRC',
            result: {'filePath': filePath, 'crc': crc},
          );
          break;

        case 'deleteFiles':
          final rawPaths = params['filePaths'];
          final deleted = <String>[];
          if (rawPaths is List) {
            for (final p in rawPaths.map((e) => e.toString())) {
              if (_wavFiles.remove(p) != null) {
                deleted.add(p);
              }
            }
          }
          _sendJsonResponse(
            id: pkt.id,
            ackMethod: 'deleteFiles',
            result: {'deletedFiles': deleted, 'failedFiles': <String>[]},
          );
          break;

        case 'playAudio':
          final filePath = params['filePath'] as String? ?? '';
          lastPlayedAudioPath = filePath;
          isAudioPlaying = true;
          _sendJsonResponse(
            id: pkt.id,
            ackMethod: 'playAudio',
            result: {'filePath': filePath},
          );
          break;

        case 'stopAudio':
          isAudioPlaying = false;
          _sendJsonResponse(
            id: pkt.id,
            ackMethod: 'stopAudio',
            result: {'stopped': true},
          );
          break;

        case 'getLayoutConfig':
          if (simulateStockV232Only) {
            _sendJsonError(
              id: pkt.id,
              ackMethod: 'getLayoutConfig',
              errorString:
                  'Unknown method: getLayoutConfig. Available methods: [deleteFiles, getFilesBySuffix, getInfo, keyboardInput, playAudio, saveToFile, setBacklight, setFileCRC, setVolume, stopAudio]',
            );
            break;
          }
          _sendJsonResponse(
            id: pkt.id,
            ackMethod: 'getLayoutConfig',
            result: {'config': storedLayoutConfig},
          );
          break;

        case 'setLayoutConfig':
          if (simulateStockV232Only) {
            _sendJsonError(
              id: pkt.id,
              ackMethod: 'setLayoutConfig',
              errorString:
                  'Unknown method: setLayoutConfig. Available methods: [deleteFiles, getFilesBySuffix, getInfo, keyboardInput, playAudio, saveToFile, setBacklight, setFileCRC, setVolume, stopAudio]',
            );
            break;
          }
          final config = params['config'];
          if (config is Map<String, dynamic>) {
            storedLayoutConfig = Map<String, dynamic>.from(config);
          }
          _sendJsonResponse(
            id: pkt.id,
            ackMethod: 'setLayoutConfig',
            result: {'saved': true},
          );
          break;

        case 'triggerKeyAction':
          _sendJsonResponse(
            id: pkt.id,
            ackMethod: 'triggerKeyAction',
            result: params,
          );
          break;

        default:
          _sendJsonResponse(
            id: pkt.id,
            ackMethod: method,
            result: {'ok': true},
          );
      }
    }
  }

  /// Emits an unsolicited physical `keyStateChanged` event from the simulated SK18.
  void emitPhysicalKeyStateChanged({
    required int col,
    required int row,
    required bool pressed,
  }) {
    if (!_connected) return;
    final eventPacket = ProtocolV2Codec.encodeJsonMap(
      id: 0,
      payloadMap: {
        'method': 'keyStateChanged',
        'parameters': {
          'col': col,
          'row': row,
          'pressed': pressed,
        },
      },
    );
    _emitToHost(eventPacket);
  }

  void _sendJsonResponse({
    required int id,
    required String ackMethod,
    required Object result,
  }) {
    final packet = ProtocolV2Codec.encodeJsonMap(
      id: id,
      payloadMap: {
        'ack_method': ackMethod,
        'success': true,
        'result': result,
      },
    );
    _emitToHost(packet);
  }

  void _sendJsonError({
    required int id,
    required String ackMethod,
    required String errorString,
  }) {
    final packet = ProtocolV2Codec.encodeJsonMap(
      id: id,
      payloadMap: {
        'ack_method': ackMethod,
        'success': false,
        'errorString': errorString,
      },
    );
    _emitToHost(packet);
  }

  void _emitToHost(Uint8List bytes) {
    if (!_incomingController.isClosed) {
      scheduleMicrotask(() {
        if (!_incomingController.isClosed && _connected) {
          _incomingController.add(bytes);
        }
      });
    }
  }

  @override
  void dispose() {
    _connected = false;
    if (!_incomingController.isClosed) {
      _incomingController.close();
    }
  }
}
