---
id: TQ-0070
title: Publish the library as an HTML gallery over rsync or SFTP
status: done
priority: normal
labels:
  - feature
  - component/backend
  - component/frontend
  - component/config
created: 2026-09-22T09:56:36+02:00
updated: 2026-09-22T19:16:21+02:00
---

Render the library as a static HTML gallery and upload it to a web host, so a
Gaming Memories library can become a public site the way
`games-screenshot-gallery`'s `make deploy` target does today.

The feature is off until it is turned on. When it is on, the sidebar grows a
**Publish** button directly above **Settings**, and Settings grows a **Publish**
tab.

## Reference behaviour

The Makefile this replaces:

    deploy:
    	rsync --progress -rltz --delete \
    		./Gallery/ deploy@192.168.40.17:/srv/staticsites/screenshots.fmartingr.com/
    	ssh deploy@192.168.40.17 \
    		'chmod -R u=rwX,go=rX /srv/staticsites/screenshots.fmartingr.com'

The published site must keep working as it does now: per-folder `index.html`,
`.thumb.jpg` sidecars beside every capture, `cover.*` as a folder's tile.

## Decisions

Answered before planning; these are settled, not open.

- **Transport:** both, rsync preferred. A pure-Dart SFTP transport is the
  baseline so the feature works with no external binary and on Windows; rsync
  is used automatically when it can be.
- **Render target:** a separate app-managed build directory holding only the
  rendered HTML. The upload merges two local trees into one remote tree — HTML
  from the build directory, media from the library. The library folder is not
  written to, and no media is duplicated on disk.
- **Scope:** the whole library, minus an exclusion list of platforms and albums.
- **Auth:** a private key file plus an optional passphrase. The passphrase is
  asked for at publish time and held in memory only; it is never written to
  `gaming-memories.json`.
- **Template:** a Dart port of `games-screenshot-manager`'s `templates/album.html`.
  The published site must look the same as it does today.
- **Clips:** always published, like the current rsync. No toggle.
- **Permissions:** configurable, defaulting to today's `u=rwX,go=rX`, stored as
  separate file and directory octal modes (`644` / `755`).
- **Flow:** one button, straight through. No diff preview, no confirmation step.

## Settings

New `PublishSettings` on `AppSettings`, saved under `publish`. Bump the settings
`version` and keep `AppSettings.fromJson` tolerant of a file that predates it.

    enabled            bool
    transport          auto | rsync | sftp      (default auto)
    site.title         "Games Screenshots"
    site.author        "@fmartingr"
    site.url           "https://screenshots.example.com"   (og: tags)
    site.footerText    free text
    target.host        hostname or IP
    target.port        int, default 22
    target.username    remote user
    target.remotePath  absolute path on the remote
    target.keyPath     private key file, default ~/.ssh/id_ed25519
    target.fileMode    "644"
    target.dirMode     "755"
    target.deleteRemoved bool, default true
    excluded           list of relative album paths ("Steam", "Steam/Hades")

No secret is stored. The key path is a path, not a key.

## Gallery rendering

New `lib/services/publish/`:

- `gallery_node.dart` — the tree: a folder node with child folders, files, a
  cover, and per-node image/clip counts and last-updated time. Ports
  `GalleryNode`'s breadcrumbs and web-path helpers.
- `gallery_builder.dart` — walks the library folder into that tree. Skips
  excluded albums, `.DS_Store`, `*.metadata.json`, `*.thumb.jpg.frame.jpg` and
  `index.html`, treats `cover.*` as the parent's cover, and treats `*.thumb.jpg`
  as a sidecar of its media file rather than an item of its own. An empty folder
  is not linked.
- `gallery_template.dart` — renders one folder's `index.html`. A faithful port
  of `album.html`: `prefers-color-scheme` light/dark, breadcrumbs, folder tiles
  with screenshot/clip counts, the screenshots/clips filter and sort toggle,
  the lightbox with keyboard, click and swipe navigation, the `og:` tags, and
  the footer. Every interpolated value is HTML-escaped, and paths are
  percent-encoded for URLs.
