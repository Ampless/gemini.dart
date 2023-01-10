import 'dart:io';

import 'package:args/args.dart';
import 'package:proper_filesize/proper_filesize.dart';
import 'package:to_hex_string/to_hex_string.dart';
import 'package:xxh3/xxh3.dart';

late ArgResults args;
void log(Object? o) {
  if (args['verbose']) stderr.writeln(o);
}

Stream<MapEntry<String, int>> readFiles(Directory dir) async* {
  try {
    await for (final fse in dir.list(followLinks: false)) {
      log('Listing: ${fse.absolute.path}');
      if (fse is Directory) {
        yield* readFiles(fse);
      } else if (fse is File) {
        yield MapEntry(fse.path, await fse.length());
      } else if (fse is! Link) {
        throw 'file system entry is neither file nor dir nor link: ${fse.runtimeType}';
      }
    }
  } catch (e, st) {
    stderr.writeln('readFiles $dir\n$e\n$st');
  }
}

/// gives us a map: size → set (path, hash)
/// automatically filters for everything that is at least a duplicate
/// filters out everything below [minSize]
Map<int, Set<MapEntry<String, int?>>> orderAndHash(
    Iterable<MapEntry<String, int>> sizes, num minSize) {
  final files = <int, Set<MapEntry<String, int?>>>{};
  for (final file in sizes) {
    final size = file.value;
    if (size < minSize) {
    } else if (!files.containsKey(size)) {
      files[size] = {MapEntry(file.key, null)};
    } else {
      if (files[size]!.length < 2) {
        final file = files[size]!.first;
        try {
          log('Hashing: ${file.key}');
          files[size] = {
            MapEntry(file.key, xxh3(File(file.key).readAsBytesSync()))
          };
        } catch (e, st) {
          stderr.writeln('orderAndHash(${file.key}/)\n$e\n$st');
          // TODO: i think we need to remove
        }
      }
      // NOTE: this could be optimized to not hash if we couldn't hash `first`
      //       but that is such an edge case let's ignore it for now
      try {
        log('Hashing: ${file.key}');
        files[size]!
            .add(MapEntry(file.key, xxh3(File(file.key).readAsBytesSync())));
      } catch (e, st) {
        stderr.writeln('orderAndHash(${file.key}/)\n$e\n$st');
      }
    }
  }
  files.removeWhere((key, value) => value.length < 2);
  return files;
}

Map<int, Set<String>> orderByHash(Iterable<MapEntry<String, int?>> files) {
  final hashes = <int, Set<String>>{};
  for (final file in files) {
    int hash = file.value!;
    if (!hashes.containsKey(hash)) {
      hashes[hash] = {file.key};
    } else {
      hashes[hash]!.add(file.key);
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

void main(List<String> arguments) async {
  final parser = ArgParser()
    // TODO: add options like comparing names/only sizes/...
    ..addFlag('verbose', abbr: 'v', help: 'print everything we do')
    // TODO:
    //..addFlag('zeros',
    //    abbr: '0', help: 'show all zero length files as duplicates')
    ..addOption('min-size',
        abbr: 'm',
        help: 'all files below this size are ignored',
        defaultsTo: '1')
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
          '(${ProperFilesize.generateHumanReadableFilesize(files.key, decimals: 0)}):');
      hash.value.map((d) => '    $d').forEach(print);
    }
  }
}
