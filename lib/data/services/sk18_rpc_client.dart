// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../domain/models/sk18_device_info.dart';
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
  final Duration requestTimeout;

  Sk18RpcClient({
    required Sk18Transport transport,
    this.requestTimeout = const Duration(milliseconds: 2500),
  }) : _transport = transport {
    _bindTransport(_transport);
  }

  Sk18Transport get transport => _transport;
  bool get isConnected => _transport.isConnected;
  bool get isSimulator => _transport.isSimulator;
  bool get isUploadingFile => _activeUploadCount > 0;

  Stream<Sk18DeviceEvent> get deviceEvents => _eventController.stream;
  Stream<int> get frameAcks => _frameAckController.stream;
  Stream<bool> get uploadStateChanges => _uploadStateController.stream;

  void setTransport(Sk18Transport newTransport) {
    _transportSub?.cancel();
    _failAllPending('Transport switched');
    _decoder.reset();
    _transport = newTransport;
    _bindTransport(_transport);
  }

  void _bindTransport(Sk18Transport transport) {
    _transportSub?.cancel();
    _transportSub = transport.incomingBytes.listen(_onIncomingBytes);
  }

  /// Performs the fast 37-byte V1 abort -> V2 `getInfo` handshake.
  Future<Sk18DeviceInfo> connectAndHandshake(String portPath) async {
    _decoder.reset();
    await _transport.connect(portPath);

    // 1. Immediately send the 37-byte ASCII abort sequence
    await _transport.writeBytes(ProtocolV2Codec.encodeV1AbortCommand());

    // 2. Send getInfo to switch KeyboardDevice into Protocol V2 mode
    return getInfo();
  }

  Future<void> disconnect() async {
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
    final frame = ProtocolV2Codec.encodeJpegFrame(
      id: packetId,
      jpegBytes: jpegBytes,
    );
    await _transport.writeBytes(frame);
    return packetId;
  }

  // --- Stock Protocol V2 Methods ---

  Future<Sk18DeviceInfo> getInfo() async {
    final resp = await sendRpcRequest('getInfo');
    final result =
        (resp['result'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    return Sk18DeviceInfo.fromGetInfoResult(result);
  }

  Future<void> setBacklight(int level) async {
    final clamped = level.clamp(0, 100);
    await sendRpcRequest('setBacklight', parameters: {'level': clamped});
  }

  Future<void> setVolume(int level) async {
    final clamped = level.clamp(0, 7);
    await sendRpcRequest('setVolume', parameters: {'level': clamped});
  }

  Future<void> keyboardInput(String inputString) async {
    if (inputString.isEmpty) return;
    await sendRpcRequest(
      'keyboardInput',
      parameters: {'inputString': inputString},
    );
  }

  /// Queries `.wav` files stored on the SK18 using the firmware's exact `"suffixs"` key.
  Future<List<Sk18WavFileEntry>> getWavFiles() async {
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

        if (ackMethod != null || _pendingRequests.containsKey(pkt.id)) {
          _requestTimers.remove(pkt.id)?.cancel();
          final completer = _pendingRequests.remove(pkt.id);
          if (completer != null && !completer.isCompleted) {
            final success = json['success'] as bool? ?? true;
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

  void _failAllPending(String reason) {
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
