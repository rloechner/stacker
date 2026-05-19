import XCTest
import Darwin
@testable import Stacker

@MainActor
final class StackerSessionStoreLogicTests: XCTestCase {

    func testActiveAndInactiveWindowFiltering() {
        let store = StackerSessionStore()

        let choices: [WindowChoice] = [
            WindowChoice(id: 101, title: "Active One", window: nil, scriptIndex: 0),
            WindowChoice(id: 102, title: "Inactive", window: nil, scriptIndex: 1),
            WindowChoice(id: 103, title: "Also Active", window: nil, scriptIndex: 2)
        ]

        store.activeWindowIDs = [101, 103]

        let active = store.activeWindows(from: choices)
        let inactive = store.inactiveWindows(from: choices)

        XCTAssertEqual(active.map(\.id), [101, 103])
        XCTAssertEqual(inactive.map(\.id), [102])
    }

    func testSyncSelectionStateUpdatesIsSelectedFlags() {
        let store = StackerSessionStore()
        var choices: [WindowChoice] = [
            WindowChoice(id: 1, title: "One", window: nil, scriptIndex: nil, isSelected: false),
            WindowChoice(id: 2, title: "Two", window: nil, scriptIndex: nil, isSelected: true)
        ]

        store.activeWindowIDs = [1]

        store.syncSelectionState(availableWindows: &choices)

        XCTAssertTrue(choices[0].isSelected)
        XCTAssertFalse(choices[1].isSelected)
    }

    func testWindowChoiceIDScriptIsStable() {
        let pid: pid_t = 4242
        let id1 = WindowChoiceID.script(processIdentifier: pid, windowIndex: 3)
        let id2 = WindowChoiceID.script(processIdentifier: pid, windowIndex: 3)
        let idDifferent = WindowChoiceID.script(processIdentifier: pid, windowIndex: 4)

        XCTAssertEqual(id1, id2)
        XCTAssertNotEqual(id1, idDifferent)
    }
}
