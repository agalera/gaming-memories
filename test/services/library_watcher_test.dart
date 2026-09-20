import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gaming_memories/services/library_watcher.dart';
import 'package:path/path.dart' as p;

void main() {
  test('watches existing folders and folders added later', () async {
    final root = await Directory.systemTemp.createTemp('gaming-memories-');
    final game = Directory(p.join(root.path, 'PC', 'Game'));
    await game.create(recursive: true);
    addTearDown(() => root.delete(recursive: true));
    final changes = <LibraryChange>[];
    final stream = await const NativeLibraryWatcher().watch(root.path);
    final subscription = stream.listen(changes.add);
    addTearDown(subscription.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final direct = File(p.join(game.path, 'direct.jpg'));
    await direct.writeAsBytes(const [1]);
    await _waitFor(
      () => changes.any(
        (change) =>
            change.kind == LibraryChangeKind.create &&
            p.equals(change.path, direct.path),
      ),
    );

    final subAlbum = Directory(p.join(game.path, 'New album'));
    await subAlbum.create();
    await _waitFor(
      () => changes.any(
        (change) =>
            change.kind == LibraryChangeKind.create &&
            change.isDirectory &&
            p.equals(change.path, subAlbum.path),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final nested = File(p.join(subAlbum.path, 'nested.jpg'));
    await nested.writeAsBytes(const [2]);
    await _waitFor(
      () => changes.any(
        (change) =>
            change.kind == LibraryChangeKind.create &&
            p.equals(change.path, nested.path),
      ),
    );
  });
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('The expected file system event did not arrive.');
}
