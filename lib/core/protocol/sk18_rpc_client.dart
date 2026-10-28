// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../models/sk18_device_info.dart';
import 'protocol_v2_codec.dart';
import 'serial_transport_service.dart';

class Sk18WavFileEntry {
  final String filePath;
  final String crc;

  const Sk18WavFileEntry({
    required this.filePath,
    required this.crc,
  });

  String get fileName => filePath.split('/').last;

  factory Sk18WavFileEntry.fromJson(Map<String, dynamic> json) {
    return Sk18WavFileEntry(
      filePath: (json['filePath'] as String?) ?? '',
      crc: (json['crc'] ?? '0').toString(),
    );
  }
}

class Sk18DeviceEvent {
  final String method;
  final Map<String, dynamic> parameters;

  const Sk18DeviceEvent({
    required this.method,
    required this.parameters,
  });
}

/// Multiplexes Protocol V2 JSON-RPC (`cmd = 101`) requests and `CMD_VALUE_SHOW_JPG` (`cmd = 100`)
/// frames over a `Sk18Transport`, correlating responses by packet `id` and routing
/// asynchronous device events (`keyStateChanged`, `macroTriggered`, `haStateUpdated`).
class Sk18RpcClient {
  static const int wavChunkSizeBytes = 65536; // 64 KB raw chunks

  Sk18Transport _transport;
  final ProtocolV2StreamDecoder _decoder = ProtocolV2StreamDecoder();
  StreamSubscription<Uint8List>? _transportSub;

  int _nextPacketId = 1;
  final Map<int, Completer<Map<String, dynamic>>> _pendingRequests =
      <int, Completer<Map<String, dynamic>>>{};
  final Map<int, Timer> _requestTimers = <int, Timer>{};

  final StreamController<Sk18DeviceEvent> _eventController =
      StreamController<Sk18DeviceEvent>.broadcast();
  final StreamController<int> _frameAckController =
      StreamController<int>.broadcast();
  final StreamController<bool> _uploadStateController =
      StreamController<bool>.broadcast();

  int _activeUploadCount = 0;
  bool _isHandshaking = false;
  int _protocolVersion = 2;
  Completer<Map<String, String>>? _v1FindDeviceCompleter;
  Timer? _v1FindDeviceTimer;
  Completer<void>? _v1BacklightCompleter;
  Timer? _v1BacklightTimer;
  final Duration requestTimeout;

  Sk18RpcClient({
    required Sk18Transport transport,
    this.requestTimeout = const Duration(milliseconds: 2500),
  }) : _transport = transport {
    _bindTransport(_transport);
  }

  Sk18Transport get transport => _transport;
  bool get isConnected => _transport.isConnected && !_isHandshaking;
  bool get isSimulator => _transport.isSimulator;
  bool get isUploadingFile => _activeUploadCount > 0;
  int get protocolVersion => _protocolVersion;
  bool get isV1Protocol => _protocolVersion == 1;

  Stream<Sk18DeviceEvent> get deviceEvents => _eventController.stream;
  Stream<int> get frameAcks => _frameAckController.stream;
  Stream<bool> get uploadStateChanges => _uploadStateController.stream;

  void setTransport(Sk18Transport newTransport) {
    _transportSub?.cancel();
    _failAllPending('Transport switched');
    _isHandshaking = false;
    _protocolVersion = 2;
    _decoder.reset();
    _transport = newTransport;
    _bindTransport(_transport);
  }

  void _bindTransport(Sk18Transport transport) {
    _transportSub?.cancel();
    _transportSub = transport.incomingBytes.listen(_onIncomingBytes);
  }

