import Cocoa
import FlutterMacOS
import XCTest
@testable import Gaming_Memories

class RunnerTests: XCTestCase {

  func testFolderSelectionUsesSuggestedChildWhenPanelConfirmsItsParent() {
    let parent = URL(fileURLWithPath: "/Users/alice/Steam", isDirectory: true)
    let suggested = parent.appendingPathComponent("userdata", isDirectory: true)

    let actual = FolderSelection.bookmarkURL(
      selectedURL: parent,
      suggestedPath: suggested.path
    )

    XCTAssertEqual(actual, suggested)
  }

  func testFolderSelectionPreservesASelectionOutsideTheSuggestion() {
    let selected = URL(fileURLWithPath: "/Users/alice/Other", isDirectory: true)

    let actual = FolderSelection.bookmarkURL(
      selectedURL: selected,
      suggestedPath: "/Users/alice/Steam/userdata"
    )

    XCTAssertEqual(actual, selected)
  }

}
