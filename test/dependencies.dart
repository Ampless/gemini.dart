import 'dart:io';

import '../bin/gemini.dart' as gemini;

Future<void> main() async {
  assert(gemini.parseFilesize('1k') == 1000);
  assert(gemini.parseFilesize('1Ki') == 1024);
  assert(gemini.parseFilesize('1.5mB') == 1500000);

  final fixture = File.fromUri(Platform.script.resolve('justarandomfile'));
  final link = Link.fromUri(Platform.script.resolve('linktorandomfile'));
  assert(await link.target() == 'justarandomfile');
  assert(await File(link.path).readAsString() == await fixture.readAsString());

  final directory = Directory.systemTemp.createTempSync('gemini-dependencies-');
  try {
    final first = File('${directory.path}/first')
      ..writeAsStringSync('x' * 2048);
    final second = File('${directory.path}/second')
      ..writeAsBytesSync(first.readAsBytesSync());
    final alias = Link('${directory.path}/alias')..createSync('first');
    final script = File.fromUri(Platform.script.resolve('../bin/gemini.dart'));
    for (final (minimum, size) in [('1KB', '2 KB'), ('1KiB', '2 KiB')]) {
      final result = Process.runSync(Platform.resolvedExecutable, [
        'run',
        script.path,
        '-m',
        minimum,
        directory.path,
      ], workingDirectory: script.parent.parent.path);
      assert(result.exitCode == 0, result.stderr);
      final output = result.stdout.toString();
      assert(output.contains('($size):'), output);
      assert(output.contains(first.path), output);
      assert(output.contains(second.path), output);
      assert(!output.contains(alias.path), output);
    }
  } finally {
    directory.deleteSync(recursive: true);
  }
  stdout.writeln('Dependency and symlink checks passed.');
}
