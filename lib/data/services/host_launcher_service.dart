import 'dart:io';

import '../../domain/models/button_action.dart';

class HostLaunchResult {
  final HostLauncherType launcherType;
  final String target;
  final List<String> args;
  final int exitCode;
  final String output;

  const HostLaunchResult({
    required this.launcherType,
    required this.target,
    this.args = const [],
    this.exitCode = 0,
    this.output = '',
  });
}

typedef HostProcessExecutor = Future<HostLaunchResult> Function(
  HostLauncherType launcherType,
  String target,
  List<String> args,
);

/// Executes Host Launcher button actions (`"app"`, `"script"`, `"url"`).
class HostLauncherService {
  final bool dryRun;
  final HostProcessExecutor? customExecutor;
  final List<HostLaunchResult> _history = <HostLaunchResult>[];

  HostLauncherService({
    this.dryRun = false,
    this.customExecutor,
  });

  List<HostLaunchResult> get history => List.unmodifiable(_history);

  Future<HostLaunchResult> execute({
    required HostLauncherType launcherType,
    required String target,
    List<String> args = const [],
  }) async {
    final cleanTarget = target.trim();
    if (cleanTarget.isEmpty) {
      const emptyRes = HostLaunchResult(
        launcherType: HostLauncherType.app,
        target: '',
        exitCode: -1,
        output: 'Target is empty',
      );
      _history.add(emptyRes);
      return emptyRes;
    }

    if (customExecutor != null) {
      final res = await customExecutor!(launcherType, cleanTarget, args);
      _history.add(res);
      return res;
    }

    if (dryRun) {
      final simulated = HostLaunchResult(
        launcherType: launcherType,
        target: cleanTarget,
        args: args,
        exitCode: 0,
        output: '[DryRun] Executed ${launcherType.jsonValue}: $cleanTarget ${args.join(' ')}'.trim(),
      );
      _history.add(simulated);
      return simulated;
    }

    try {
      ProcessResult procResult;
      switch (launcherType) {
        case HostLauncherType.app:
          if (Platform.isMacOS) {
            procResult = await Process.run('open', ['-a', cleanTarget, ...args]);
          } else if (Platform.isWindows) {
            procResult = await Process.run(
              'cmd',
              ['/c', 'start', '', cleanTarget, ...args],
            );
          } else {
            procResult = await Process.run(cleanTarget, args);
          }
          break;

        case HostLauncherType.script:
          if (Platform.isWindows) {
            procResult = await Process.run(
              'cmd',
              ['/c', cleanTarget, ...args],
            );
          } else {
            final fullCmd = args.isEmpty
                ? cleanTarget
                : '$cleanTarget ${args.join(' ')}';
            procResult = await Process.run('/bin/sh', ['-c', fullCmd]);
          }
          break;

        case HostLauncherType.url:
          if (Platform.isMacOS) {
            procResult = await Process.run('open', [cleanTarget]);
          } else if (Platform.isWindows) {
            procResult = await Process.run('cmd', ['/c', 'start', cleanTarget]);
          } else {
            procResult = await Process.run('xdg-open', [cleanTarget]);
          }
          break;
      }

      final result = HostLaunchResult(
        launcherType: launcherType,
        target: cleanTarget,
        args: args,
        exitCode: procResult.exitCode,
        output: (procResult.stdout?.toString() ?? '').trim(),
      );
      _history.add(result);
      return result;
    } catch (e) {
      final failed = HostLaunchResult(
        launcherType: launcherType,
        target: cleanTarget,
        args: args,
        exitCode: 1,
        output: e.toString(),
      );
      _history.add(failed);
      return failed;
    }
  }
}
