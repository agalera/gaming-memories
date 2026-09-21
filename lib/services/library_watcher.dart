import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

enum LibraryChangeKind { create, modify, delete, move }

class LibraryChange {
  const LibraryChange({
    required this.kind,
    required this.path,
    required this.isDirectory,
    this.destinationPath,
  });

  final LibraryChangeKind kind;
  final String path;
  final bool isDirectory;
  final String? destinationPath;
}

abstract interface class LibraryWatcher {
  Future<Stream<LibraryChange>> watch(String rootPath);
}

class NativeLibraryWatcher implements LibraryWatcher {
  const NativeLibraryWatcher();

  @override
  Future<Stream<LibraryChange>> watch(String rootPath) async {
    final root = _normalize(rootPath);
    final subscriptions = <String, StreamSubscription<FileSystemEvent>>{};
    var closed = false;
    late StreamController<LibraryChange> output;

    Future<void> removeTree(String path) async {
      final normalized = _normalize(path);
      final matches = subscriptions.keys
          .where(
            (watched) =>
                watched == normalized || p.isWithin(normalized, watched),
          )
          .toList(growable: false);
      for (final watched in matches) {
        await subscriptions.remove(watched)?.cancel();
      }
    }

    /// Watches [path] and every folder under it.
    ///
    /// A folder that arrives with files already in it gets no event for them:
    /// the watch starts after they were written. [announce] reports what the
    /// walk finds, so a folder moved or copied in whole is not missed. The
    /// library's own folders are already known at startup, so the first walk
    /// stays quiet.
    Future<void> addTree(String path, {bool announce = false}) async {
      final normalized = _normalize(path);
      if (closed || subscriptions.containsKey(normalized)) {
        return;
      }

      final directory = Directory(normalized);
      if (!await directory.exists()) {
        return;
      }

      late StreamSubscription<FileSystemEvent> subscription;
      subscription = directory
          .watch(events: FileSystemEvent.all, recursive: false)
          .listen(
            (event) {
              if (closed) {
                return;
              }

              final source = _eventPath(normalized, event.path);
              final destination =
                  event is FileSystemMoveEvent && event.destination != null
                  ? _eventPath(normalized, event.destination!)
                  : null;
              final knownDirectory =
                  event.isDirectory ||
                  subscriptions.keys.any(
                    (watched) =>
                        watched == source || p.isWithin(source, watched),
                  );
              output.add(
                LibraryChange(
                  kind: switch (event) {
                    FileSystemCreateEvent() => LibraryChangeKind.create,
                    FileSystemModifyEvent() => LibraryChangeKind.modify,
                    FileSystemDeleteEvent() => LibraryChangeKind.delete,
                    FileSystemMoveEvent() => LibraryChangeKind.move,
                  },
                  path: source,
                  destinationPath: destination,
                  isDirectory: knownDirectory,
                ),
              );

              if (event is FileSystemCreateEvent && knownDirectory) {
                unawaited(addTree(source, announce: true));
              } else if (event is FileSystemMoveEvent) {
                if (knownDirectory) {
                  unawaited(removeTree(source));
                }
                if (knownDirectory && destination != null) {
                  unawaited(addTree(destination, announce: true));
                }
              } else if (event is FileSystemDeleteEvent && knownDirectory) {
                unawaited(removeTree(source));
              }
            },
            onError: output.addError,
            onDone: () {
              if (subscriptions[normalized] == subscription) {
                subscriptions.remove(normalized);
              }
              if (normalized == root && !closed) {
                unawaited(output.close());
              }
            },
          );
      subscriptions[normalized] = subscription;

      try {
        await for (final entity in directory.list(followLinks: false)) {
          if (closed) {
            return;
          }

          final entityPath = _normalize(entity.path);
          final entityIsDirectory = entity is Directory;
          if (announce) {
            output.add(
              LibraryChange(
                kind: LibraryChangeKind.create,
                path: entityPath,
                isDirectory: entityIsDirectory,
              ),
            );
          }
          if (entityIsDirectory) {
            await addTree(entityPath, announce: announce);
          }
        }
      } on FileSystemException catch (error, stackTrace) {
        if (!closed) {
          output.addError(error, stackTrace);
        }
      }
    }

    output = StreamController<LibraryChange>(
      onCancel: () async {
        closed = true;
        final active = subscriptions.values.toList(growable: false);
        subscriptions.clear();
        await Future.wait(active.map((subscription) => subscription.cancel()));
      },
    );
    await addTree(root);
    return output.stream;
  }

  static String _eventPath(String watchedDirectory, String eventPath) {
    return _normalize(
      p.isAbsolute(eventPath) ? eventPath : p.join(watchedDirectory, eventPath),
    );
  }

  static String _normalize(String path) => p.normalize(p.absolute(path.trim()));
}
