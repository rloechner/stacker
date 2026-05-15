import ApplicationServices
import CoreGraphics

extension AXUIElement {
    static func from(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return unsafeBitCast(value, to: AXUIElement.self)
    }

    var title: String? {
        stringValue(for: kAXTitleAttribute)
    }

    var role: String? {
        stringValue(for: kAXRoleAttribute)
    }

    var subrole: String? {
        stringValue(for: kAXSubroleAttribute)
    }

    var position: CGPoint? {
        pointValue(for: kAXPositionAttribute)
    }

    var size: CGSize? {
        sizeValue(for: kAXSizeAttribute)
    }

    var topLevelUIElement: AXUIElement? {
        elementValue(for: kAXTopLevelUIElementAttribute)
    }

    var windowElement: AXUIElement? {
        elementValue(for: kAXWindowAttribute)
    }

    var isMinimized: Bool {
        boolValue(for: "AXMinimized") ?? false
    }

    var isFullscreen: Bool {
        boolValue(for: "AXFullScreen") ?? false
    }

    func set(position: CGPoint) {
        var point = position
        guard let value = AXValueCreate(.cgPoint, &point) else {
            return
        }
        AXUIElementSetAttributeValue(self, kAXPositionAttribute as CFString, value)
    }

    func set(size: CGSize) {
        var windowSize = size
        guard let value = AXValueCreate(.cgSize, &windowSize) else {
            return
        }
        AXUIElementSetAttributeValue(self, kAXSizeAttribute as CFString, value)
    }

    private func stringValue(for attribute: String) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(self, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    private func boolValue(for attribute: String) -> Bool? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(self, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? Bool
    }

    private func elementValue(for attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(self, attribute as CFString, &value)
        guard result == .success else {
            return nil
        }

        return AXUIElement.from(value)
    }

    private func pointValue(for attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(self, attribute as CFString, &value)
        guard result == .success, let axValue = value else { return nil }

        var point = CGPoint.zero
        guard CFGetTypeID(axValue) == AXValueGetTypeID() else { return nil }
        let didRead = AXValueGetValue(axValue as! AXValue, .cgPoint, &point)
        return didRead ? point : nil
    }

    private func sizeValue(for attribute: String) -> CGSize? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(self, attribute as CFString, &value)
        guard result == .success, let axValue = value else { return nil }

        var size = CGSize.zero
        guard CFGetTypeID(axValue) == AXValueGetTypeID() else { return nil }
        let didRead = AXValueGetValue(axValue as! AXValue, .cgSize, &size)
        return didRead ? size : nil
    }
}
