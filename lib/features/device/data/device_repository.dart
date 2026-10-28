import 'dart:async';
import 'dart:typed_data';

import '../../../core/models/device_model_registry.dart';
import '../../../core/models/sk18_device_info.dart';
import '../../../core/protocol/serial_transport_service.dart';
import '../../../core/protocol/sk18_rpc_client.dart';
import '../../profiles/domain/sk18_profile.dart';
import 'jpeg_frame_streamer.dart';

class DeviceRepository {
  final SimulatorSerialTransport _simulatorTransport;
  final PosixSerialTransport _posixTransport;
  late final Sk18RpcClient _rpcClient;
  late final JpegFrameStreamer _frameStreamer;

  Sk18DeviceInfo _deviceInfo = Sk18DeviceInfo.defaultPortrait();
  List<Sk18WavFileEntry> _wavFiles = const [];
  List<String> _availablePorts = DeviceModelRegistry.instance.all
      .map((descriptor) => descriptor.simulatorPortUri)
      .toList();

  DeviceRepository({
    SimulatorSerialTransport? simulatorTransport,
    PosixSerialTransport? posixTransport,
    bool useBackgroundJpegIsolate = true,
  }) : _simulatorTransport = simulatorTransport ?? SimulatorSerialTransport(),
       _posixTransport = posixTransport ?? PosixSerialTransport() {
    _rpcClient = Sk18RpcClient(transport: _simulatorTransport);
    _frameStreamer = JpegFrameStreamer(
      rpcClient: _rpcClient,
      useBackgroundIsolate: useBackgroundJpegIsolate,
    );
  }

  Sk18RpcClient get rpcClient => _rpcClient;

  JpegFrameStreamer get frameStreamer => _frameStreamer;

  SimulatorSerialTransport get simulatorTransport => _simulatorTransport;

  Sk18DeviceInfo get deviceInfo => _deviceInfo;

  List<Sk18WavFileEntry> get wavFiles => List.unmodifiable(_wavFiles);

  List<String> get availablePorts => List.unmodifiable(_availablePorts);

  bool get isConnected => _rpcClient.isConnected;

  bool get isSimulator => _rpcClient.isSimulator;

  String get activePortPath => _rpcClient.transport.activePortPath;

  Stream<Sk18DeviceEvent> get deviceEvents => _rpcClient.deviceEvents;

  Future<List<String>> refreshPorts() async {
    _availablePorts = await SerialPortDiscovery.discoverPorts();
    return _availablePorts;
  }

  Future<Sk18DeviceInfo> connect(String portPath) async {
    _frameStreamer.resetState();
    await _rpcClient.disconnect();
    if (portPath == SerialPortDiscovery.simulatorPortUri ||
        portPath.startsWith('simulator://')) {
      _rpcClient.setTransport(_simulatorTransport);
    } else {
      _rpcClient.setTransport(_posixTransport);
    }

    try {
      _deviceInfo = await _rpcClient.connectAndHandshake(portPath);
      await refreshWavFiles();
      return _deviceInfo;
    } catch (_) {
      _wavFiles = const [];
      await _rpcClient.disconnect();
      rethrow;
    }
  }

  Future<void> disconnect() async {
    _frameStreamer.resetState();
    await _rpcClient.disconnect();
  }

  Future<List<Sk18WavFileEntry>> refreshWavFiles() async {
    if (!isConnected) return _wavFiles;
    _wavFiles = await _rpcClient.getWavFiles();
    return _wavFiles;
  }

  Future<void> setBacklight(int level) async {
    if (!isConnected) return;
    await _rpcClient.setBacklight(level);
  }

  Future<void> setVolume(int level) async {
    if (!isConnected) return;
    await _rpcClient.setVolume(level);
  }

  Future<void> sendKeyboardInput(String text) async {
    if (!isConnected || text.isEmpty) return;
    await _rpcClient.keyboardInput(text);
  }

  Future<String> uploadWavFile({
    required String remoteFilePath,
    required Uint8List wavBytes,
    void Function(double progress)? onProgress,
  }) async {
    final crc = await _rpcClient.uploadWavFile(
      remoteFilePath: remoteFilePath,
      wavBytes: wavBytes,
      onProgress: onProgress,
    );
    await refreshWavFiles();
    return crc;
  }

  Future<List<String>> deleteWavFiles(List<String> filePaths) async {
    final deleted = await _rpcClient.deleteFiles(filePaths);
    await refreshWavFiles();
    return deleted;
  }

  Future<void> playAudio(String filePath) async {
    if (!isConnected) return;
    await _rpcClient.playAudio(filePath);
  }

  Future<void> stopAudio() async {
    if (!isConnected) return;
    await _rpcClient.stopAudio();
  }

  /// Synchronizes the active profile to the SK18 / MK10.
  ///
  /// Attempts custom companion firmware `setLayoutConfig` (`sk18_config.json`) first.
  /// If the connected unit is running stock `V2.32` firmware (or responds with
  /// `Unknown method` / `Unsupported method` or times out on `setLayoutConfig`),
  /// falls back to applying hardware backlight and volume settings and streaming
  /// an immediate LCD frame.
  ///
  /// Returns `true` if `setLayoutConfig` succeeded on custom firmware, or `false`
  /// if the stock `V2.32` fallback was used.
  Future<bool> syncProfileToFirmware(
    Sk18Profile profile, {
    int pageIndex = 0,
  }) async {
    if (!isConnected) {
      throw StateError('SK18 device is not connected.');
    }

    final isStockHardwareFirmware =
        !isSimulator &&
        _deviceInfo.deviceVersion.toUpperCase().startsWith('V2.');
    if (isStockHardwareFirmware) {
      await _applyStockFirmwareSync(profile);
      return false;
    }

    final config = profile.toSk18ConfigJson(pageIndex: pageIndex);
    try {
      await _rpcClient.setLayoutConfig(config);
      if (!isSimulator) {
        await _frameStreamer.markDirtyAndPump();
      }
      return true;
    } on StateError catch (e) {
      if (e.message.contains('Unknown method') ||
          e.message.contains('Unsupported method')) {
        await _applyStockFirmwareSync(profile);
        return false;
      }
      rethrow;
    } on TimeoutException {
      await _applyStockFirmwareSync(profile);
      return false;
    }
  }

  Future<void> _applyStockFirmwareSync(Sk18Profile profile) async {
    await _rpcClient.setBacklight(profile.backlight);
    await _rpcClient.setVolume(profile.volume);
    if (!isSimulator) {
      await _frameStreamer.markDirtyAndPump();
    }
  }

  void dispose() {
    _frameStreamer.dispose();
    _rpcClient.dispose();
    _simulatorTransport.dispose();
    _posixTransport.dispose();
  }
}
