import 'dart:io';

void main() {
  final directory = Directory.systemTemp.createTempSync('gemini-fail-');
  try {
    final script = File.fromUri(Platform.script.resolve('../bin/gemini.dart'));
    final missing = '${directory.path}/missing';
    for (final flags in [
      <String>[],
      ['--no-fail'],
      ['--fail'],
      ['-f']
    ]) {
      final result = Process.runSync(
        Platform.resolvedExecutable,
        ['run', script.path, ...flags, missing],
        workingDirectory: script.parent.parent.path,
      );
      final shouldFail = flags.contains('--fail') || flags.contains('-f');
      assert((result.exitCode != 0) == shouldFail, '$flags: ${result.stderr}');
      assert(result.stderr.toString().contains(missing), result.stderr);
    }
    final success = Process.runSync(
      Platform.resolvedExecutable,
      ['run', script.path, '--fail', directory.path],
      workingDirectory: script.parent.parent.path,
    );
    assert(success.exitCode == 0, success.stderr);
  } finally {
    directory.deleteSync(recursive: true);
  }
  stdout.writeln('Fail flag checks passed.');
}