- Clip durations come from the existing `*.metadata.json` sidecars, so the
  overlay keeps showing a length without running ffprobe at publish time. A
  clip with no cached duration renders the play icon alone.

Rendering writes into `<support dir>/publish/`, mirroring the album tree, one
`index.html` per folder. A file is only rewritten when its bytes change, so an
unchanged page keeps its mtime and the transport skips it.

## Publish plan

`publish_plan.dart` builds the remote tree as a map of remote relative path to
local source file, merging the two local roots. The transports share it, so both
agree on exactly what the remote should hold.

## Transports

`PublishTransport` is the seam, with `SftpTransport` and `RsyncTransport` behind
it, both reporting progress and both honouring `deleteRemoved` and the
configured modes.

**SFTP** (`package:dartssh2`, pure Dart, no binary):

- Connects, authenticates with the key and optional passphrase.
- Lists the remote tree, compares size and mtime against the plan, uploads what
  differs, creates missing directories, sets the configured mode on what it
  writes, and preserves mtime so the next run can skip it.
- Deletes remote entries the plan does not contain, deepest first.

**rsync**: two passes, because the remote tree merges two local roots.

1. Media from the library root, with `--delete-excluded` so an album removed
   from the library or added to the exclusion list also leaves the remote, and
   a protect filter so pass 1 does not delete the `index.html` files pass 2
   owns.
2. HTML from the build directory, no `--delete`; a folder that disappeared
   entirely was already removed by pass 1.

Both passes carry `-rltz`, `--chmod=D<dirMode>,F<fileMode>` and
`-e 'ssh -i <key> -p <port> -o BatchMode=yes'`, and `--progress` is parsed for
the progress value. `--chmod` replaces the separate `ssh … chmod -R` round trip.

`BatchMode=yes` means rsync fails fast instead of hanging on a passphrase prompt
the app cannot answer.

**Selection** under `auto`: rsync when the `rsync` and `ssh` binaries resolve on
PATH and authentication can be non-interactive — an unencrypted key, or a key
already loaded into a running agent. Otherwise SFTP, which can take the
passphrase the app asked for. `rsync` and `sftp` force one and report a usable
error when it cannot run.

## UI

- **Sidebar:** an `FButton` labelled **Publish**, full width, directly above
  **Settings**, rendered only when publishing is enabled. It runs the publish
  itself — no intermediate view. While running it is disabled and its label
  carries the progress. The result lands in the existing notification channel.
- **Settings:** a fourth tab, **Publish**, holding the master switch and, when
  on, the site identity fields, the destination fields, the key path, the
  transport choice, the permission modes and the exclusion list. Same autosave
  and validation behaviour as the other tabs.
- The passphrase is asked for in a dialog at publish time, and kept in memory
  for the rest of the session.
- Publishing is refused with a clear message when the library folder is unset
  or unauthorized, or when a required destination field is empty.

## Logging

Route progress and failures through `AppLog`. Extend the controller's
`_redactDiagnostic` so a passphrase can never reach the log file.

## Validation

- `gallery_builder`: exclusions, sidecar and cover handling, empty folders,
  counts, nesting.
- `gallery_template`: escaping of a title holding `<`, `&` and a quote;
  percent-encoded paths; the clip overlay with and without a cached duration;
  the `og:` tags on a child page and their absence on the root.
- `publish_plan`: the merge of both roots, and the deletions implied by a
  remote listing.
- `RsyncTransport`: the exact arguments of both passes, and a real local
  `rsync` run against a temporary directory proving `--delete-excluded` plus the
  protect filter removes an excluded album while leaving `index.html` alone.
- `SftpTransport`: the upload/skip/delete decisions against a fake remote
  listing, without a network.
