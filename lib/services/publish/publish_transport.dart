import '../../models/app_settings.dart';
import 'publish_plan.dart';

/// Progress of an upload, as the Publish button reports it.
class PublishProgress {
  const PublishProgress({required this.message, this.value});

  final String message;

  /// Completion between 0 and 1, or null when the transport cannot say.
  final double? value;
}

typedef PublishProgressCallback = void Function(PublishProgress progress);

/// What a finished upload did.
class PublishOutcome {
  const PublishOutcome({
    required this.uploaded,
    required this.skipped,
    required this.deleted,
    required this.bytes,
    this.stopped = false,
  });

  const PublishOutcome.empty()
    : uploaded = 0,
      skipped = 0,
      deleted = 0,
      bytes = 0,
      stopped = false;

  final int uploaded;
  final int skipped;
  final int deleted;
  final int bytes;

  /// The upload was stopped partway rather than finishing.
  final bool stopped;

  String describe() {
    final parts = [
      '$uploaded uploaded',
      if (skipped > 0) '$skipped unchanged',
      if (deleted > 0) '$deleted removed',
    ];
    return parts.join(' · ');
  }
}

/// Stops a publish partway.
///
/// It is asked between files rather than checked inside one, and the
/// transports also listen so the work in flight — an rsync process, an upload
/// of a large clip — ends at once instead of after it finishes.
class PublishCancellation {
  PublishCancellation();

  final _listeners = <void Function()>[];
  var _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    for (final listener in List.of(_listeners)) {
      listener();
    }
    _listeners.clear();
  }

  /// Runs [listener] when the publish is stopped, or straight away when it
  /// already has been.
  void onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  /// Drops a listener that has nothing left to stop.
  void removeListener(void Function() listener) => _listeners.remove(listener);

  void throwIfCancelled() {
    if (_cancelled) {
      throw const PublishStopped();
    }
  }
}

/// Raised when the user stops a publish. Not a failure, so it is reported as
/// what happened rather than as something that went wrong.
class PublishStopped implements Exception {
  const PublishStopped();

  @override
  String toString() => 'The publish was stopped.';
}

/// A failure the user can act on, rather than a stack trace.
class PublishException implements Exception {
  const PublishException(this.message, {this.detail});

  final String message;
  final String? detail;

  @override
  String toString() => detail == null ? message : '$message ($detail)';
}

/// Everything an upload needs that is not in the settings.
class PublishRequest {
  const PublishRequest({
    required this.plan,
    required this.target,
    required this.libraryPath,
    required this.buildPath,
    required this.cancellation,
    this.secret,
  });

  final PublishPlan plan;
  final PublishTargetSettings target;

  /// The two local roots the plan draws from.
  final String libraryPath;
  final String buildPath;

  /// The passphrase or password the publish was started with, held in memory
  /// for this publish only and never written anywhere.
  final String? secret;

  /// Asked between files, so the Stop button takes effect promptly.
  final PublishCancellation cancellation;
}

abstract interface class PublishTransport {
  /// What the settings call this uploader.
  String get name;

  Future<PublishOutcome> upload(
    PublishRequest request, {
    PublishProgressCallback? onProgress,
  });
}
