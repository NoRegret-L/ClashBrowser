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
}
