import Foundation

public enum Mood: String, Codable, CaseIterable, Sendable {
    case good
    case okay
    case difficult

    public var label: String {
        switch self {
        case .good: "Bem"
        case .okay: "Ok"
        case .difficult: "Difícil"
        }
    }

    public var symbol: String {
        switch self {
        case .good: "☀"
        case .okay: "◒"
        case .difficult: "☁"
        }
    }
}
