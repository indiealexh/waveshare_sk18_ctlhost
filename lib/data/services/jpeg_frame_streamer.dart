import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../domain/models/ha_entity_state.dart';
import '../../domain/models/sk18_device_info.dart';
import '../../domain/models/sk18_geometry.dart';
import '../../domain/models/sk18_profile.dart';
import '../../ui/core/rendering/sk18_canvas_painter.dart';
import 'sk18_rpc_client.dart';

class _JpegIsolateRequest {
  final int width;
  final int height;
  final int quality;
  final TransferableTypedData rgbaData;

  const _JpegIsolateRequest({
    required this.width,
    required this.height,
    required this.quality,
    required this.rgbaData,
  });
}

Uint8List _encodeRgbaToBaselineJpegInIsolate(_JpegIsolateRequest req) {
  final rgbaBytes = req.rgbaData.materialize().asUint8List();
  final frameImage = img.Image.fromBytes(
    width: req.width,
    height: req.height,
    bytes: rgbaBytes.buffer,
    bytesOffset: rgbaBytes.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodeJpg(frameImage, quality: req.quality);
}

/// Manages dirty-flagged offscreen GPU frame rasterization, background `Isolate`
/// baseline JPEG encoding (`quality: 85`), `CMD_VALUE_SHOW_JPG` (`cmd = 100`)
/// ACK flow control with a `500 ms` watchdog timer, and automatic streaming pause
/// while chunked `saveToFile` WAV uploads are active.
class JpegFrameStreamer {
  static const int defaultJpegQuality = 85;
  static const Duration defaultAckWatchdogDuration = Duration(milliseconds: 500);

  final Sk18RpcClient rpcClient;
  final Duration ackWatchdogDuration;
  final bool useBackgroundIsolate;

  StreamSubscription<int>? _ackSub;
  StreamSubscription<bool>? _uploadSub;
  Timer? _ackWatchdogTimer;

  bool _isDirty = false;
  bool _isEncodingFrame = false;
  bool _waitingForFrameAck = false;
  bool _pausedForUpload = false;
  int _framesSentCount = 0;
  int _watchdogRecoveryCount = 0;

  Future<Sk18RawFrameBuffer> Function()? _frameRenderCallback;

  JpegFrameStreamer({
    required this.rpcClient,
    this.ackWatchdogDuration = defaultAckWatchdogDuration,
    this.useBackgroundIsolate = true,
  }) {
    _ackSub = rpcClient.frameAcks.listen(_onFrameAckReceived);
    _uploadSub = rpcClient.uploadStateChanges.listen(_onUploadStateChanged);
    _pausedForUpload = rpcClient.isUploadingFile;
  }

  bool get isDirty => _isDirty;
  bool get isEncodingFrame => _isEncodingFrame;
  bool get waitingForFrameAck => _waitingForFrameAck;
  bool get isPausedForUpload => _pausedForUpload || rpcClient.isUploadingFile;
  int get framesSentCount => _framesSentCount;
  int get watchdogRecoveryCount => _watchdogRecoveryCount;

  /// Encodes a raw RGBA buffer to baseline JPEG (`quality: 85`), offloading work
  /// to a background `Isolate` via `TransferableTypedData` when `useIsolate = true`.
  static Future<Uint8List> encodeRgbaToBaselineJpeg(
    Sk18RawFrameBuffer rawFrame, {
    int quality = defaultJpegQuality,
    bool useIsolate = true,
  }) async {
    final request = _JpegIsolateRequest(
      width: rawFrame.width,
      height: rawFrame.height,
      quality: quality,
      rgbaData: TransferableTypedData.fromList([rawFrame.rgbaBytes]),
    );
    if (!useIsolate) {
      return _encodeRgbaToBaselineJpegInIsolate(request);
    }
    return Isolate.run(() => _encodeRgbaToBaselineJpegInIsolate(request));
  }

  /// Convenience helper that rasterizes the SK18 or MK10 canvas on the GPU (with 90°
  /// pre-rotation when targeting a portrait framebuffer) and encodes a baseline JPEG.
  static Future<Uint8List> renderPageToJpeg({
    required Sk18Page page,
    required bool authoringInLandscape,
    required bool rotateForPortraitDevice,
    WaveshareModel model = WaveshareModel.sk18,
    bool upsideDown = false,
    Map<String, HaEntityState> haEntities = const {},
    Set<int> pressedKeyIndices = const {},
    List<Sk18KeyRect>? rawDeviceRects,
    int offsetX = 0,
    int offsetY = 0,
    String profileName = 'SK18 Studio',
    String statusText = 'LIVE',
    String clockString = '12:00',
    int quality = defaultJpegQuality,
    bool useIsolate = true,
  }) async {
    final rawFrame = await Sk18CanvasRenderer.renderOffscreenRgba(
      page: page,
      authoringInLandscape: authoringInLandscape,
      rotateForPortraitDevice: rotateForPortraitDevice,
      model: model,
      upsideDown: upsideDown,
      haEntities: haEntities,
      pressedKeyIndices: pressedKeyIndices,
      rawDeviceRects: rawDeviceRects,
      offsetX: offsetX,
      offsetY: offsetY,
      profileName: profileName,
      statusText: statusText,
      clockString: clockString,
    );
    return encodeRgbaToBaselineJpeg(
      rawFrame,
      quality: quality,
      useIsolate: useIsolate,
    );
  }

  void setFrameRenderCallback(Future<Sk18RawFrameBuffer> Function() callback) {
    _frameRenderCallback = callback;
  }

  /// Clears any pending dirty or ACK-wait state when connecting or disconnecting.
  void resetState() {
    _isDirty = false;
    _clearAckWait();
  }

  /// Marks the visual state dirty and immediately flushes a frame if the streamer
  /// is connected, not currently encoding, not waiting for a frame ACK, and not
  /// paused for an active `saveToFile` WAV upload.
  Future<void> markDirtyAndPump() async {
    _isDirty = true;
    await _trySendNextDirtyFrame();
  }

  /// Pushes a pre-encoded JPEG frame through the ACK backpressure and upload-pause gates.
  Future<bool> sendEncodedJpegIfReady(Uint8List jpegBytes) async {
    if (!rpcClient.isConnected ||
        isPausedForUpload ||
        _isEncodingFrame ||
        _waitingForFrameAck) {
      _isDirty = true;
      return false;
    }

    _waitingForFrameAck = true;
    _startAckWatchdog();
    try {
      await rpcClient.sendJpegFrame(jpegBytes);
      _framesSentCount++;
      return true;
    } catch (_) {
      _clearAckWait();
      return false;
    }
  }

  Future<void> _trySendNextDirtyFrame() async {
    if (!_isDirty ||
        !rpcClient.isConnected ||
        rpcClient.isV1Protocol ||
        isPausedForUpload ||
        _isEncodingFrame ||
        _waitingForFrameAck) {
      return;
    }

    final renderCallback = _frameRenderCallback;
    if (renderCallback == null) return;

    _isDirty = false;
    _isEncodingFrame = true;

    try {
      final rawBuffer = await renderCallback();
      final jpegBytes = await encodeRgbaToBaselineJpeg(
        rawBuffer,
        useIsolate: useBackgroundIsolate,
      );

      if (!rpcClient.isConnected || isPausedForUpload) {
        _isDirty = true;
        return;
      }

      _waitingForFrameAck = true;
      _startAckWatchdog();
      await rpcClient.sendJpegFrame(jpegBytes);
      _framesSentCount++;
    } catch (_) {
      _clearAckWait();
    } finally {
      _isEncodingFrame = false;
      if (_isDirty &&
          !_waitingForFrameAck &&
          !isPausedForUpload &&
          rpcClient.isConnected) {
        unawaited(_trySendNextDirtyFrame());
      }
    }
  }

  void _onFrameAckReceived(int packetId) {
    _clearAckWait();
    if (_isDirty && !isPausedForUpload) {
      _trySendNextDirtyFrame();
    }
  }

  void _onUploadStateChanged(bool isUploading) {
    _pausedForUpload = isUploading;
    if (!isUploading && _isDirty && !_waitingForFrameAck && !_isEncodingFrame) {
      _trySendNextDirtyFrame();
    }
  }

  void _startAckWatchdog() {
    _ackWatchdogTimer?.cancel();
    _ackWatchdogTimer = Timer(ackWatchdogDuration, () {
      if (_waitingForFrameAck) {
        _waitingForFrameAck = false;
        _watchdogRecoveryCount++;
        if (_isDirty && !isPausedForUpload) {
          _trySendNextDirtyFrame();
        }
      }
    });
  }

  void _clearAckWait() {
    _ackWatchdogTimer?.cancel();
    _ackWatchdogTimer = null;
    _waitingForFrameAck = false;
  }

  void dispose() {
    _ackWatchdogTimer?.cancel();
    _ackWatchdogTimer = null;
    _ackSub?.cancel();
    _uploadSub?.cancel();
  }
}
