import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

class NativeLoopback {
  static const _channel = MethodChannel('clashbrowser/native_probe/v1');
  static bool get supported => Platform.isAndroid || Platform.isIOS ||
      Platform.operatingSystem == 'ohos' || Platform.operatingSystem == 'harmonyos';

  static Future<Map<String, dynamic>> command(Map<String, dynamic> args) async {
    final input = jsonEncode(args);
    final String? output;
    if (Platform.isIOS) {
      output = await _channel.invokeMethod<String>('loopback', input);
    } else if (supported) {
      output = await Isolate.run(() => _ffi(input));
    } else {
      throw StateError('Native core unavailable');
    }
    if (output == null) throw StateError('Native reply missing');
    return Map<String, dynamic>.from(jsonDecode(output) as Map);
  }

  static String _ffi(String input) {
    final library = DynamicLibrary.open('libclash.so');
    final command = library.lookupFunction<Pointer<Utf8> Function(Pointer<Utf8>),
        Pointer<Utf8> Function(Pointer<Utf8>)>('ClashBrowserLoopback');
    final release = library.lookupFunction<Void Function(Pointer<Utf8>),
        void Function(Pointer<Utf8>)>('ClashBrowserFree');
    final arg = input.toNativeUtf8();
    try {
      final result = command(arg);
      if (result.address == 0) throw StateError('Native reply missing');
      try { return result.toDartString(); } finally { release(result); }
    } finally { malloc.free(arg); }
  }
}
