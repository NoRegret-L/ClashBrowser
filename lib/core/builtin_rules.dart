import 'dart:io';
import 'package:flutter/services.dart';

/// Only fixed assets from the installation bundle. No remote provider paths.
/// Native code independently checks hashes and actual loaded rule counts.
class BuiltinRules {
  static const _files = [
    'manifest.json', 'reject.mrs', 'private.mrs', 'icloud.mrs',
    'apple.mrs', 'google.mrs', 'proxy.mrs', 'direct.mrs',
    'lancidr.mrs', 'cncidr.mrs', 'telegramcidr.mrs',
  ];

  static Future<void> stage(Directory home) async {
    final dir = await Directory('${home.path}/rules').create();
    for (final name in _files) {
      final data = await rootBundle.load('assets/rules/$name');
      if (data.lengthInBytes == 0) throw StateError('Empty rule asset');
      await File('${dir.path}/$name').writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
  }
}
