---
id: TQ-0049
title: Show friendly errors and write a diagnostic log file
status: done
priority: high
labels:
  - feature
  - component/backend
  - component/frontend
created: 2026-09-21T09:49:26+02:00
updated: 2026-09-21T09:55:48+02:00
---

# Friendly errors, with the detail kept in a log file

## The problem

Failures reach the user as raw system text. `_setError` is called with the
exception interpolated straight in:

    _setError('Could not load this folder: $exception');
    _setError('Could not prepare media previews: $exception');
    _setError('Could not load the library: $exception');
    _setError('Could not load sub-albums: $exception');
    _setError('Could not save settings: $exception');
    _setError('Could not refresh the timeline: $exception');
    _setError('$failure: $exception');
    _setError(exception.toString().replaceFirst('FileSystemException: ', ''));

so the dialog can read

    Could not load the library: FileSystemException: Directory listing
    failed, path = '/Users/x/Library' (OS Error: Operation not permitted,
    errno = 1)

`_providerFailureSummary` does the same for provider failures, and it tells
the user to "See the console log for details" — there is no log to see. The
only diagnostics are `debugPrint` calls, which reach a terminal nobody has
open in a release build.

## Target behaviour

1. Every message the user reads is plain language: what failed, and what they
   can do about it. No exception type, no errno, no path from the middle of a
   stack trace.
2. Every failure is written in full to a log file — message, exception, stack
   trace, timestamp — so a problem can be diagnosed after the fact.
3. The log is safe to hand over: secrets are redacted the way
   `_redactDiagnostic` already redacts the Steam API key.
4. The log rotates, so it cannot grow without bound.
5. Logging never breaks the app. A failure to write a log line is swallowed.

This is the groundwork for a support packet (OS, configuration and the log
file) that users will be able to attach to a report.

## Done when

- No user-visible string interpolates an exception.
- A log file exists in the application support directory and captures provider
  failures, folder access failures, watcher failures and unexpected errors.
- The Steam API key never appears in it.
- `make check` passes.

---

## Notes

- 2026-09-21T09:55:48+02:00 — Implemented.

  lib/services/app_log.dart
    AppLog interface, SilentAppLog (the default, so tests and const code never
    touch the filesystem) and FileAppLog. Appends are chained onto one future so
    entries cannot interleave and a rotation cannot run underneath a write; a
    line that cannot be written is dropped rather than becoming a second failure.
    Rotates at maxBytes keeping retainedFiles beside the current file, and
    read() returns them oldest first, which is the support packet's input.
    Everything passes through the redact hook first - the log does not know what
    a secret looks like, the controller does.

    diagnosticLog is a module-level AppLog for the const providers, which are
    constructed inside const provider lists and have nowhere to inject one. Set
    once in main; silent in tests.

  lib/services/user_facing_error.dart
    describeFailure(failure, action:) returns one sentence: what failed and what
    to do. FileSystemException is read through its errno (EACCES/EPERM, ENOENT,
    ENOSPC, EROFS, ENOTDIR/EISDIR, plus the Windows equivalents) rather than
    shown. A message the app raised itself is passed through, because those are
    already written for the user; one carrying an OS error is not. Anything
    unrecognised says the details are in the log file.

  Wiring
    LibraryController takes an AppLog and sets its redactor. _fail(action,
    exception, stackTrace, category:) logs in full and shows the sentence; every
    _setError('... $exception') call site now goes through it. Provider
    failures, folder-access failures, watcher failures and library-change
    failures log with their stack traces. _providerFailureSummary is gone: it
    existed to put a truncated exception on screen and told the user to check a
    console log that did not exist.

    main.dart opens the log at <support>/logs/gaming-memories.log, records the OS
    and version at startup, and routes FlutterError.onError and
    PlatformDispatcher.instance.onError into it.

  Verified end to end - three provider failures, what the user sees against what
  the log holds:

    [warning] Could not import from Steam. The app is not allowed to read that
              folder. Grant access to it in Settings.
    [warning] Could not import from Hytale. A file was not in the format the app
              expected, so it may be damaged.
    [warning] Could not import from Minecraft. The app could not reach the
              network. Check your connection and try again.

    2026-...Z ERROR [provider] Provider "Steam" failed.
        FileSystemException: Directory listing failed, path = '/Users/x/Library'
        (OS Error: Operation not permitted, errno = 1)
        #0 ... full stack trace

  No user-visible string interpolates an exception any more, and the only
  debugPrint left in lib/ is FileAppLog's own debug-build mirror. make check
  passes (168 tests).

  Left for the support packet task: gathering OS and configuration alongside
  AppLog.read(), and giving the user a way to find or export the file. The log
  side of it is done - it rotates, it is redacted, and it is readable as one
  string.