- Transport selection under each `transport` value and each auth shape.
- `AppSettings` JSON round-trip, and loading a settings file with no `publish`
  key.
- `flutter analyze` and `flutter test` clean.

---

## Notes

- 2026-09-22T10:24:33+02:00 — Implemented and verified.

  Two design corrections came out of testing against a real rsync 3.5.1, both of
  which would have lost data on the remote:

  1. macOS ships openrsync, not rsync. It accepts --delete-excluded and a protect
     filter and silently does neither, and rejects --chmod outright. A publish
     through it would leave deleted captures on the host with no error. rsync is
     now gated on a version probe that rejects openrsync and anything below 3.0,
     and falls back to SFTP.

  2. A blanket 'P index.html' protect rule also protects the page of an album
     that is gone, so rsync cannot delete that album's folder and the orphan page
     stays on the site forever. The captures pass now takes one protect rule per
     page actually rendered, read from a filter file beside the build directory.
     Glob characters in an album name are escaped: 'Hades [GOTY]' unescaped
     matches nothing, and its live page would be deleted on the next publish.

  Pass order was also flipped: pages first, then captures. A failure partway
  through the captures pass then leaves the site's pages intact rather than gone.

  Also fixed while wiring the settings tab: _validateAndSave in settings_page.dart
  rebuilds AppSettings field by field, so a new section is dropped unless it is
  named there. Publish is now carried through.

  Verified with a sample built from the real gallery: root, platform and album
  pages render, breadcrumbs and covers and counts are right, clip overlays carry
  the cached durations, the lightbox opens and navigates, and an excluded album
  has no page and no files in the plan. The delegated lightbox click was bound to
  the first .gallery on the page in the Go template, which is the folder list on a
  page that has both; it is bound to .gallery.files here.

  The real-rsync test skips when PATH has no rsync 3. Run it with
  GAMING_MEMORIES_RSYNC pointing at one.

  flutter analyze clean; 278 tests pass.
- 2026-09-22T10:45:49+02:00 — Added bundled platform covers.

  Nothing writes a cover into a platform folder, so a platform tile on the front
  page was falling back to whichever capture came first below it. The 11 covers
  from games-screenshot-gallery are now bundled under assets/covers/platforms and
  matched to the platform folder by name, case and padding ignored: Android, Game
  Boy, Game Boy Advance, Game Boy Color, Nintendo Switch, Nintendo Switch 2, PC,
  Pico-8, PlayStation 4, PlayStation 5, Super Nintendo. 504 KB in total, and
  adding another is a file in that folder plus a line in the map.

  Precedence: a cover.* in the library wins, then the bundled one, then the first
  thumbnail below the folder. Only a top-level folder takes a bundled cover, so a
  game album named 'PC' does not get one.

  The cover is written into the build directory next to the platform's
  index.html, never into the library, and is published from the build root. That
  matters for rsync: the mirroring pass walks the library, which has no such
  file, so without a protect rule it would delete the cover it had just
  uploaded. The rules are derived from build-root plan files, so the cover is
  covered by the same mechanism as the pages.

  GalleryFolder.coverName/coverSourcePath collapsed into one GalleryCover value
  carrying its origin, because 'a name plus one of two possible sources' was
  about to become three nullable fields.

  One bug found while testing: the renderer reported a cover whose asset could
  not be read, which would hand the upload a file that is not on disk. It now
  only reports a cover that is actually in the build directory.

  Verified against the real gallery sample: the three platforms present render
  their bundled covers, the platform og:image points at the cover, and the file
  is served with the right type. flutter analyze clean; 297 tests pass.
