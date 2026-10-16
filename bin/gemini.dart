import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:proper_filesize/proper_filesize.dart';
import 'package:to_hex_string/to_hex_string.dart';
import 'package:xxh3/xxh3.dart';

late ArgResults args;
void log(Object? o) {
  if (args['verbose']) stderr.writeln(o);
}

Future<bool> isSmbSymlink(File file, int size) async {
  // Minshall+French links store XSym, target byte length, MD5, then target bytes.
  if (size != 1067) return false;
  final handle = await file.open();
  try {
    final bytes = await handle.read(1067);
    if (bytes.length != 1067) return false;
    final header = RegExp(r'^XSym\n([0-9]{4})\n([0-9a-f]{32})\n')
        .firstMatch(latin1.decode(bytes));
    if (header == null) return false;
    final length = int.parse(header[1]!);
    if (length < 1 || length > 1024) return false;
    final target = bytes.sublist(header.end, header.end + length);
    return md5.convert(target).toString() == header[2];
  } finally {
    await handle.close();
  }
}

Stream<(String, int)> readFiles(Directory dir) async* {
  try {
    await for (final fse in dir.list(followLinks: false)) {
      log('Listing: ${fse.path}');
      try {
        if (fse is Directory) {
          yield* readFiles(fse);
        } else if (fse is File) {
          final stat = await fse.stat();
          if (stat.type == FileSystemEntityType.notFound) {
            throw FileSystemException('Cannot stat file', fse.path);
          }
          if (stat.type != FileSystemEntityType.file) continue;
          if (!args['skip-smb-symlinks'] ||
              !await isSmbSymlink(fse, stat.size)) {
            yield (fse.path, stat.size);
          }
        } else if (fse is! Link) {
          throw 'file system entry is neither file nor dir nor link: ${fse.runtimeType}';
        }
      } catch (e, st) {
        if (args['fail']) rethrow;
        stderr.writeln('readFiles $fse\n$e\n$st');
      }
    }
  } catch (e, st) {
    if (args['fail']) {
      rethrow;
    } else {
      stderr.writeln('readFiles $dir\n$e\n$st');
    }
  }
}

/// gives us a map: size → set (path, hash)
/// automatically filters for everything that is at least a duplicate in size
/// filters out everything below [minSize]
Map<int, Iterable<(String, int?)>> orderAndHash(
    Iterable<(String, int)> sizes, num minSize) {
  final files = <int, Set<(String, int?)>>{};
  for (final (path, size) in sizes) {
    if (size < minSize) {
    } else if (!files.containsKey(size)) {
      files[size] = {(path, null)};
    } else {
      if (files[size]!.length < 2) {
        final file = files[size]!.first;
        try {
          log('Hashing: ${file.$1}');
          files[size] = {(file.$1, xxh3(File(file.$1).readAsBytesSync()))};
        } catch (e, st) {
          stderr.writeln('orderAndHash(${file.$1}/)\n$e\n$st');
          // TODO: i think we need to remove
        }
      }
      // NOTE: this could be optimized to not hash if we couldn't hash `first`
      //       but that is such an edge case let's ignore it for now
      try {
        log('Hashing: $path');
        files[size]!.add((path, xxh3(File(path).readAsBytesSync())));
      } catch (e, st) {
        stderr.writeln('orderAndHash($path/)\n$e\n$st');
      }
    }
  }
  files.removeWhere((key, value) => value.length < 2);
  return files;
}

Map<int, Set<String>> orderByHash(Iterable<(String, int?)> files) {
  final hashes = <int, Set<String>>{};
  for (final (path, hash) in files) {
    if (hashes.containsKey(hash)) {
      hashes[hash]!.add(path);
    } else {
      hashes[hash!] = {path};
    }
  }
  return hashes;
}

extension Flatten<T> on Iterable<Stream<T>> {
  Stream<T> flatten() async* {
    for (final i in this) {
      yield* i;
    }
  }
}

extension NotEmptyOr<T> on Iterable<T> {
  Iterable<T> notEmptyOr(T e) => isEmpty ? [e] : this;
}

num parseFilesize(String s) {
  s = s.toUpperCase();
  s = (s.endsWith('B') ? s : '${s}B').replaceAll('I', 'i');
  return FileSize.parse(s).size;
}

BaseType deduceBase(String s) {
  s = s.toLowerCase();
  final bin = s.contains(RegExp('[c-z]')) ? s.contains('i') : true;
  return bin ? BaseType.binary : BaseType.metric;
}

void main(List<String> arguments) async {
  final parser = ArgParser()
    // TODO: add options like comparing names/only sizes/...
    ..addFlag('verbose', abbr: 'v', help: 'print everything we do')
    ..addFlag('fail', abbr: 'f', help: 'fail on file scanning errors')
    ..addFlag('skip-smb-symlinks',
        help: 'detect and skip Minshall+French SMB symlink files (slower)')
    // TODO:
    //..addFlag('zeros', abbr: '0', help: 'show all empty files as duplicates')
    ..addOption('min-size',
        abbr: 'm',
        help: 'all files below this size are ignored',
        defaultsTo: '1')
    // TODO: ignore system
    // TODO: --version
    ..addFlag('help',
        abbr: 'h', help: 'displays usage and options', negatable: false);
  args = parser.parse(arguments);
  if (args['help']) {
    stderr.writeln('gemini [options] [directory1 ...]');
    stderr.writeln();
    stderr.writeln(parser.usage);
    return;
  }
  final rf = args.rest
      .map(Directory.new)
      // FIXME: this causes absolute paths
      .notEmptyOr(Directory.current)
      .map(readFiles)
      .flatten();
  final allFiles =
      orderAndHash(await rf.toList(), parseFilesize(args['min-size']));
  for (final files in allFiles.entries) {
    if (files.value.length < 2) continue;
    final hashes = orderByHash(files.value);
    for (final hash in hashes.entries) {
      if (hash.value.length < 2) continue;
      final unit =
          Unit.auto(size: files.key, baseType: deduceBase(args['min-size']));
      print('${hash.key.toHexString(pad: true)} '
          '(${FileSize.fromBytes(files.key).toString(decimals: 0, unit: unit)}):');
      hash.value.map((d) => '    $d').forEach(print);
    }
  }
}
