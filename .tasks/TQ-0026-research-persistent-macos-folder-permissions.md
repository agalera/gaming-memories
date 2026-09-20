---
id: TQ-0026
title: Research persistent macOS folder permissions
status: done
priority: high
labels:
  - component/frontend
  - component/backend
created: 2026-09-20T10:40:20+02:00
updated: 2026-09-20T12:46:45+02:00
---

# Persistent macOS folder access without disabling App Sandbox

Research date: 2026-09-20

## Decision

Keep App Sandbox enabled and add an app-specific macOS folder-access bridge that owns `NSOpenPanel` selection and security-scoped bookmarks. On macOS, a path string is not an authorization credential. The durable credential is bookmark data created from the URL returned by the system open panel, resolved on later launches, and activated with `startAccessingSecurityScopedResource()` before Dart touches the path.

The user-facing flow can be close to the requested one, with one important ordering constraint:

1. Derive an automatic candidate path without probing it.
2. Ask the user to confirm that folder in the macOS folder chooser.
3. Create and activate a security-scoped bookmark from the selected URL.
4. Validate the directory while that scope is active.
5. Atomically save the setting and bookmark only if validation succeeds.

A sandboxed app cannot inspect an arbitrary folder first and then silently ask macOS to authorize that already-known path. Apple's supported dynamic-access flow is an explicit user selection in an open/save panel; the panel runs out of process and extends the sandbox for the selected URL. [`directoryURL` only controls the directory shown by the panel](https://developer.apple.com/documentation/appkit/nssavepanel/directoryurl); it does not grant that directory. This means automatic discovery on macOS must mean “derive a likely candidate and ask the user to confirm it,” not “prove the directory exists before asking.” This conclusion follows from Apple's [App Sandbox file-access model](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox) and the user-selected entitlement's documented scope: access to items the user opens or saves through the standard panels ([entitlement reference](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html)).

There is no need to disable the sandbox or request Full Disk Access.

## Current application state

The repository already has the correct sandbox baseline:

