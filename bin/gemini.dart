import 'dart:io';

import 'package:crypto/crypto.dart';

class CheckingFile {
  String path;
  String hash;
  int size;

  CheckingFile({required this.path, required this.hash, required this.size});

  static Future<CheckingFile> read(File file) async => CheckingFile(
        path: file.path,
        hash: sha512
            .convert(await file.readAsBytes())
            .bytes
            .map((e) => e.toRadixString(16).padLeft(2, '0'))
            .reduce((v1, v2) => v1 + v2),
        size: await file.length(),
      );

  bool isDuplicateOf(CheckingFile o) => o.hash == hash && o.size == size;
}

Stream<CheckingFile> readFiles(Directory dir) async* {
  for (final fse in await dir.list().toList()) {
    if (fse is Directory) {
      yield* readFiles(fse);
    } else if (fse is File) {
      yield await CheckingFile.read(fse);
    } else {
      throw 'file system entry is neither file nor dir: ${fse.runtimeType}';
    }
  }
}

Stream<T> flatten<T>(Iterable<Stream<T>> s) async* {
  for (final i in s) {
    yield* i;
  }
}

// TODO: no arguments causes a crash
void main(List<String> arguments) async {
  final rf = arguments.map((d) => readFiles(Directory(d)));
  final files = await flatten(rf).where((e) => e.size > 1024).toList();
  while (files.isNotEmpty) {
    final file = files.first;
    final dups = files.where((f) => f.isDuplicateOf(file));
    if (dups.length > 1) {
      print('${file.hash}:');
      dups.map((d) => '    ${d.path}').forEach(print);
    }
    files.removeWhere((f) => f.isDuplicateOf(file));
  }
}
