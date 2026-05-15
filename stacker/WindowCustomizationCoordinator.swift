import Foundation

enum StackWindowFormatter {
    static func displayTitle(for id: UInt, titles: [String], order: [UInt]) -> String {
        guard let index = order.firstIndex(of: id), titles.indices.contains(index) else {
            return "Window"
        }
        return titles[index]
    }
}