- 2026-09-22T12:20:10+02:00 — Credentials are now chosen, and no key is forced.

  PublishTargetSettings carries a PublishCredentialKind:

  - automaticKey (default) — whatever the system already has. The SSH agent
    first, then the usual identity files under ~/.ssh in OpenSSH's order
    (id_ed25519, id_ecdsa, id_rsa, id_dsa). Nothing to configure.
  - manualKey — one key file, and only that one. The path is the only thing
    saved.
  - password — asked for at publish time, kept in memory, never written.

  validate() no longer demands a key path; it only does so for manualKey. A
  settings file written before this choice existed migrates by what it held:
  a keyPath means manualKey, no keyPath means automaticKey.

  dartssh2 can forward an agent to a remote host but cannot authenticate against
  a local one, so SshAgentClient speaks the part of the agent protocol that needs
  — request identities, sign — over SSH_AUTH_SOCK. SSHIdentity.custom plus
  SSHRawHostKey/SSHRawSignature is the seam dartssh2 provides for exactly this.
  Two details that matter: an ssh-rsa identity is advertised as rsa-sha2-256 and
  signed with the SSH_AGENT_RSA_SHA2_256 flag, because OpenSSH 8.8 and newer
  refuse SHA-1; and agent identities set shouldProbe so a hardware token is not
  asked to sign for a key the server would reject.

  Verified against the real ssh-agent, not only the fake: both an ed25519 and an
  RSA key list with the right type and comment, and both sign, the RSA one
  returning an rsa-sha2-256 signature. The unit tests run against a stand-in
  agent on a real unix socket speaking the real wire protocol.

  Transport selection per kind:
  - automaticKey — rsync gets no -i at all, so ssh reads the agent, ssh_config
    and the default identities itself. This is rsync's best case. It falls back
    to SFTP only when a passphrase would have to be typed.
  - manualKey — rsync gets -i, unless the path holds a space (rsync splits its
    -e value on whitespace) or the key is encrypted.
  - password — always SFTP; rsync cannot be handed one without a terminal.

  The passphrase dialog became a secret dialog: it asks for a passphrase or a
  password depending on what is needed, and the held secret is dropped when the
  credential kind, key path, user or host changes, not just the key path.

  flutter analyze clean; 335 tests pass.
- 2026-09-22T12:30:22+02:00 — Fixed: the key file Choose button did nothing on macOS.

  Root cause: file_picker's macOS plugin gates every panel behind an App Sandbox
  entitlement check (com.apple.security.files.user-selected.read-only/read-write).
  Gaming Memories is distributed with Developer ID outside the sandbox and
  declares neither, so handleFileSelection returned a FlutterError before the
  NSOpenPanel was ever created — the button simply did nothing.

  The codebase already knew this. folder_access_service.dart carries the comment
  'file_picker refuses to open its macOS panel unless the app declares the App
  Sandbox entitlements' and routes folder choosing through the Runner's own
  NSOpenPanel on macOS. The key chooser was written against FilePicker.pickFile
  and missed that workaround.

  The Runner's folder-access channel now answers 'chooseFile' as well, and
  FolderAccessService grew chooseFile(FileChoiceRequest). macOS uses the native
  panel; every other platform keeps file_picker, which has no such gate there.

  Second problem the native panel also fixes: SSH keys live in ~/.ssh, and
  file_picker hardcodes showsHiddenFiles = false with no way to override it, so
  the folder was unreachable even if the panel had opened. The Runner's panel
  takes showHiddenFiles, and the chooser opens in ~/.ssh when it exists.

  A chooser failure now shows beside the field instead of being swallowed.

  Verified: flutter build macos succeeds, so the Swift compiles; widget tests
  prove the button calls the chooser with showHiddenFiles true and an initial
  path of ~/.ssh, stores the chosen path, and surfaces a FolderAccessException.

  Note while checking a real run: 'Rendered 241 gallery pages and 0 platform
  covers' is correct rather than a fault. That library is the old gallery folder,
  which already holds cover.* in every platform folder, and a library cover wins
  over a bundled one by design. The tiles still render, from those files.

  flutter analyze clean; 337 tests pass.
