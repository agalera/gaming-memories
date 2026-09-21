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

  test('reports what a folder already holds when it arrives whole', () async {
    final root = await Directory.systemTemp.createTemp('gaming-memories-');
    final staging = await Directory.systemTemp.createTemp('gaming-memories-');
    await Directory(p.join(root.path, 'PC')).create(recursive: true);
    addTearDown(() => root.delete(recursive: true));
    addTearDown(() {
      if (staging.existsSync()) {
        staging.deleteSync(recursive: true);
      }
    });

    // Built away from the library, so every file is in place before the watcher
    // ever hears about the folder.
    final staged = Directory(p.join(staging.path, 'New Game'));
    final subAlbum = Directory(p.join(staged.path, 'Boss fights'));
    await subAlbum.create(recursive: true);
    final capture = File(p.join(staged.path, 'capture.jpg'));
    await capture.writeAsBytes(const [1]);
    final nested = File(p.join(subAlbum.path, 'nested.jpg'));
    await nested.writeAsBytes(const [2]);

    final changes = <LibraryChange>[];
    final stream = await const NativeLibraryWatcher().watch(root.path);
    final subscription = stream.listen(changes.add);
    addTearDown(subscription.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final game = Directory(p.join(root.path, 'PC', 'New Game'));
    await staged.rename(game.path);

    bool created(String path, {required bool isDirectory}) => changes.any(
      (change) =>
          change.kind == LibraryChangeKind.create &&
          change.isDirectory == isDirectory &&
          p.equals(change.path, path),
    );

    await _waitFor(() => created(game.path, isDirectory: true));
    await _waitFor(
      () => created(p.join(game.path, 'capture.jpg'), isDirectory: false),
    );
    await _waitFor(
      () => created(p.join(game.path, 'Boss fights'), isDirectory: true),
    );
    await _waitFor(
      () => created(
        p.join(game.path, 'Boss fights', 'nested.jpg'),
        isDirectory: false,
      ),
    );

    // The folder is watched from here on, not just walked once.
    final later = File(p.join(game.path, 'later.jpg'));
    await later.writeAsBytes(const [3]);
    await _waitFor(() => created(later.path, isDirectory: false));
  });

  test('does not replay the library it starts on', () async {
    final root = await Directory.systemTemp.createTemp('gaming-memories-');
    final game = Directory(p.join(root.path, 'PC', 'Game'));
    await game.create(recursive: true);
    final existing = File(p.join(game.path, 'existing.jpg'));
    await existing.writeAsBytes(const [1]);
    addTearDown(() => root.delete(recursive: true));
    // The platform can still be delivering the events that built this fixture.
    await Future<void>.delayed(const Duration(milliseconds: 500));

    final changes = <LibraryChange>[];
    final stream = await const NativeLibraryWatcher().watch(root.path);
    final subscription = stream.listen(changes.add);
    addTearDown(subscription.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // The platform reports folder-level noise of its own; what must not happen
    // is the first walk handing the queue every file the library already holds.
    expect(
      changes.where((change) => !change.isDirectory),
      isEmpty,
      reason: 'the startup walk announced ${existing.path}',
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