  /// Performs the fast 37-byte V1 abort -> V2 `getInfo` handshake, with automatic
  /// fallback to Protocol V1 (`CMD_VALUE_FIND_DEVICE`) for stock `V2.29` hardware
  /// and a 128 KB buffer-flush retry if a V2 unit's receive buffer was wedged.
  Future<Sk18DeviceInfo> connectAndHandshake(String portPath) async {
    _isHandshaking = true;
    _protocolVersion = 2;
    _decoder.reset();
    await _transport.connect(portPath);

    try {
      // 1. Immediately send the 37-byte ASCII abort sequence
      await _transport.writeBytes(ProtocolV2Codec.encodeV1AbortCommand());

      if (!_transport.isSimulator) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }

      // 2. On simulator or synthetic short-timeout tests, run a single V2 getInfo
      if (_transport.isSimulator ||
          requestTimeout < const Duration(milliseconds: 500)) {
        final info = await _getInfoV2(timeout: requestTimeout);
        _isHandshaking = false;
        return info;
      }

      // 3. On hardware serial ports, try V2 getInfo first
      try {
        final info = await _getInfoV2(
          timeout: const Duration(milliseconds: 1000),
        );
        _isHandshaking = false;
        return info;
      } on TimeoutException {
        // 3a. Probe Protocol V1 (for stock V2.29 MK10 / SK18 firmware)
        final v1Info = await _tryHandshakeV1(
          timeout: const Duration(milliseconds: 800),
        );
        if (v1Info != null) {
          _protocolVersion = 1;
          _isHandshaking = false;
          return v1Info;
        }

        // 3b. Flush any interrupted V2 payload left in m_buffer_new and retry V2 getInfo
        await _transport.writeBytes(
          ProtocolV2Codec.encodeV2BufferFlushSequence(),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final retryInfo = await _getInfoV2(
          timeout: const Duration(milliseconds: 1200),
        );
        _isHandshaking = false;
        return retryInfo;
      }
    } catch (_) {
      _isHandshaking = false;
      await disconnect();
      rethrow;
    }
  }

  Future<void> disconnect() async {
    _isHandshaking = false;
    _protocolVersion = 2;
    _failAllPending('Disconnected');
    _decoder.reset();
    await _transport.disconnect();
  }

  /// Sends a JSON-RPC request (`cmd = 101`) and awaits the correlated response by packet `id`.
  Future<Map<String, dynamic>> sendRpcRequest(
    String method, {
    Map<String, dynamic>? parameters,
    Duration? timeout,
  }) async {
    if (!_transport.isConnected) {
      throw StateError('SK18 transport is not connected.');
    }

    final packetId = _nextPacketId++;
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[packetId] = completer;

    final effectiveTimeout = timeout ?? requestTimeout;
    _requestTimers[packetId] = Timer(effectiveTimeout, () {
      _requestTimers.remove(packetId);
      final pending = _pendingRequests.remove(packetId);
      if (pending != null && !pending.isCompleted) {
        pending.completeError(
          TimeoutException('RPC "$method" (id=$packetId) timed out'),
        );
      }
    });

    final frame = ProtocolV2Codec.encodeJsonRequest(
      id: packetId,
      method: method,
      parameters: parameters,
    );

    try {
      await _transport.writeBytes(frame);
    } catch (e) {
      _requestTimers.remove(packetId)?.cancel();
      _pendingRequests.remove(packetId);
      rethrow;
    }

    return completer.future;
  }

  /// Sends a `CMD_VALUE_SHOW_JPG` (`cmd = 100`) baseline JPEG frame and returns the packet `id`.
  Future<int> sendJpegFrame(Uint8List jpegBytes) async {
    if (!_transport.isConnected) {
      throw StateError('SK18 transport is not connected.');
    }
    final packetId = _nextPacketId++;
    if (isV1Protocol) {
      if (!_frameAckController.isClosed) {
        scheduleMicrotask(() {
          if (!_frameAckController.isClosed) {
            _frameAckController.add(packetId);
          }
        });
      }
      return packetId;
    }
    final frame = ProtocolV2Codec.encodeJpegFrame(
      id: packetId,
      jpegBytes: jpegBytes,
    );
    await _transport.writeBytes(frame);
    return packetId;
  }

  // --- Stock Protocol V2 & V1 Methods ---

