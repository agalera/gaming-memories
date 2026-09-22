import Cocoa
import FlutterMacOS

enum FolderSelection {
  static func bookmarkURL(selectedURL: URL, suggestedPath: String?) -> URL {
    guard let suggestedPath, !suggestedPath.isEmpty else {
      return selectedURL
    }

    let selectedURL = selectedURL.standardizedFileURL
    let suggestedURL = URL(
      fileURLWithPath: suggestedPath,
      isDirectory: true
    ).standardizedFileURL
    let suggestedParent = suggestedURL.deletingLastPathComponent()
    return selectedURL == suggestedParent ? suggestedURL : selectedURL
  }
}

class MainFlutterWindow: NSWindow {
  private var folderAccessChannel: FolderAccessChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    folderAccessChannel = FolderAccessChannel(
      messenger: flutterViewController.engine.binaryMessenger,
      window: self
    )

    super.awakeFromNib()
  }
}

private final class FolderAccessChannel {
  private struct Failure: Error {
    let code: String
    let message: String
  }

  private let channel: FlutterMethodChannel
  private weak var window: NSWindow?
  private var activeURLs: [String: URL] = [:]
  private var terminationObserver: NSObjectProtocol?
  private var isChoosing = false

  init(messenger: FlutterBinaryMessenger, window: NSWindow) {
    channel = FlutterMethodChannel(
      name: "gaming-memories/folder-access",
      binaryMessenger: messenger
    )
    self.window = window
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    terminationObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.willTerminateNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.releaseAll()
    }
  }

  deinit {
    channel.setMethodCallHandler(nil)
    if let terminationObserver {
      NotificationCenter.default.removeObserver(terminationObserver)
    }
    releaseAll()
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "userHomeDirectory":
      guard let account = getpwuid(getuid()) else {
        result(
          error(
            "userHomeUnavailable",
            "macOS could not locate your user folder."
          )
        )
        return
      }
      result(String(cString: account.pointee.pw_dir))
    case "choose":
      choose(arguments: call.arguments, result: result)
    case "choosePath":
      choosePath(arguments: call.arguments, result: result)
    case "chooseFile":
      chooseFile(arguments: call.arguments, result: result)
    case "activate":
      activate(arguments: call.arguments, result: result)
    case "release":
      release(arguments: call.arguments)
      result(nil)
    case "releaseAll":
      releaseAll()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Presents the folder chooser and answers the selected path. The app runs
  /// outside the App Sandbox, where a path is the whole authorization, so no
  /// bookmark is taken.
  private func choosePath(arguments: Any?, result: @escaping FlutterResult) {
    guard !isChoosing else {
      result(error("chooserBusy", "Another folder chooser is already open."))
      return
    }
    guard let window else {
      result(error("unavailable", "The folder chooser is unavailable."))
      return
    }
    let values = arguments as? [String: Any]
    let panel = openPanel(values: values)
    panel.prompt = "Choose"
    if let initialPath = values?["initialPath"] as? String,
       !initialPath.isEmpty {
      panel.directoryURL = URL(fileURLWithPath: initialPath, isDirectory: true)
    }

    isChoosing = true
    panel.beginSheetModal(for: window) { [weak self] response in
      self?.isChoosing = false
      guard response == .OK, let panelURL = panel.url else {
        result(nil)
        return
      }
      result(panelURL.standardizedFileURL.path)
    }
  }

  /// Presents a file chooser and answers the selected path.
  ///
  /// Hidden files are shown on request, because the SSH keys this is used for
  /// live in `~/.ssh`, which a panel would otherwise never reach.
  private func chooseFile(arguments: Any?, result: @escaping FlutterResult) {
    guard !isChoosing else {
      result(error("chooserBusy", "Another chooser is already open."))
      return
    }
    guard let window else {
      result(error("unavailable", "The file chooser is unavailable."))
      return
    }
    let values = arguments as? [String: Any]
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false
    panel.resolvesAliases = true
    panel.showsHiddenFiles = values?["showHiddenFiles"] as? Bool ?? false
    panel.title = values?["title"] as? String ?? "Choose a file"
    panel.message = values?["title"] as? String
    panel.prompt = "Choose"
    if let initialPath = values?["initialPath"] as? String,
       !initialPath.isEmpty {
      panel.directoryURL = URL(fileURLWithPath: initialPath, isDirectory: true)
    }

    isChoosing = true
    panel.beginSheetModal(for: window) { [weak self] response in
      self?.isChoosing = false
      guard response == .OK, let panelURL = panel.url else {
        result(nil)
        return
      }
      result(panelURL.standardizedFileURL.path)
    }
  }

  private func openPanel(values: [String: Any]?) -> NSOpenPanel {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = !(values?["readOnly"] as? Bool ?? true)
    panel.resolvesAliases = true
    panel.title = values?["title"] as? String ?? "Choose a folder"
    return panel
  }

  private func choose(arguments: Any?, result: @escaping FlutterResult) {
    guard !isChoosing else {
      result(error("chooserBusy", "Another folder chooser is already open."))
      return
    }
    guard let window else {
      result(error("unavailable", "The folder chooser is unavailable."))
      return
    }
    let values = arguments as? [String: Any]
    let readOnly = values?["readOnly"] as? Bool ?? true
    let panel = openPanel(values: values)
    panel.prompt = "Allow Access"
    panel.message = values?["message"] as? String
      ?? "Gaming Memories will only access the folder you select."
    if let suggestedPath = values?["suggestedPath"] as? String,
       !suggestedPath.isEmpty {
      let suggestedURL = URL(fileURLWithPath: suggestedPath, isDirectory: true)
      panel.directoryURL = suggestedURL.deletingLastPathComponent()
      panel.nameFieldStringValue = suggestedURL.lastPathComponent
    } else if let initialPath = values?["initialPath"] as? String,
              !initialPath.isEmpty {
      panel.directoryURL = URL(fileURLWithPath: initialPath, isDirectory: true)
    }

    isChoosing = true
    panel.beginSheetModal(for: window) { [weak self] response in
      guard let self else {
        result(
          FlutterError(
            code: "unavailable",
            message: "Folder access is unavailable.",
            details: nil
          )
        )
        return
      }
      self.isChoosing = false
      guard response == .OK, let panelURL = panel.url else {
        result(nil)
        return
      }
      let selectedURL = FolderSelection.bookmarkURL(
        selectedURL: panelURL,
        suggestedPath: values?["suggestedPath"] as? String
      )

      do {
        let startedAccess = panelURL.startAccessingSecurityScopedResource()
        defer {
          if startedAccess {
            panelURL.stopAccessingSecurityScopedResource()
          }
        }
        let bookmark = try selectedURL.bookmarkData(
          options: self.creationOptions(readOnly: readOnly),
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        )
        result(try self.activate(bookmark: bookmark, readOnly: readOnly))
      } catch let failure as Failure {
        result(self.error(failure.code, failure.message))
      } catch {
        result(
          self.error(
            "bookmarkCreationFailed",
            "macOS could not remember access to that folder."
          )
        )
      }
    }
  }

  private func activate(arguments: Any?, result: @escaping FlutterResult) {
    guard let values = arguments as? [String: Any],
          let typedData = values["bookmark"] as? FlutterStandardTypedData else {
      result(error("bookmarkInvalid", "The saved folder permission is invalid."))
      return
    }
    do {
      result(
        try activate(
          bookmark: typedData.data,
          readOnly: values["readOnly"] as? Bool ?? true
        )
      )
    } catch let failure as Failure {
      result(error(failure.code, failure.message))
    } catch {
      result(
        self.error(
          "bookmarkResolutionFailed",
          "macOS could not restore access to that folder."
        )
      )
    }
  }

  private func activate(bookmark: Data, readOnly: Bool) throws -> [String: Any] {
    var stale = false
    let url: URL
    do {
      url = try URL(
        resolvingBookmarkData: bookmark,
        options: [.withSecurityScope, .withoutUI],
        relativeTo: nil,
        bookmarkDataIsStale: &stale
      )
    } catch {
      throw Failure(
        code: "bookmarkResolutionFailed",
        message: "macOS could not restore access to that folder."
      )
    }
    guard url.startAccessingSecurityScopedResource() else {
      throw Failure(
        code: "accessDenied",
        message: "Access to that folder was not granted."
      )
    }

    let currentBookmark: Data
    do {
      currentBookmark = stale
        ? try url.bookmarkData(
            options: creationOptions(readOnly: readOnly),
            includingResourceValuesForKeys: nil,
            relativeTo: nil
          )
        : bookmark
    } catch {
      url.stopAccessingSecurityScopedResource()
      throw Failure(
        code: "bookmarkRefreshFailed",
        message: "macOS could not refresh access to that folder."
      )
    }

    let leaseID = UUID().uuidString
    activeURLs[leaseID] = url
    return [
      "path": url.path,
      "bookmark": FlutterStandardTypedData(bytes: currentBookmark),
      "leaseId": leaseID,
    ]
  }

  private func release(arguments: Any?) {
    guard let values = arguments as? [String: Any],
          let leaseID = values["leaseId"] as? String,
          let url = activeURLs.removeValue(forKey: leaseID) else {
      return
    }
    url.stopAccessingSecurityScopedResource()
  }

  private func releaseAll() {
    let urls = Array(activeURLs.values)
    activeURLs.removeAll()
    for url in urls {
      url.stopAccessingSecurityScopedResource()
    }
  }

  private func creationOptions(readOnly: Bool) -> URL.BookmarkCreationOptions {
    readOnly
      ? [.withSecurityScope, .securityScopeAllowOnlyReadAccess]
      : [.withSecurityScope]
  }

  private func error(_ code: String, _ message: String) -> FlutterError {
    FlutterError(code: code, message: message, details: nil)
  }
}
