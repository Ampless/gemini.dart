import 'dart:io';

import 'package:args/args.dart';
import 'package:proper_filesize/proper_filesize.dart';
import 'package:to_hex_string/to_hex_string.dart';
import 'package:xxh3/xxh3.dart';

late ArgResults args;
void log(Object? o) {
  if (args['verbose']) stderr.writeln(o);
}

Stream<(String, int)> readFiles(Directory dir) async* {
  try {
    await for (final fse in dir.list(followLinks: false)) {
      log('Listing: ${fse.absolute.path}');
      if (fse is Directory) {
        yield* readFiles(fse);
      } else if (fse is File) {
        yield (fse.path, await fse.length());
      } else if (fse is! Link) {
        throw 'file system entry is neither file nor dir nor link: ${fse.runtimeType}';
      }
    }
  } catch (e, st) {
    stderr.writeln('readFiles $dir\n$e\n$st');
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
  final u = s.toUpperCase();
  s = (u.endsWith('B') ? u : '${u}B').replaceAll('I', 'i');
  return ProperFilesize.parseHumanReadableFilesize(s);
}

Bases deduceBase(String s) {
  s = s.toLowerCase();
  final bin = s.contains(RegExp('[c-z]')) ? s.contains('i') : true;
  return bin ? Bases.Binary : Bases.Metric;
}

void main(List<String> arguments) async {
  final parser = ArgParser()
    // TODO: add options like comparing names/only sizes/...
    ..addFlag('verbose', abbr: 'v', help: 'print everything we do')
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
      print('${hash.key.toHexString(pad: true)} '
          '(${ProperFilesize.generateHumanReadableFilesize(files.key, decimals: 0, base: deduceBase(args['min-size']))}):');
      hash.value.map((d) => '    $d').forEach(print);
    }
  }
}
