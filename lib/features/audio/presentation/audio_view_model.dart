// ignore_for_file: prefer_initializing_formals

import 'dart:typed_data';

import '../../../core/protocol/sk18_rpc_client.dart';
import '../../device/data/device_repository.dart';
import '../../studio/presentation/studio_session.dart';

class AudioViewModel extends StudioSubViewModel {
  final DeviceRepository _deviceRepository;
  double? _wavUploadProgress;

  AudioViewModel({
    required StudioSession session,
    required DeviceRepository deviceRepository,
  }) : _deviceRepository = deviceRepository,
       super(session);

  List<Sk18WavFileEntry> get wavFiles => _deviceRepository.wavFiles;
  double? get wavUploadProgress => _wavUploadProgress;

  Future<void> uploadWavBytes({
    required String fileName,
    required Uint8List wavBytes,
  }) async {
    final sanitized = fileName.endsWith('.wav') ? fileName : '$fileName.wav';
    final remotePath = sanitized.startsWith('/data/sound/')
        ? sanitized
        : '/data/sound/$sanitized';

    _wavUploadProgress = 0.0;
    session.setStatus('Uploading $remotePath...');
    notify(markCanvasDirty: false);

    try {
      final crc = await _deviceRepository.uploadWavFile(
        remoteFilePath: remotePath,
        wavBytes: wavBytes,
        onProgress: (progress) {
          _wavUploadProgress = progress;
          notify(markCanvasDirty: false);
        },
      );
      session.setStatus('Uploaded $remotePath (CRC32: $crc)');
    } catch (e) {
      session.setStatus('WAV upload failed: $e', isError: true);
    } finally {
      _wavUploadProgress = null;
      notify(markCanvasDirty: false);
    }
  }

  Future<void> uploadGeneratedSampleWav(String name) async {
    final sampleBytes = Uint8List(4096);
    for (int i = 0; i < sampleBytes.length; i++) {
      sampleBytes[i] = (i * 17) & 0xFF;
    }
    await uploadWavBytes(fileName: name, wavBytes: sampleBytes);
  }

  Future<void> playWavFile(String remoteFilePath) async {
    try {
      await _deviceRepository.playAudio(remoteFilePath);
      session.setStatus('Playing $remoteFilePath');
    } catch (e) {
      session.setStatus('Play audio error: $e', isError: true);
    }
    notify(markCanvasDirty: false);
  }

  Future<void> stopWavPlayback() async {
    try {
      await _deviceRepository.stopAudio();
      session.setStatus('Stopped device audio');
    } catch (e) {
      session.setStatus('Stop audio error: $e', isError: true);
    }
    notify(markCanvasDirty: false);
  }

  Future<void> deleteWavFile(String remoteFilePath) async {
    try {
      await _deviceRepository.deleteWavFiles([remoteFilePath]);
      session.setStatus('Deleted $remoteFilePath');
    } catch (e) {
      session.setStatus('Delete file error: $e', isError: true);
    }
    notify(markCanvasDirty: false);
  }
}