- 2026-09-22T12:45:48+02:00 — Automatic now reads ~/.ssh/config, which is where an agent is usually set up.

  The SFTP transport only looked at SSH_AUTH_SOCK, so an agent configured with
  IdentityAgent was invisible to it. That is the normal way to set one up —
  1Password, Secretive and gpg-agent all do it — and a windowed app inherits no
  SSH_AUTH_SOCK from a shell in any case. On macOS the rsync path is refused
  (openrsync), so SFTP is what actually runs, and it failed with 'All
  authentication methods failed' while plain ssh worked.

  New SshConfig parser covering what decides a sign-in: Host blocks with glob and
  negated patterns, Include with globs and loop protection, IdentityAgent,
  IdentityFile, IdentitiesOnly, keyword=value, quoted values and the ~, %d, %h,
  %u and %r expansions. Quoting matters rather than being an edge case: the
  1Password socket lives under 'Group Containers', so the value has a space in
  it. Match blocks are skipped rather than guessed at, because applying one whose
  condition cannot be evaluated would offer a key for the wrong host.

  Resolution order for automatic: the agent the config names for that host, else
  SSH_AUTH_SOCK; then the IdentityFile entries; then the default id_* files,
  unless IdentitiesOnly says the named ones are the whole list. A chosen key file
  still ignores all of it.

  Two bugs found while testing the parser: a value was unquoted twice, which cut
  the 1Password socket path at its first space; and the implicit leading block
  answered for IdentitiesOnly before any block that actually set it.

  Verified against the real setup with SSH_AUTH_SOCK unset, which is what a GUI
  launch looks like: the agent socket is read from the config, 9 identities come
  back including the staticsites-deploy key, the RSA one is advertised as
  rsa-sha2-256, and nothing has to be typed.

  Not carried over from the config: HostName, User and Port stay as typed in
  Settings, so publishing never connects somewhere the fields do not say.

  flutter analyze clean; 365 tests pass.
- 2026-09-22T13:07:58+02:00 — Publishing can be stopped, and host keys are verified.

  The Publish button gives way, while a publish runs, to a toast in the same
  shape as the library and scan ones — what it is on now, and a bar — beside an
  icon-only stop button. Stopping ends the file in flight rather than waiting for
  it: rsync's process is killed, and an SFTP upload aborts its writer. Nothing
  the mirror would have removed is removed once a stop is asked for, because the
  uploads that would have replaced those files never ran. A stop is reported as
  what happened rather than as a failure.

  Then the rsync failure reported mid-change: 'Host key verification failed'
  while ssh worked. The host was not in known_hosts, and BatchMode=yes stops ssh
  asking about one — so it refused. Reproduced against the real host with the old
  flags, and fixed with StrictHostKeyChecking=accept-new, which takes a first key
  on trust and still refuses a changed one.

  Diagnosing that turned up a worse problem in the transport that was working.
  dartssh2 accepts any host key when no verifier is given — its own documentation
  says leaving it null 'exposes the connection to man-in-the-middle attacks' — so
  SFTP had been publishing to whatever answered. rsync was refusing correctly and
  SFTP was not checking at all.

  Both now behave the same way, trust on first use, which is what was chosen:

  - known_hosts is read, including hashed entries, [host]:port for a non-default
    port, @revoked, and any UserKnownHostsFile the config names for that host.
  - A host nobody knows yet is accepted and remembered; a key that later differs
    is refused and nothing is uploaded.
  - Another key type for a known host is new rather than changed, so a server
    offering several does not read as an attack.
  - What is accepted is kept beside the settings, not written into the user's
    known_hosts, because the verifier is handed a fingerprint rather than the key
    and could not write a well-formed entry. rsync maintains that file itself.

  The fingerprints are the same strings ssh-keygen -lf prints, checked against a
  generated ed25519 and RSA key rather than only against my own arithmetic.

  Verified against the real host: the old flags reproduce the reported error, the
  new ones connect and record the key, and the verifier then reads that entry as
  known while a substituted fingerprint reads as changed.

  flutter analyze clean; 393 tests pass.
