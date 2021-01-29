#!/usr/bin/env dart run

import 'dart:convert';
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

  dynamic toJson() => {'path': path, 'size': size, 'hash': hash};

  static CheckingFile fromJson(dynamic json) =>
      CheckingFile(path: json['path'], hash: json['hash'], size: json['size']);
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
    print(
      jsonEncode(
        (await readFiles(Directory(dir))).map((e) => e.toJson()).toList(),
      ),
    );
  }
}
