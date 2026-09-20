import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final configuration in ['DebugProfile', 'Release']) {
    test('$configuration allows outbound Steam requests', () {
      final entitlements = File('macos/Runner/$configuration.entitlements')
          .readAsStringSync();

      expect(
        entitlements,
        contains('<key>com.apple.security.network.client</key>\n\t<true/>'),
      );
    });
  }
}
