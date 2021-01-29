#!/usr/bin/env dart run

import 'dart:io';

import 'package:crypto/crypto.dart';

class CheckingFile {
  String path;
  List<int> hash;
  int size;

  CheckingFile({required this.path, required this.hash, required this.size});

  static Future<CheckingFile> read(File file) async => CheckingFile(
        path: file.path,
        hash: sha512.convert(await file.readAsBytes()).bytes,
        size: await file.length(),
      );

  @override
  String toString() => '{"$path",$size,'
      '${hash.first.toRadixString(16).padLeft(2, '0')}..'
      '${hash.last.toRadixString(16).padLeft(2, '0')}}';
}

Future<List<CheckingFile>> readFiles(Directory dir) async {
  final files = <CheckingFile>[];
  for (final fse in await dir.list().toList()) {
    if (fse is Directory) {
      files.addAll(await readFiles(fse));
    } else if (fse is File) {
      files.add(await CheckingFile.read(fse));
    } else {
      throw 'WTF A FSE IS SOMETHING WEIRD (${fse.runtimeType})';
    }
  }
  return files;
}

void main(List<String> arguments) async {
  for (final dir in arguments) {
    print(await readFiles(Directory(dir)));
  }
}
