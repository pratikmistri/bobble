import Foundation

enum ChatHeadsLayoutMode: String, CaseIterable, Codable, Identifiable {
    case vertical
    case horizontal

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .vertical:
            return "Vertical"
        case .horizontal:
            return "Horizontal"
        }
    }
}
