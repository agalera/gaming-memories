import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/services/provider_paths.dart';
import 'package:path/path.dart' as p;

void main() {
  test('Steam discovery can use the real home outside a macOS sandbox', () {
    const resolver = ProviderPathResolver(userHomeDirectory: '/Users/alice');

    expect(resolver.steamUserdataCandidates(), [
      p.join(
        '/Users/alice',
        'Library',
        'Application Support',
        'Steam',
        'userdata',
      ),
    ]);
  }, skip: !Platform.isMacOS);

  test('macOS discovery does not fall back to a sandbox container home', () {
    const resolver = ProviderPathResolver(allowEnvironmentHome: false);

    expect(resolver.steamUserdataCandidates(), isEmpty);
    expect(resolver.hytaleScreenshots(), isNull);
  }, skip: !Platform.isMacOS);

  test('Hytale discovery uses the real macOS account home', () {
    const resolver = ProviderPathResolver(userHomeDirectory: '/Users/alice');

    expect(
      resolver.hytaleScreenshots(),
      p.join('/Users/alice', 'Pictures', 'Hytale Screenshots'),
    );
  }, skip: !Platform.isMacOS);
}
