## 2.0.0

- Added `--verbose`/`-v` flag
- Performance optimizations big time (a FreeBSD Git with 3GiB in 100k files now
  takes just 12s on an M1-series chip)
- Doesn't crash for too many open files anymore

## 1.1.0

- Switched from SHA512 to XXH3
- Removed the 1KiB file limit (files below 1KiB are now also checked)
- File sizes are now also listed in the output
- General performance optimizations

## 1.0.1

- Fixed the `gemini` executable not being registered in the `pubspec`

## 1.0.0

- Initial version