- 2026-09-22T13:14:02+02:00 — Documented Publish on the site and added a website note to AGENTS.md.

  site/docs.html gained a Publish section as 08, between the sources and the
  reference material, which renumbered the four that follow. It covers turning it
  on, the three ways to sign in and what Automatic reads from ~/.ssh/config, host
  keys on first use and what a refusal means, rsync against SFTP including why
  openrsync is skipped, exclusions and mirroring, and the bundled platform
  covers. rsync 3 joined the optional tools table, and two entries joined
  troubleshooting: a refused host key, and a publish that finds no SSH key.

  The landing page was left as it is. It was deliberately simplified in 41d5e89
  and carries no feature list to add to.

  AGENTS.md now says site/docs.html is part of a user-facing change, and names
  the two things easy to miss: the sections are numbered, so inserting one
  renumbers the rest, and each needs an entry in both the sidebar and the 'On
  this page' list.

  Checked by serving the site: the section renders with the existing styles,
  every anchor resolves to a section and every section is linked, and app.js has
  no hardcoded section list to fall out of step.
- 2026-09-22T13:16:35+02:00 — Fixed: the published footer still credited games-screenshot-manager.

  The template was already right. The library is a folder that used to be a
  gallery built by that tool, so it still holds 246 of its index.html files, and
  the captures pass had no exclusion for them. The pages pass wrote the right
  ones and the captures pass then copied the library's over the top: a protect
  rule stops a file being deleted, not being overwritten by one the sender has.

  index.html joins the patterns the captures pass never sends. The pages the
  first pass wrote are still protected from deletion, and a page for an album
  that is gone is neither protected nor sent, so it still leaves the host.

  SFTP was never affected: GalleryBuilder ignores index.html, so a library page
  never reaches the plan.

  The real-rsync test now starts from a library carrying another tool's pages,
  which is the shape of a migrated one. Checked that it fails without the fix —
  it reports 'page from the old tool' where the rendered page belongs — and
  passes with it.

  The host corrects itself on the next publish: the stale pages are not sent, and
  --delete-excluded removes every remote index.html that is not one of the pages
  just written.

  flutter analyze clean; 393 tests pass.
- 2026-09-22T13:22:56+02:00 — Progress no longer slips backwards, and captures upload before pages.

  Two causes for the percentage. Each rsync pass reported its own 0-100%, so the
  second one restarted the count; and rsync's --info=progress2 percentage slips
  back on its own while the file list is still being built, because the total it
  divides by is not known yet.

  Each pass now takes the share of the whole range its root's bytes deserve, from
  the plan, and what is shown is clamped so it only ever rises. The progress line
  parser was also too loose: it took any line holding a percent sign and two
  spaces, so a capture in an album like '100% Orange Juice' read as progress. It
  now matches the shape of a progress2 line, bytes first.

  Order reversed, which the user asked for and is plainly better. Pages used to
  go first, which meant a page could point at media still on its way. Captures go
  first now, so a visitor reading the site mid-publish sees the previous pages,
  which still point at files that are there. A failure partway is also kinder
  this way: old pages plus some new media beats new pages pointing at nothing.
  The SFTP plan is sorted the same way, library root before build root.

  buildArguments returns named passes rather than a bare list of argument lists,
  because the order, the labels and now the progress weights all have to agree,
  and a positional list had already crossed them once while I was editing.

  flutter analyze clean; 401 tests pass. README and site/docs.html updated.
