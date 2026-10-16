# gemini

A tool for finding duplicate files.

## Installing

```sh
dart pub global activate gemini
```

## Usage

```sh
gemini [options] [directory ...]
```

Native symlinks are always skipped. Use `--skip-smb-symlinks` to also detect and
skip Minshall+French SMB links exposed as ordinary files. This is off by default
because it reads each 1,067-byte file to validate the stored target and MD5
checksum.
