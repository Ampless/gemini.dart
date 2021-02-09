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

  bool isDuplicateOf(CheckingFile o) => o.hash == hash && o.size == size;
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
  var files = <CheckingFile>[];
  for (final dir in arguments) {
    files.addAll(await readFiles(Directory(dir)));
  }
  files = files.where((element) => element.size > 1024).toList();
  while (files.isNotEmpty) {
    final file = files.first;
    final dups = files.where((f) => f.isDuplicateOf(file));
    if (dups.length > 1) {
      print('${file.hash}:');
      for (final d in dups) {
        print('    ${d.path}');
      }
    }
    files.removeWhere((f) => f.isDuplicateOf(file));
  }
}
