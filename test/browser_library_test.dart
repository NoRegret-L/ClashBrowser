import 'dart:io';
import 'package:clashbrowser/core/browser_library.dart';
import 'package:clashbrowser/core/browser_tabs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tabs have stable ids and independent last visited URLs', () {
    final tabs = BrowserTabs();
    tabs.visited('https://example.com/a');
    final first = tabs.active.id;
    tabs.add();
    final second = tabs.active.id;
    expect(second, isNot(first));
    expect(tabs.active.url, isNull);
    tabs.visited('https://example.org/b');
    tabs.activate(first);
    expect(tabs.active.url, 'https://example.com/a');
    tabs.close(first);
    expect(tabs.active.id, second);
    tabs.close(second);
    expect(tabs.tabs.length, 1);
    expect(tabs.active.url, isNull);
  });
  test('history and bookmarks survive reopening and do not store query or fragment', () async {
    final dir = await Directory.systemTemp.createTemp('browser-library-test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/library.json');
    final library = BrowserLibrary(file: file);
    await Future.wait([
      library.record('https://example.com/a?token=secret#private'),
      library.record('https://example.com/a?token=another'),
      library.toggleBookmark('https://example.com/a?token=secret#private'),
      library.record('https://example.org/b'),
    ]);
    expect(await file.readAsString(), isNot(contains('secret')));
    final reopened = BrowserLibrary(file: file);
    await reopened.restore();
    expect(reopened.history.map((v) => v.url),
      ['https://example.org/b', 'https://example.com/a']);
    expect(reopened.bookmarks, ['https://example.com/a']);
    await reopened.clearHistory();
    await reopened.removeBookmark('https://example.com/a');
    final cleared = BrowserLibrary(file: file);
    await cleared.restore();
    expect(cleared.history, isEmpty);
    expect(cleared.bookmarks, isEmpty);
  });
  test('invalid URLs never enter history or favorites', () async {
    final library = BrowserLibrary();
    await library.record('http://example.com');
    await library.toggleBookmark('https://user:pass@example.com');
    expect(library.history, isEmpty);
    expect(library.bookmarks, isEmpty);
  });
  test('corrupted library is not overwritten', () async {
    final dir = await Directory.systemTemp.createTemp('browser-library-corrupt');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/library.json');
    await file.writeAsString('broken');
    final library = BrowserLibrary(file: file);
    await library.restore();
    expect(library.storageFailed, isTrue);
    await library.record('https://example.com');
    expect(await file.readAsString(), 'broken');
  });

  test('burst mutations share one writer and flush the latest state', () async {
    final dir = await Directory.systemTemp.createTemp('browser-library-burst');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/library.json');
    final library = BrowserLibrary(file: file);
    final stopwatch = Stopwatch()..start();
    final first = library.record('https://example.com/0?token=secret');
    final writes = <Future<void>>[first];
    for (var i = 1; i < 64; i++) {
      writes.add(library.record('https://example.com/$i'));
    }
    writes.add(library.toggleBookmark('https://example.com/63#private'));
    expect(writes.every((write) => identical(write, first)), isTrue);
    expect(identical(library.flush(), first), isTrue);
    await library.flush();
    stopwatch.stop();
    // Diagnostic only: no arbitrary wall-clock pass/fail threshold.
    print('PERF browser_library burst 65 mutations: ${stopwatch.elapsedMicroseconds} us');
    final restored = BrowserLibrary(file: file);
    await restored.restore();
    expect(restored.history.length, 64);
    expect(restored.history.first.url, 'https://example.com/63');
    expect(restored.history.last.url, 'https://example.com/0');
    expect(restored.bookmarks, ['https://example.com/63']);
    final raw = await file.readAsString();
    expect(raw, isNot(contains('secret')));
    expect(raw, isNot(contains('private')));
    final second = library.clearHistory();
    expect(identical(second, first), isFalse);
    await second;
    await restored.restore();
    expect(restored.history, isEmpty);
    expect(restored.bookmarks, ['https://example.com/63']);
  });
}