- 2026-09-22T14:55:09+02:00 — Gallery template rebuilt: modern, themed, and carrying the real logo.

  Fonts moved off monospace onto a system sans stack. The cards were laid out
  with flex and flex-grow, which stretched whatever landed in the last row; they
  are a grid now, with a fixed aspect ratio, so every card lines up. Captures are
  cropped to keep that even, album covers are fitted instead, because a logo or
  box art carries as much at its edges as in the middle — Super Nintendo's
  wordmark was being sliced. Rounded cards and pill controls throughout, and the
  palette now matches the website.

  Light and dark themes with a control in the page corner. The system setting
  still decides by default; a choice overrides it and is kept in the reader's
  browser under the same key the website uses, so one choice covers both. The
  theme is settled by a script in the head, before the first paint, or a dark
  page flashes white on its way there.

  The footer shows the logo below the credit line. I first drew it as SVG to keep
  a page self-contained, but the trace was visibly off — the ribbon and the photo
  glyph especially — and the ask was for the logo rather than something like it.
  It is published as gaming-memories.webp at the site root instead, 8 KB, by the
  same seam the bundled platform covers use, so it is planned, protected from the
  mirroring pass, and pruned like anything else the build directory owns. A build
  that ships no logo links to none rather than pointing every page at a file that
  is not there.

  Two bugs the rework turned up. Filtering wrote an inline display, which a grid
  layout then has to agree with; it toggles the hidden attribute now — and a
  class beats the browser's own [hidden] rule, so the filter bar was showing on
  albums with nothing to filter until that was said explicitly. Both have tests.

  platform_covers.dart split in two: only the bundled implementation needs
  Flutter, so gallery rendering is Flutter-free and can run from a script.

  Added tool/render_demo_gallery.dart and a gallery-preview make target, which
  renders a library and serves it, for looking at the template without
  publishing anywhere.

  flutter analyze clean; 412 tests pass. README and site/docs.html updated.
- 2026-09-22T15:44:43+02:00 — Gallery adjustments: automatic theme, full-bleed album tiles, readable date.

  The theme control is gone. The page declares both palettes and follows the
  reader's system setting, with two theme-color meta tags carrying the media
  query rather than a script, so nothing is stored and there is nothing to keep
  in step.

  An album tile is now one image with its name over it, the same shape as a
  capture tile, rather than a fitted image with the name beneath. Covers arrive
  at whatever ratio their source used, so they are cropped to the tile. The name
  sits on a gradient strong enough to carry it over a dark screenshot, box art
  or a logo on white.

  That does cost something on the platform tiles: the bundled covers are logos,
  and a logo cropped to 16/10 loses its bottom edge — Nintendo Switch and Super
  Nintendo lose part of their wordmark. Raised with the user rather than quietly
  reverted, since full-bleed was the explicit ask. A blurred backdrop behind a
  whole cover would fill the tile without cropping, if that reads better.

  Last updated is a sentence now, '6 September 2026 at 08:05', in the time the
  capture carries rather than in UTC, with the ISO stamp kept in a time element
  for anything that wants to sort on it.

  The preview tool renders under the title 'Gaming Memories'. A real publish
  still takes its title from Settings, which on this machine reads 'Games
  Screenshots'.

  flutter analyze clean; 412 tests pass.
- 2026-09-22T18:19:45+02:00 — Album tiles take their cover's own aspect ratio, in CSS alone.

  I was about to read image headers while rendering to learn each cover's shape.
  The user asked whether HTML and CSS could do it, and they can: an img with a
  width and no height keeps its intrinsic ratio, so the tile is as tall as its
  cover with nothing having to measure anything. The folder rule drops the
  16/10 aspect-ratio and the crop; the grid gets align-items: start so a row is
  as tall as its tallest tile and the shorter ones sit at the top of it.

  This matters more than it looked. The covers in a real library are genuinely
  different shapes, by source: a Steam banner is 460x215, so 2.14; Nintendo
  Switch, PlayStation 5 and Game Boy covers are square; Super Nintendo is 1.45.
  A fixed 16/10 cropped a third off the height of every square cover and cut the
  ends off every banner. All of them are whole now.

  Captures keep the one shape, which is what keeps their grid even, and the
  lightbox keeps contain so a full-size image is never cropped.

  flutter analyze clean; 412 tests pass.
