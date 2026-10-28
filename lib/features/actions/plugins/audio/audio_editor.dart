import 'package:flutter/material.dart';

import '../../domain/action_plugin.dart';

class AudioEditor extends StatelessWidget {
  final ActionEditorScope scope;

  const AudioEditor({super.key, required this.scope});

  @override
  Widget build(BuildContext context) {
    final vm = scope.vm;
    final action = scope.action;
    final wavList = vm.wavFiles;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'On-Device WAV Audio Settings',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 8),
            const Text(
              'Device WAV File (/data/sound/*.wav)',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: wavList.map((entry) {
                final isSelected = action.audioFilePath == entry.filePath;
                return ChoiceChip(
                  key: Key('wav_chip_${entry.fileName}'),
                  label: Text(
                    entry.fileName,
                    style: const TextStyle(fontSize: 11),
                  ),
                  selected: isSelected,
                  onSelected: (_) {
                    scope.update(action.copyWith(audioFilePath: entry.filePath));
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            if (vm.wavUploadProgress != null) ...[
              LinearProgressIndicator(value: vm.wavUploadProgress),
              const SizedBox(height: 8),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  key: const Key('play_wav_btn'),
                  onPressed: () => vm.playWavFile(action.audioFilePath),
                  icon: const Icon(Icons.volume_up_rounded, size: 16),
                  label: const Text('Play WAV', style: TextStyle(fontSize: 12)),
                ),
                OutlinedButton.icon(
                  key: const Key('stop_wav_btn'),
                  onPressed: vm.stopWavPlayback,
                  icon: const Icon(Icons.stop_rounded, size: 16),
                  label: const Text('Stop', style: TextStyle(fontSize: 12)),
                ),
                OutlinedButton.icon(
                  key: const Key('upload_wav_btn'),
                  onPressed: () => vm.uploadGeneratedSampleWav('studio_beep.wav'),
                  icon: const Icon(Icons.cloud_upload_rounded, size: 16),
                  label: const Text(
                    'Upload WAV',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