- Both `macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements` enable `com.apple.security.app-sandbox` and `com.apple.security.files.user-selected.read-write`.
- The missing entitlement is `com.apple.security.files.bookmarks.app-scope`, which Apple documents as the entitlement for persistent app-scoped bookmark access ([Apple bookmark entitlement documentation](https://developer.apple.com/documentation/professional-video-applications/enabling-security-scoped-bookmark-and-url-access)). It must be added to both entitlement files.
- `ConfigStore` persists one JSON document at schema version 5. It stores only path strings.
- `LibraryController.initialize()` loads settings and immediately scans `outputPath`. On macOS, bookmark restoration and activation therefore need to happen between loading the settings and scanning the library.
- `SettingsPage` validates paths with `Directory.exists()`. A sandbox denial can look exactly like a missing directory, so this check must not classify a macOS automatic path until its scope is active.
- Local provider sources are read-only in normal operation: Steam, Diablo IV, and Guild Wars 2 read screenshots and copy them into the library. The library folder needs read/write access for imports, thumbnails, metadata, covers, and normal viewing.
- Steam is the only current automatic provider with a macOS candidate. Diablo IV and Guild Wars 2 return no automatic source on non-Windows platforms, so they must not cause a macOS permission panel unless the user switches them to a custom folder.

The installed picker does not solve persistence. The locked `file_picker 13.1.0` uses `file_picker_darwin 2.1.0`. Its Dart directory method invokes the native `dir` method and returns `String?`; it does not expose the original URL or bookmark data, and in this version it also drops `dialogTitle` and `initialDirectory` rather than forwarding them ([upstream Dart adapter](https://github.com/vicajilau/flutter_file_picker/blob/main/packages/file_picker_darwin/lib/src/file_picker_darwin.dart#L153-L168)). The Swift side creates an `NSOpenPanel` and reduces the selected URL to `url.path` ([upstream macOS handler](https://github.com/vicajilau/flutter_file_picker/blob/main/packages/file_picker_darwin/darwin/file_picker_darwin/Sources/file_picker_darwin/MacOSFilePickerHandler.swift#L191-L234)). It has no bookmark creation, restoration, stale-bookmark handling, or balanced start/stop access API. The plugin's own setup documentation covers only the user-selected entitlement ([file_picker Darwin README](https://github.com/vicajilau/flutter_file_picker/blob/main/packages/file_picker_darwin/README.md#macos-setup)).

Consequently, the app must create the bookmark from the original `NSOpenPanel` URL before reducing it to a string. A wrapper around the current `getDirectoryPath()` result cannot recover the security scope later.

## Platform rules the implementation must honor

### Selection grants an ephemeral scope

For URLs returned by `NSOpenPanel` or `NSSavePanel`, macOS starts scoped access on behalf of the app. If the selected URL is a directory, that extension covers its descendants recursively. The app must stop access when finished ([Apple: Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)). This makes a narrowly selected provider root sufficient; the app does not need access to the user's entire home or `Library` directory.

### Bookmarks make the grant durable

Create app-scoped bookmark data with `bookmarkData(options: [.withSecurityScope], relativeTo: nil)`. For provider source folders, also use `.securityScopeAllowOnlyReadAccess`; omit that option for the read/write library folder. Apple documents both modes and notes that bookmark data can continue to locate a moved or renamed item where the underlying volume supports it ([bookmark creation API](https://developer.apple.com/documentation/foundation/nsurl/bookmarkdata%28options%3Aincludingresourcevaluesforkeys%3Arelativeto%3A%29)).

On a later launch, resolve with `.withSecurityScope` and `relativeTo: nil`. If `bookmarkDataIsStale` is true, recreate the bookmark from the resolved URL and replace the stored data ([bookmark resolution API](https://developer.apple.com/documentation/foundation/url/init%28resolvingbookmarkdata%3Aoptions%3Arelativeto%3Abookmarkdataisstale%3A%29-3ic6f)). Use `.withoutUI` during automatic startup restoration so bookmark resolution itself does not surprise the user with UI; failure should become an explicit “Access required” state ([resolution option](https://developer.apple.com/documentation/foundation/nsurl/bookmarkresolutionoptions/withoutui)).

### Resolution alone does not activate access

After resolving a stored security-scoped bookmark, call `startAccessingSecurityScopedResource()` and check its Boolean result. Every successful start must have a matching `stopAccessingSecurityScopedResource()`; Apple warns that unbalanced starts leak kernel resources and can eventually prevent further sandbox extensions ([start-access API](https://developer.apple.com/documentation/foundation/url/startaccessingsecurityscopedresource%28%29)).

The resolved URL must remain owned by the native scope manager while Dart uses its path. Apple explicitly warns that converting a security-scoped URL to a string does not transfer security scope and that a string cannot later be used to obtain access ([NSURL, “Security-Scoped URLs and String Paths”](https://developer.apple.com/documentation/foundation/nsurl)). Dart file I/O is valid only while the native process has an active scope created from the resolved URL.

## Proposed architecture

### 1. Add a cross-platform `FolderAccessService`

Define a Dart interface and inject it into `LibraryController`:

```text
FolderAccessService
  choose(request) -> PendingFolderGrant?        // macOS panel; null on cancel
  activate(bookmarkData) -> ActiveFolderGrant   // resolved path + lease + stale refresh
  release(lease)
  dispose()
```

`PendingFolderGrant` should include the selected canonical path and opaque bookmark bytes. `ActiveFolderGrant` should include the resolved canonical path, a native lease identifier, and refreshed bookmark bytes when the stored bookmark was stale. The non-macOS implementation can preserve today's normal path validation and return no bookmark.

Implement the macOS service in Swift behind a dedicated `FlutterMethodChannel` registered from `MainFlutterWindow.swift`. Flutter documents this exact macOS host-code pattern ([Flutter platform-channel guide](https://docs.flutter.dev/platform-integration/platform-channels#step-6-add-a-macos-platform-specific-implementation)). An app-specific channel is preferable to forking `file_picker`: the feature needs bookmark persistence and lifetime management, not just a chooser.

The Swift component should:

- Present one sheet-modal `NSOpenPanel` on the main thread with directories enabled, files disabled, and a user-facing prompt such as “Allow Access.” `NSOpenPanel.canChooseDirectories` is the supported directory-selection control ([Apple API](https://developer.apple.com/documentation/appkit/nsopenpanel/canchoosedirectories)).
- Set `directoryURL` to the auto-discovered candidate (or its closest meaningful parent if the candidate is unavailable to the panel), while still requiring the user to confirm a selection.
- Create bookmark data from `panel.url` before returning any string path.
- Stop the panel URL's implicit scope after bookmark creation, then resolve/start the new bookmark through the same lease machinery used at startup; validation should not depend on a leaked panel-session grant.
- Resolve stored bookmarks, start scopes, and retain the resolved `URL` for every live lease.
- Reference-count leases by logical grant ID so concurrent validation/collection cannot accidentally stop access another operation is using.
- Refresh stale bookmarks and return replacement data to Dart.
- Stop scopes when a lease reaches zero, when a grant is replaced, and at app termination/deinitialization.
- Return typed failure codes (`cancelled`, `bookmarkCreationFailed`, `bookmarkResolutionFailed`, `accessDenied`, `unavailable`) rather than embedding filesystem details in user messages.

### 2. Persist grants with settings schema version 6

Add a map keyed by logical resource, separate from the provider's custom/automatic choice:

```json
{
  "version": 6,
  "folderGrants": {
    "library": {
      "platform": "macos",
      "path": "/Users/alice/Pictures/Gaming Memories",
      "access": "readWrite",
      "bookmark": "<base64 bookmark data>"
    },
    "provider.steam": {
      "platform": "macos",
      "path": "/Users/alice/Library/Application Support/Steam/userdata",
      "access": "readOnly",
      "bookmark": "<base64 bookmark data>"
    }
  }
}
```

The bookmark is opaque authorization state, not a path replacement. The resolved bookmark URL is authoritative on macOS; `path` is a display value, an initial location for reauthorization, and the fallback on platforms that use normal paths. If resolution follows a moved folder, update the displayed/effective path and persist it.

Keeping the bookmark in the same document as the path enables one logical commit. Harden `ConfigStore.save()` to write a temporary sibling file, flush it, and replace the settings file so an interrupted save cannot leave a path without its bookmark or vice versa.

### 3. Separate path resolution from providers

Move automatic-path derivation out of provider collection into a resolver that returns a requirement, for example:

```text
FolderRequirement(
  id: provider.steam,
  candidatePath: ~/Library/Application Support/Steam/userdata,
  access: readOnly,
  mode: automatic,
)
```

Do not call `Directory.exists()` on an ungranted macOS requirement. That result is ambiguous under App Sandbox. Providers should receive an effective, currently authorized path (or an explicit unavailable status) rather than independently rebuilding a path string. This also prevents a bookmark that followed a renamed folder from disagreeing with the old setting string.

Use the narrowest stable root:

| Resource | Scope | Recommended selected root |
| --- | --- | --- |
| Media library | Read/write; active while the app displays or modifies the library | The configured library root |
| Steam automatic source | Read-only; active during validation and collection | `~/Library/Application Support/Steam/userdata` |
| Custom provider source | Read-only; active during validation and collection | The selected screenshot/provider root |

Do not ask for `~/Library`, the whole Steam folder, or the home directory when a narrower descendant is sufficient.

### 4. Make folder changes transactional

Treat a folder-related edit and its grant as one transaction:

1. Keep the currently saved setting and active grant untouched.
2. Present the panel and receive a pending bookmark.
3. Resolve/start the pending bookmark and validate through the active scope.
4. Build schema-v6 settings containing the new setting, canonical path, and bookmark.
5. Atomically persist the document.
6. Promote the pending library lease or release a source validation lease.
7. Only after persistence succeeds, release and discard the old grant.

If the user cancels, selects the wrong auto folder, validation fails, bookmark creation fails, or settings persistence fails, release the pending scope and retain the previous saved setting and bookmark. Other unrelated fields may continue to autosave independently.

This transaction should apply when:

- Selecting or changing the library folder.
- Enabling a provider in automatic mode when no valid grant exists.
- Switching a provider between automatic and custom mode.
- Changing a custom provider folder.

On macOS, make folder text fields read-only and use “Choose…” / “Change…” actions. A manually typed absolute path cannot confer sandbox access, so accepting free-form text would create a setting the app cannot honor.

## User experience

### First run

Use a short permission checklist rather than opening several unexplained panels at launch. The first-run screen should explain that Gaming Memories remains sandboxed and only receives access to folders the user confirms. Each enabled requirement gets its own action:

- **Library folder — Choose folder**
- **Steam screenshots — Allow access** (pre-positioned at the derived `userdata` candidate)

Present panels one at a time as a direct result of the user's Continue/Allow action. Disabled providers and providers without a macOS candidate must not prompt.

After confirmation, show one of these states in Settings:

- **Access allowed** — bookmark resolved and validation passed.
- **Access required** — no bookmark, bookmark could not resolve/start, or a migrated path needs confirmation.
- **Folder unavailable** — a previously granted removable/network location is currently unavailable; offer Retry and Choose Again.
- **Wrong folder** — the selection does not match an automatic candidate; keep the previous setting and offer Choose Again or “Use custom folder.”

There is no separate generic macOS “allow this exact path” alert to trigger. For arbitrary folders, the `NSOpenPanel` itself is the system-controlled permission interaction. Its title, message, starting directory, and confirm button should make that purpose explicit.

### Settings autosave

Keep autosave for ordinary fields. Folder edits use the transaction above and need no Save button. Useful behavior by action:

| User action | Persisted result |
| --- | --- |
| Enables auto provider and grants a valid candidate | Save enabled mode and bookmark together |
| Cancels the permission panel | Revert the toggle/mode to its prior saved value |
| Selects an invalid/wrong folder | Show inline error; save neither path nor bookmark |
| Chooses a valid custom folder | Save custom mode, path, and bookmark together |
| Existing valid grant fails to resolve later | Keep configuration, mark access required, do not report “folder does not exist” |

The settings panel should validate the resolved grant immediately on entry. It must not wait for library collection to reveal a permission failure. During collection, a missing grant is a provider-specific warning, not a raw filesystem error; every failed provider should retain its own warning.

## Validation rules

Validation must run only after a bookmark-backed scope is active on macOS.

- **Library:** resolved URL is a directory; it can be enumerated; a uniquely named empty probe file can be created, flushed, and deleted. Failure must not replace the prior library setting.
- **Automatic Steam:** the selected canonical URL must match the derived `userdata` candidate, be a readable directory, and permit enumeration. Do not require screenshots to exist: a valid Steam installation can have an empty account or no screenshots yet.
- **Custom source:** resolved URL is a readable directory and can be enumerated. Provider-specific shape checks may improve messages, but must not reject a legitimate empty screenshot folder.
- **Automatic provider with no supported candidate:** keep the provider unconfigured and show “No supported installation location was found on this Mac,” without opening a panel.

The validator must distinguish `notInstalled`, `needsAuthorization`, `unavailable`, `wrongFolder`, and `notWritable`. Collapsing all of these into `Directory.exists() == false` recreates the current bug.

## Startup and runtime lifecycle

Change initialization to this order:

1. Load schema-v6 settings.
2. Resolve stored bookmarks with `.withSecurityScope` and `.withoutUI`.
3. Activate the library bookmark and retain that resolved URL for the app session, because gallery images, videos, thumbnails, actions, and rescans access the library asynchronously over time.
4. Refresh and persist stale bookmark data before continuing.
5. Scan the library only if its access state is ready; otherwise initialize an empty library and expose `needsAuthorization` to the UI.
6. Resolve provider bookmarks into availability state, but activate provider scopes only around validation and `collect()`, releasing them in `finally` blocks.

Provider collection should acquire both the provider source lease and the already-active library destination lease before using Dart I/O. If any required lease is unavailable, return a warning for that provider and continue with the other providers.

## Migration from schema version 5

Path strings cannot be converted into security-scoped bookmarks without renewed user selection. On the first schema-v6 run on macOS:

1. Preserve all v5 settings and paths.
2. Add an empty `folderGrants` map.
3. Mark every configured external library/custom source, plus every enabled automatic provider with a candidate, as `needsAuthorization`.
4. Open the permission checklist with each panel pre-positioned from the existing path/candidate.
5. Commit each successful grant independently so canceling Steam permission does not discard a valid library grant.

The migration must not report a path as nonexistent merely because it lacks a grant. Bookmarks are tied to the creating app's code-signing identity, so a bookmark that fails after a reinstall, signing-identity change, or corruption should use the same reauthorization path; Apple's bookmark API documents that app-scoped bookmarks resolve only for the same signing identity ([bookmark creation API](https://developer.apple.com/documentation/foundation/nsurl/bookmarkdata%28options%3Aincludingresourcevaluesforkeys%3Arelativeto%3A%29)).

## Failure handling

- **User cancels:** no error toast; keep prior settings and show “Access not granted” inline if the resource is required.
- **Bookmark fails to resolve/start:** do not scan through the stored string path. Mark access required and offer a pre-positioned Choose Again action.
- **Bookmark is stale:** start access, regenerate bookmark data, atomically replace it, and continue. If regeneration fails, release access and request selection again.
- **Folder moved:** use the resolved bookmark URL and update the display path; do not force the old string path.
- **Folder deleted or volume offline:** show unavailable and Retry/Choose Again. Do not silently erase the bookmark, because a removable volume may return.
- **Wrong auto folder:** discard the pending bookmark and retain the old setting. Offer custom mode explicitly rather than silently converting modes.
- **Settings write fails:** release the pending grant and keep the old grant active.
- **Provider lacks access during collection:** emit one warning for that provider and continue other providers.
- **App exits or a grant is replaced:** balance every successful scope start with a stop.

## Implementation sequence

1. Add the app-scope bookmark entitlement to DebugProfile and Release, then verify the built app's signed entitlements.
2. Add schema-v6 `FolderGrant` persistence and atomic `ConfigStore` replacement, with migration tests.
3. Implement the macOS Swift channel for choose/create, resolve/start, stale refresh, and release. Keep bookmark bytes opaque across the channel (`FlutterStandardTypedData` / `Uint8List`) and Base64-encode only at JSON serialization.
4. Add `FolderAccessService` plus a fake implementation for Dart tests and a normal-path implementation for non-macOS platforms.
5. Restore/activate library access before `LibraryScanner.scan()` and add explicit access states to `LibraryController`.
6. Extract automatic candidate resolution from providers and pass authorized effective paths into provider collection.
7. Replace macOS folder text entry/picking with the transactional chooser and add first-run/migration permission UI.
8. Map permission failures to inline settings states and per-provider collection warnings.
9. Exercise a signed sandboxed build through relaunch, replacement, denial, and stale/unavailable scenarios.

## Test plan

### Dart unit/widget tests

- Settings schema v5 migrates without manufacturing bookmarks.
- A valid pending grant is validated and saved with its path in one write.
- Cancel, wrong folder, failed validation, and failed persistence keep the previous path/bookmark.
- `LibraryController.initialize()` restores access before invoking the scanner.
- Scanner is not called with an unauthorized external path.
- A stale refresh updates bookmark data and the resolved display path.
- Settings-open validation reports access state immediately.
- Enabling/switching path mode reverts when its required grant transaction fails.
- Source scopes are released in `finally` on both success and provider exceptions.
- Each provider with missing access emits its own warning while other providers continue.
- Non-macOS behavior remains path-based and does not require bookmark data.

### Swift/native tests

- Bookmark creation uses `.withSecurityScope`; read-only source creation also uses `.securityScopeAllowOnlyReadAccess`.
- Resolution uses `.withSecurityScope` and returns refreshed data when stale.
- A false `startAccessingSecurityScopedResource()` result is surfaced as `accessDenied`.
- Lease reference counting produces exactly one balanced stop for each successful start.
- Replacing or disposing a live grant stops the old URL.
- Panel cancel returns `cancelled` and creates no bookmark.

### Signed macOS integration checks

- Inspect both debug/profile and release signatures to confirm sandbox, user-selected read/write, and app-scope bookmark entitlements.
- Select a library outside the container, import media, quit fully, relaunch, and confirm the library scans without another chooser.
- Grant the auto Steam `userdata` folder, quit/relaunch, and confirm local screenshots remain readable.
- Rename a granted folder and confirm the bookmark resolves it, updates the displayed path, and remains valid after another relaunch.
- Deny/cancel each panel and confirm no edited path or bookmark is saved.
- Select a wrong folder and confirm validation occurs in Settings, not later during collection.
- Disconnect and reconnect an external-volume library and verify unavailable/Retry behavior.
- Verify multiple inaccessible providers produce separate warnings.
- Confirm the app still has no access to an unrelated sibling folder, demonstrating that the sandbox boundary remains intact.

## Acceptance criteria

- App Sandbox stays enabled in every build configuration.
- No Full Disk Access instruction or broad home-directory entitlement is introduced.
- Every external folder used on macOS has an explicit, user-confirmed, narrowly scoped bookmark.
- Library access is restored before startup scanning; provider access is activated only while needed.
- A valid grant works after a full app quit and relaunch under the same signed identity.
- Wrong, canceled, inaccessible, or invalid folder edits never replace the last valid saved setting/grant.
- Settings surfaces permission/validation failures immediately with user-facing language.
- Collection reports authorization/unavailable conditions as separate provider warnings, never as `path = ""` or a misleading nonexistent-path error.

---

## Notes

- 2026-09-20T10:43:40+02:00 — Confirmed current macOS runner keeps App Sandbox and user-selected read/write but lacks the app-scoped bookmark entitlement. file_picker 13.1.0/file_picker_darwin 2.1.0 presents NSOpenPanel and returns only a String path; it does not create, resolve, refresh, start, or stop security-scoped bookmarks. Apple requires a user selection for arbitrary external folders and security-scoped bookmark data for persistence across launches. The native flow must preserve the selected URL long enough to create the bookmark before reducing it to a Dart path.
- 2026-09-20T10:49:05+02:00 — Completed the primary-source-backed plan in docs/research/macos-security-scoped-folder-access.md. Decision: retain App Sandbox; use an app-owned NSOpenPanel/security-scoped bookmark bridge; restore library scope before scanning; scope provider access around validation/collection; and commit folder settings/bookmarks transactionally. The plan includes the schema-v5 migration, first-run/settings UX, failure states, implementation sequence, tests, and acceptance criteria. Documentation checks passed.
- 2026-09-20T10:54:15+02:00 — Consolidated the complete research plan into this task body at the user's request and removed the standalone docs/research artifact. This task file is now the single source for the findings and implementation plan.
- 2026-09-20T10:56:41+02:00 — Implementation started. The folder-access seam will expose directory selection and bookmark activation/release while keeping NSOpenPanel, security-scoped URL ownership, stale refresh, and lease balancing inside the macOS adapter. A normal-path adapter and fakes preserve non-macOS behavior and testability.
- 2026-09-20T11:22:06+02:00 — Implemented persistent sandboxed macOS folder access. Added schema-v6 folder grants and atomic config replacement; a native NSOpenPanel/security-scoped bookmark bridge with stale refresh and balanced leases; startup library restoration before validation/scanning; short-lived provider scopes; centralized automatic paths; transactional settings selection with read-only macOS path fields and immediate inline access validation; automatic Steam confirmation; and provider-specific amber processing warnings. Verified the local Steam candidate resolves to ~/Library/Application Support/Steam/userdata and contains the expected <account>/760/remote/<app>/screenshots hierarchy. Verification: make check (41 tests) passed; fvm flutter build macos --debug passed; plutil validated both entitlement files; codesign inspection confirmed app-sandbox, user-selected read-write, and bookmarks.app-scope in the built app. Manual system-panel grant/relaunch testing remains a release smoke check because it requires user interaction.
- 2026-09-20T11:53:15+02:00 — Reopened after live macOS diagnosis: NSOpenPanel opened inside the automatic Steam userdata candidate, so its confirmation button required selecting a child account directory; the controller then correctly rejected that child as the wrong automatic root. Updating the UX to explain the exact target, route multiple candidates through an in-app choice, and open the macOS panel at the target's parent with the target identified.
- 2026-09-20T12:01:36+02:00 — Fixed the diagnosed Steam authorization UX. Automatic folder candidates are now explicit and the selected automatic path is persisted. A single candidate opens NSOpenPanel at its parent with the exact target named and confirmation enabled; multiple candidates first show an explanatory in-app chooser, then open the macOS panel for the selected target. Steam guidance now explicitly says to confirm userdata rather than a numbered account folder. Added controller, provider, and widget regressions. Verified visually against the live macOS panel without granting access: Steam is displayed at the parent level, userdata is visible, the prompt identifies it, and Allow Access is enabled. make check passed with 44 tests and the macOS debug build succeeded.
- 2026-09-20T12:11:20+02:00 — Reopened after the corrected chooser still loops. Persisted settings remain unchanged and the live inline state shows the controller's exact automatic-path mismatch error, narrowing the failure to the URL returned by NSOpenPanel versus the suggested userdata candidate. Adding temporary tagged boundary instrumentation to capture selected versus suggested paths.
- 2026-09-20T12:29:24+02:00 — Final live diagnosis and fix: App Sandbox rewrites Dart HOME and Foundation's current-user home APIs to the app container, so Steam discovery was validating against <container>/Library/Application Support/Steam/userdata. The enabled NSOpenPanel button also returned the displayed Steam parent because nameFieldStringValue does not select the userdata row. The native bridge now resolves the real account home through getpwuid(getuid()), the shared resolver supplies that path to both Settings and SteamProvider, and discovery fails closed instead of falling back to a container home. When the pre-positioned panel confirms the suggested target's parent, the bridge deliberately creates the persistent read-only bookmark for the suggested userdata child; unrelated/wrong selections remain rejectable. Updated the user-facing prompt, added Dart and Swift regressions, and repaired RunnerTests' host path after the app product rename. Live signed-debug verification on this Mac confirmed the system dialog points at /Users/<user>/Library/Application Support/Steam/userdata, one click saves a provider.steam bookmark for that exact path, Settings changes to Access allowed, and a full quit/relaunch restores and activates that exact userdata bookmark without prompting again. Verification: make check passed (46 tests), both RunnerTests passed, and fvm flutter build macos --debug succeeded; temporary diagnostic logging was removed.
- 2026-09-20T12:46:41+02:00 — Reopened after Steam collection still produced an opaque generic warning. Added provider-boundary diagnostics with a timestamped stable prefix, sanitized exception text, full stack traces, and API-key/query redaction; the in-app warning now includes a sanitized one-line cause and points to the console. The red regression proved the prior catch-all discarded all diagnostics. Live reproduction then exposed the actual cause: App Sandbox denied HTTPS to store.steampowered.com because both runner configurations lacked com.apple.security.network.client. Added the outbound client entitlement to DebugProfile and Release plus regression coverage. Verified the built signature contains network.client. Repeating the same Collect media action completed local scanning and cover downloads and populated 18 Steam items with no provider failure. make check passed with 49 tests; the debug macOS build succeeded.