  Future<Sk18DeviceInfo> getInfo() async {
    if (isV1Protocol) {
      final info = await _tryHandshakeV1(timeout: requestTimeout);
      if (info == null) {
        throw TimeoutException('V1 getInfo timed out');
      }
      return info;
    }
    return _getInfoV2(timeout: requestTimeout);
  }

  Future<Sk18DeviceInfo> _getInfoV2({Duration? timeout}) async {
    final resp = await sendRpcRequest('getInfo', timeout: timeout);
    final result =
        (resp['result'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    return Sk18DeviceInfo.fromGetInfoResult(result);
  }

  Future<Sk18DeviceInfo?> _tryHandshakeV1({required Duration timeout}) async {
    _v1FindDeviceTimer?.cancel();
    final completer = Completer<Map<String, String>>();
    _v1FindDeviceCompleter = completer;
    _v1FindDeviceTimer = Timer(timeout, () {
      _v1FindDeviceTimer = null;
      if (!completer.isCompleted) {
        completer.complete(const {});
      }
    });

    await _transport.writeBytes(
      ProtocolV2Codec.encodeV1Packet(cmd: ProtocolV2Codec.v1CmdFindDevice),
    );
    final map = await completer.future;
    _v1FindDeviceCompleter = null;
    if (map.isEmpty) {
      return null;
    }

    // Activate host connection mode in V1 firmware
    final connectJson = utf8.encode(jsonEncode({'connect': true}));
    await _transport.writeBytes(
      ProtocolV2Codec.encodeV1Packet(
        cmd: ProtocolV2Codec.v1CmdSendJson,
        payload: connectJson,
      ),
    );
    return Sk18DeviceInfo.fromV1ScreenMessage(map);
  }

  Future<void> setBacklight(int level) async {
    final clamped = level.clamp(0, 100);
    if (isV1Protocol) {
      _v1BacklightTimer?.cancel();
      final completer = Completer<void>();
      _v1BacklightCompleter = completer;
      _v1BacklightTimer = Timer(const Duration(milliseconds: 500), () {
        _v1BacklightTimer = null;
        if (!completer.isCompleted) {
          completer.complete();
        }
      });
      await _transport.writeBytes(
        ProtocolV2Codec.encodeV1Packet(
          cmd: ProtocolV2Codec.v1CmdSetBacklight,
          payload: ascii.encode('$clamped'),
        ),
      );
      await completer.future;
      _v1BacklightCompleter = null;
      return;
    }
    await sendRpcRequest('setBacklight', parameters: {'level': clamped});
  }

  Future<void> setVolume(int level) async {
    final clamped = level.clamp(0, 7);
    if (isV1Protocol) {
      return;
    }
    await sendRpcRequest('setVolume', parameters: {'level': clamped});
  }

  Future<void> keyboardInput(String inputString) async {
    if (inputString.isEmpty) return;
    if (isV1Protocol) {
      final jsonBytes = utf8.encode(jsonEncode({'qmk_string': inputString}));
      await _transport.writeBytes(
        ProtocolV2Codec.encodeV1Packet(
          cmd: ProtocolV2Codec.v1CmdSendJson,
          payload: jsonBytes,
        ),
      );
      return;
    }
    await sendRpcRequest(
      'keyboardInput',
      parameters: {'inputString': inputString},
    );
  }

  /// Queries `.wav` files stored on the SK18 using the firmware's exact `"suffixs"` key.
  Future<List<Sk18WavFileEntry>> getWavFiles() async {
    if (isV1Protocol) {
      return const [];
    }
    final resp = await sendRpcRequest(
      'getFilesBySuffix',
      parameters: {
        'suffixs': ['wav'],
      },
    );
    final result =
        (resp['result'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final rawList = (result['filePaths'] as List<dynamic>?) ?? const <dynamic>[];
    return rawList
        .whereType<Map<String, dynamic>>()
        .map(Sk18WavFileEntry.fromJson)
        .toList();
  }

  /// Uploads a `.wav` file in 64 KB (`65536`-byte) chunks via `saveToFile` followed
  /// by `setFileCRC`, automatically signaling `uploadStateChanges` so JPEG frame
  /// streaming pauses during the upload.
  Future<String> uploadWavFile({
    required String remoteFilePath,
    required Uint8List wavBytes,
    void Function(double progress)? onProgress,
  }) async {
    _activeUploadCount++;
    if (!_uploadStateController.isClosed) {
      _uploadStateController.add(true);
    }

    try {
      final totalLength = wavBytes.length;
      if (totalLength == 0) {
        await sendRpcRequest(
          'saveToFile',
          parameters: {
            'filePath': remoteFilePath,
            'seek': 0,
            'data': '',
          },
        );
        onProgress?.call(1.0);
      } else {
        int seek = 0;
        while (seek < totalLength) {
          final end = (seek + wavChunkSizeBytes < totalLength)
              ? seek + wavChunkSizeBytes
              : totalLength;
          final chunk = Uint8List.sublistView(wavBytes, seek, end);
          final b64Chunk = base64Encode(chunk);

          await sendRpcRequest(
            'saveToFile',
            parameters: {
              'filePath': remoteFilePath,
              'seek': seek,
              'data': b64Chunk,
            },
          );

          seek = end;
          onProgress?.call(seek / totalLength);
        }
      }

      final crcValue = ProtocolV2Codec.crc32(wavBytes).toString();
      await sendRpcRequest(
        'setFileCRC',
        parameters: {
          'filePath': remoteFilePath,
          'crc': crcValue,
        },
      );
      return crcValue;
    } finally {
      _activeUploadCount = (_activeUploadCount - 1).clamp(0, 1000);
      if (_activeUploadCount == 0 && !_uploadStateController.isClosed) {
        _uploadStateController.add(false);
      }
    }
  }

  Future<List<String>> deleteFiles(List<String> filePaths) async {
    if (filePaths.isEmpty) return const [];
    final resp = await sendRpcRequest(
      'deleteFiles',
      parameters: {'filePaths': filePaths},
    );
    final result =
        (resp['result'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final deleted = (result['deletedFiles'] as List<dynamic>?) ?? const [];
    return deleted.map((e) => e.toString()).toList();
  }

  Future<void> playAudio(String filePath) async {
    await sendRpcRequest('playAudio', parameters: {'filePath': filePath});
  }

  Future<void> stopAudio() async {
    await sendRpcRequest('stopAudio');
  }

  // --- Custom Firmware Companion Methods ---

  Future<Map<String, dynamic>> getLayoutConfig() async {
    final resp = await sendRpcRequest('getLayoutConfig');
    final result =
        (resp['result'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    return (result['config'] as Map<String, dynamic>?) ?? result;
  }

  Future<void> setLayoutConfig(Map<String, dynamic> config) async {
    await sendRpcRequest('setLayoutConfig', parameters: {'config': config});
  }

  Future<void> triggerKeyAction({
    required int col,
    required int row,
    required bool pressed,
  }) async {
    await sendRpcRequest(
      'triggerKeyAction',
      parameters: {
        'col': col,
        'row': row,
        'pressed': pressed,
      },
    );
  }

  void _onIncomingBytes(Uint8List chunk) {
    final packets = _decoder.addChunk(chunk);
    for (final pkt in packets) {
      if (pkt.isV1) {
        _handleIncomingV1Packet(pkt);
        continue;
      }

      if (pkt.isShowJpg) {
        if (!_frameAckController.isClosed) {
          _frameAckController.add(pkt.id);
        }
        continue;
      }

      if (pkt.isJson) {
        final json = pkt.decodeJson();
        if (json == null) continue;

        final ackMethod = json['ack_method'] as String?;
        if (ackMethod == 'updataDisplay') {
          if (!_frameAckController.isClosed) {
            _frameAckController.add(pkt.id);
          }
          continue;
        }

        final requestId = (json['requestId'] as num?)?.toInt() ?? pkt.id;
        int? matchedId;
        if (_pendingRequests.containsKey(requestId)) {
          matchedId = requestId;
        } else if (pkt.id == -1 &&
            (ackMethod != null || json.containsKey('errorString')) &&
            _pendingRequests.isNotEmpty) {
          matchedId = _pendingRequests.keys.first;
        }

        if (ackMethod != null || matchedId != null) {
          final targetId = matchedId ?? requestId;
          _requestTimers.remove(targetId)?.cancel();
          final completer = _pendingRequests.remove(targetId);
          if (completer != null && !completer.isCompleted) {
            final success =
                (json['success'] as bool?) ?? !json.containsKey('errorString');
            if (success) {
              completer.complete(json);
            } else {
              completer.completeError(
                StateError(
                  json['errorString'] as String? ?? 'RPC $ackMethod failed',
                ),
              );
            }
          }
          continue;
        }

        final eventMethod = json['method'] as String?;
        if (eventMethod != null) {
          final params =
              (json['parameters'] as Map<String, dynamic>?) ??
              const <String, dynamic>{};
          if (!_eventController.isClosed) {
            _eventController.add(
              Sk18DeviceEvent(method: eventMethod, parameters: params),
            );
          }
        }
      }
    }
  }

  void _handleIncomingV1Packet(ProtocolV2Packet pkt) {
    if (pkt.cmd == ProtocolV2Codec.v1CmdFindDevice ||
        pkt.cmd == ProtocolV2Codec.v1CmdGetScreenMessage) {
      final map = pkt.decodeV1StringMap();
      _v1FindDeviceTimer?.cancel();
      _v1FindDeviceTimer = null;
      final completer = _v1FindDeviceCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete(map);
      }
      return;
    }

    if (pkt.cmd == ProtocolV2Codec.v1CmdSetBacklight) {
      _v1BacklightTimer?.cancel();
      _v1BacklightTimer = null;
      final completer = _v1BacklightCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
      return;
    }

    if (pkt.cmd == ProtocolV2Codec.v1CmdProactiveEscalation) {
      final items = pkt.decodeV1ProactiveEscalation();
      for (final item in items) {
        if (item['type'] == 'keyState' && !_eventController.isClosed) {
          final col = (item['col'] as num?)?.toInt() ?? 0;
          final row = (item['row'] as num?)?.toInt() ?? 0;
          final pressedRaw = item['pressed'];
          final pressed =
              (pressedRaw is bool && pressedRaw) ||
              (pressedRaw is num && pressedRaw != 0);
          _eventController.add(
            Sk18DeviceEvent(
              method: 'keyStateChanged',
              parameters: {
                'col': col,
                'row': row,
                'pressed': pressed,
              },
            ),
          );
        }
      }
      return;
    }
  }

  void _failAllPending(String reason) {
    _v1FindDeviceTimer?.cancel();
    _v1FindDeviceTimer = null;
    final v1Find = _v1FindDeviceCompleter;
    _v1FindDeviceCompleter = null;
    if (v1Find != null && !v1Find.isCompleted) {
      v1Find.complete(const {});
    }

    _v1BacklightTimer?.cancel();
    _v1BacklightTimer = null;
    final v1Bl = _v1BacklightCompleter;
    _v1BacklightCompleter = null;
    if (v1Bl != null && !v1Bl.isCompleted) {
      v1Bl.complete();
    }

    for (final timer in _requestTimers.values) {
      timer.cancel();
    }
    _requestTimers.clear();
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError(reason));
      }
    }
    _pendingRequests.clear();
  }

  void dispose() {
    _transportSub?.cancel();
    _failAllPending('Sk18RpcClient disposed');
    if (!_eventController.isClosed) {
      _eventController.close();
    }
    if (!_frameAckController.isClosed) {
      _frameAckController.close();
    }
    if (!_uploadStateController.isClosed) {
      _uploadStateController.close();
    }
  }
}
