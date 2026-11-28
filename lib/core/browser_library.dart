import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'browser_address.dart';

class BrowserVisit {
  const BrowserVisit(this.url, this.when);
  final String url;
  final DateTime when;
}

/// Local-only URLs without query strings/fragments. No node or auth secrets.
class BrowserLibrary {
  BrowserLibrary({File? file}) : _file = file;
  final File? _file;
  final List<BrowserVisit> _history = [];
  final Set<String> _bookmarks = {};
  Future<void>? _pendingWrite;
  bool _dirty = false;
  bool storageFailed = false;

  List<BrowserVisit> get history => List.unmodifiable(_history.reversed);
  List<String> get bookmarks => List.unmodifiable(_bookmarks);
  bool get persistent => _file != null && !storageFailed;

  static String? savedUrl(String input) {
    final uri = browserAddress(input);
    if (uri == null) return null;
    return uri.toString().split(RegExp(r'[?#]')).first;
  }

  static Future<BrowserLibrary> open() async {
    try {
      const channel = MethodChannel('clashbrowser/storage/v1');
      final path = await channel.invokeMethod<String>('directory');
      if (path == null || path.isEmpty || !Directory(path).isAbsolute) {
        throw StateError('App storage unavailable');
      }
      final library = BrowserLibrary(file: File('$path/browser-library-v1.json'));
      await library.restore();
      return library;
    } catch (_) {
      return BrowserLibrary()..storageFailed = true;
    }
  }

  Future<void> restore() async {
    final file = _file;
    if (file == null || !await file.exists()) return;
    try {
      final raw = jsonDecode(await file.readAsString()) as Map;
      if (raw['version'] != 1) throw const FormatException('Unknown version');
      final history = <BrowserVisit>[];
      final bookmarks = <String>{};
      for (final item in raw['history'] as List) {
        final url = savedUrl(item['url'] as String);
        final when = DateTime.tryParse(item['when'] as String);
        if (url != null && when != null) history.add(BrowserVisit(url, when));
      }
      for (final item in raw['bookmarks'] as List) {
        final url = savedUrl(item as String);
        if (url != null) bookmarks.add(url);
      }
      _history..clear()..addAll(history);
      _bookmarks..clear()..addAll(bookmarks);
    } catch (_) {
      // Do not overwrite a corrupted/unknown-version file automatically.
      storageFailed = true;
    }
  }

  bool containsBookmark(String url) => _bookmarks.contains(savedUrl(url));

  Future<void> record(String input) {
    final url = savedUrl(input);
    if (url == null) return Future.value();
    if (_history.isNotEmpty && _history.last.url == url) return Future.value();
    _history.add(BrowserVisit(url, DateTime.now().toUtc()));
    return _save();
  }

  Future<void> toggleBookmark(String input) {
    final url = savedUrl(input);
    if (url == null) return Future.value();
    if (!_bookmarks.remove(url)) _bookmarks.add(url);
    return _save();
  }

  Future<void> clearHistory() {
    _history.clear();
    return _save();
  }

  Future<void> removeBookmark(String url) {
    _bookmarks.remove(url);
    return _save();
  }

  Future<void> flush() => _pendingWrite ?? Future<void>.value();

  Future<void> _save() {
    if (_file == null || storageFailed) return Future<void>.value();
    _dirty = true;
    // A single writer drains the latest state. Calls arriving before the
    // snapshot is captured share one write, without a timer or size threshold.
    return _pendingWrite ??= Future<void>.microtask(_drainWrites);
  }

  Future<void> _drainWrites() async {
    final file = _file!;
    try {
      await file.parent.create(recursive: true);
      while (_dirty && !storageFailed) {
        _dirty = false;
        final snapshot = jsonEncode({
          'version': 1,
          'history': [for (final visit in _history)
            {'url': visit.url, 'when': visit.when.toIso8601String()}],
          'bookmarks': _bookmarks.toList(),
        });
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(snapshot, flush: true);
        await temp.rename(file.path);
        // Mutations during I/O set _dirty again; never lose the newer state.
      }
    } catch (_) {
      storageFailed = true;
    } finally {
      _pendingWrite = null;
    }
  }
}
