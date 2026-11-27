/// Logical tabs share one active native renderer; no background navigation.
class BrowserTab {
  BrowserTab(this.id);
  final int id;
  String? url;
}
class BrowserTabs {
  final List<BrowserTab> _tabs = [BrowserTab(0)];
  int _nextId = 1;
  int _activeId = 0;
  List<BrowserTab> get tabs => List.unmodifiable(_tabs);
  BrowserTab get active => _tabs.firstWhere((t) => t.id == _activeId);

  void add() {
    final tab = BrowserTab(_nextId++);
    _tabs.add(tab);
    _activeId = tab.id;
  }

  void activate(int id) {
    if (!_tabs.any((t) => t.id == id)) throw StateError('Unknown tab');
    _activeId = id;
  }

  void close(int id) {
    final index = _tabs.indexWhere((t) => t.id == id);
    if (index < 0) throw StateError('Unknown tab');
    _tabs.removeAt(index);
    if (_tabs.isEmpty) {
      add();
    } else if (_activeId == id) {
      _activeId = _tabs[index < _tabs.length ? index : _tabs.length - 1].id;
    }
  }

  void visited(String url) => active.url = url;
}
