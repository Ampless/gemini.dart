import 'dart:io';

import 'package:proper_filesize/proper_filesize.dart';
import 'package:to_hex_string/to_hex_string.dart';
import 'package:xxh3/xxh3.dart';

class CheckingFile {
  String path;
  int hash;
  int size;

  CheckingFile({required this.path, required this.hash, required this.size});

  static Future<CheckingFile> read(File file) async => CheckingFile(
        path: file.path,
        hash: await file.readAsBytes().then(xxh3),
        size: await file.length(),
      );

  bool isDuplicateOf(CheckingFile o) => o.hash == hash && o.size == size;
}

Stream<Future<CheckingFile>> readFiles(Directory dir) async* {
  for (final fse in await dir.list().toList()) {
    if (fse is Directory) {
      yield* readFiles(fse);
    } else if (fse is File) {
      yield CheckingFile.read(fse);
    } else if (fse is Link) {
    } else {
      throw 'file system entry is neither file nor dir nor link: ${fse.runtimeType}';
    }
  }
}

Stream<T> flatten<T>(Iterable<Stream<T>> s) async* {
  for (final i in s) {
    yield* i;
  }
}

// TODO: think about a default like (args = []) ⇒ (args ← ['.'])
void main(List<String> args) async {
  final rf = await flatten(args.map((d) => readFiles(Directory(d)))).toList();
  final files = await Future.wait(rf);
  while (files.isNotEmpty) {
    final file = files.first;
    final dups = files.where((f) => f.isDuplicateOf(file));
    if (dups.length > 1) {
      print('${file.hash.toHexString(pad: true)} '
          '(${ProperFilesize.generateHumanReadableFilesize(file.size, decimals: 0)}):');
      dups.map((d) => '    ${d.path}').forEach(print);
    }
    files.removeWhere((f) => f.isDuplicateOf(file));
  }
}
