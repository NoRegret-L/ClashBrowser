import 'dart:ffi';
import 'dart:io';

import 'package:flutter/services.dart';

/// Checks a real native symbol, not the presence of an artifact or a mock.
/// It does not start a listener and must never change CoreAdapter readiness.
class NativeCoreProbe {
  static const _channel = MethodChannel('clashbrowser/native_probe/v1');

  static Future<String> inspect() async {
    try {
      if (Platform.isAndroid) {
        final library = DynamicLibrary.open('libclash.so');
        final abi = library.lookupFunction<Int32 Function(), int Function()>(
          'bridgeABI',
        )();
        if (abi != 3) return 'Android 内核 ABI 不兼容';
        return 'Android Mihomo 原生库已加载 · ABI $abi';
      }
      if (Platform.isIOS) {
        final version = await _channel.invokeMethod<String>('version');
        if (version == null || version.isEmpty) {
          return 'iOS 内核版本不可用';
        }
        return 'iOS Mihomo 原生库已加载 · $version';
      }
      if (Platform.operatingSystem == 'ohos' ||
          Platform.operatingSystem == 'harmonyos') {
        final library = DynamicLibrary.open('libclash.so');
        final version = library.lookupFunction<
            Pointer<Uint8> Function(), Pointer<Uint8> Function()>(
          'ArkClashVersion',
        )();
        if (version.address == 0) return '鸿蒙内核版本不可用';
        final free = library.lookupFunction<
            Void Function(Pointer<Uint8>), void Function(Pointer<Uint8>)>(
          'ArkClashFree',
        );
        try {
          final bytes = <int>[];
          // Bound a trusted native C string read; version is ASCII.
          for (var i = 0; i < 256; i++) {
            final byte = (version + i).value;
            if (byte == 0) {
              return bytes.isEmpty
                  ? '鸿蒙内核版本不可用'
                  : '鸿蒙 Mihomo 原生库已加载 · ${String.fromCharCodes(bytes)}';
            }
            bytes.add(byte);
          }
          return '鸿蒙内核版本格式异常';
        } finally {
          free(version);
        }
      }
      return '当前平台无原生内核';
    } catch (_) {
      // Never disclose native paths or raw platform errors to the UI.
      return '原生内核不可用 · 浏览器保持离线';
    }
  }
}
