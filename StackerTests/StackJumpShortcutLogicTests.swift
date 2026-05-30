import XCTest
import Carbon
@testable import Stacker

final class StackJumpShortcutLogicTests: XCTestCase {

    func testSlotNumberMapsDigitKeyCodes() {
        XCTAssertEqual(StackJumpShortcutLogic.slotNumber(forKeyCode: UInt16(kVK_ANSI_1)), 1)
        XCTAssertEqual(StackJumpShortcutLogic.slotNumber(forKeyCode: UInt16(kVK_ANSI_9)), 9)
        XCTAssertNil(StackJumpShortcutLogic.slotNumber(forKeyCode: UInt16(kVK_ANSI_0)))
    }

    func testResolvedWindowIDUsesOneBasedSlotIndex() {
        let order: [UInt] = [101, 202, 303]
        XCTAssertEqual(StackJumpShortcutLogic.resolvedWindowID(slotNumber: 1, windowOrder: order), 101)
        XCTAssertEqual(StackJumpShortcutLogic.resolvedWindowID(slotNumber: 3, windowOrder: order), 303)
        XCTAssertNil(StackJumpShortcutLogic.resolvedWindowID(slotNumber: 4, windowOrder: order))
    }

    func testMatchesModifiersRequiresExactModifierSet() {
        let controlOnly = Int(NSEvent.ModifierFlags.control.rawValue)
        let eventFlags = CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue)
        XCTAssertTrue(StackJumpShortcutLogic.matchesModifiers(eventFlags: eventFlags, requiredRawValue: controlOnly))

        let commandEventFlags = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue)
        XCTAssertFalse(StackJumpShortcutLogic.matchesModifiers(eventFlags: commandEventFlags, requiredRawValue: controlOnly))
    }

    func testShouldHandleRequiresActiveStackSlot() {
        let controlOnly = Int(NSEvent.ModifierFlags.control.rawValue)
        let keyCode = UInt16(kVK_ANSI_2)
        let flags = CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue)

        XCTAssertTrue(
            StackJumpShortcutLogic.shouldHandle(
                isEnabled: true,
                stackerIsFrontmost: false,
                keyCode: keyCode,
                eventFlags: flags,
                requiredModifiersRawValue: controlOnly,
                frontmostPID: 42,
                windowOrder: [1, 2, 3]
            )
        )

        XCTAssertFalse(
            StackJumpShortcutLogic.shouldHandle(
                isEnabled: true,
                stackerIsFrontmost: false,
                keyCode: keyCode,
                eventFlags: flags,
                requiredModifiersRawValue: controlOnly,
                frontmostPID: 42,
                windowOrder: [1]
            )
        )

        XCTAssertFalse(
            StackJumpShortcutLogic.shouldHandle(
                isEnabled: false,
                stackerIsFrontmost: false,
                keyCode: keyCode,
                eventFlags: flags,
                requiredModifiersRawValue: controlOnly,
                frontmostPID: 42,
                windowOrder: [1, 2, 3]
            )
        )

        XCTAssertFalse(
            StackJumpShortcutLogic.shouldHandle(
                isEnabled: true,
                stackerIsFrontmost: true,
                keyCode: keyCode,
                eventFlags: flags,
                requiredModifiersRawValue: controlOnly,
                frontmostPID: 42,
                windowOrder: [1, 2, 3]
            )
        )
    }
}