- 2026-09-22T18:29:43+02:00 — Captures take their own aspect ratio too, so no tile crops anything now.

  The natural ratio moved from the folder rule to the base one: .gallery
  .preview keeps width 100% and height auto with no aspect-ratio and no
  object-fit, and the grid aligns items to the start. Both grids behave the
  same, and the folder override is down to the border the clipping anchor
  already draws.

  The retro sources are what this is really for. A Game Boy capture is 160x144,
  so 10:9, and the old 16/10 crop cut the bottom off every one of them — which
  on a Game Boy is where the dialogue box sits. Every one of those screenshots
  was losing its text. They are whole now, and so are the 16:9 console captures,
  which were losing a strip top and bottom.

  Checked in the browser rather than by eye: across a page the rendered ratio of
  every tile matches its image's own to within the 1px border, so nothing is
  cropped and nothing is stretched.

  flutter analyze clean; 412 tests pass. site/docs.html follows.
- 2026-09-22T18:46:48+02:00 — The lightbox shows a capture's date, and the date itself got more accurate.

  The date rides on the tile as a data attribute, so opening one needs no second
  index, and it is cleared on close or the last one lingers behind the next image
  while it loads.

  Reading it turned up something worth fixing. The scanner knew two name shapes,
  dashed and run-together, and a real library also holds 103 captures named
  20231231_082312 — Android and several emulators write that one. Those read as
  the day they were copied rather than the day they were taken; every Game Boy
  capture in the library was dated wrong.

  Rather than teach the gallery a third shape the app would not know, both now
  read dates through lib/services/capture_date.dart. A capture that showed one
  date in the app and another on the site would be the same capture twice.

  The shared parser also refuses digits that are not a moment. 12345678_901234
  used to roll over into a year of its own, and a day past the end of its month
  did the same; a name has to be a real date to count as one.

  flutter analyze clean; 421 tests pass. site/docs.html follows.
- 2026-09-22T19:16:21+02:00 — Capture dates now read the formats a real library actually holds.

  Surveyed both libraries read-only. ~/Syncthing/gaming-memories is uniform, all
  dashed; the older gallery is where the variety is. 1,428 of its 16,550
  captures — 8.6% — carried a date nothing could read, so they were dated the day
  they were copied.

  capture_date.dart now recognises a date rather than a list of formats: a year,
  month and day anywhere in the name, with whatever separator the source used,
  followed optionally by a time with its own separator. That covers a prefix
  (WoWScrnShot_, Hytale, muOS_, CleanShot, Screenshot), dots, underscores and
  spaces in the time, the word 'at', hours and minutes without seconds,
  milliseconds and microseconds trailing, and two-digit years both bare and
  dashed.

  Two calls needed evidence rather than a guess, and the file system gave it:

  - Warcraft III writes month first. WC3ScrnShot_020920_201603_001.png sits in a
    Reforged folder and was written on 9 February 2020, so it is not 20
    September 2002. It is named before the general reading, because the digits
    alone cannot say.
  - The emulator shape Chrono Trigger (U) [!]-250131-192902.png is year first:
    the file was written five days after 31 January 2025.

  Measured rather than assumed. Across 17,091 captures in both libraries, 17,080
  now read — 99.94%, up from 91.4% — and the 11 that do not genuinely carry no
  date: chicory_screen_004.png, Screenshot_9.png, Undated_Main Menu.jpg. No
  parse lands after the file was written or before 1990, and a spot check of
  every newly handled shape matches its modification time to the minute, bar the
  ones plainly copied in later.

  The parser also refuses digits that are not a moment: a long number, an
  impossible month or day, 29 February in a common year, and a separator used
  once but not twice.

  flutter analyze clean; 436 tests pass.
