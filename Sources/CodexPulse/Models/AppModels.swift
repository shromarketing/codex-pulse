import Foundation
import SwiftUI

enum ProviderKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case codex
    case claude

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
    var symbol: String { self == .codex ? "waveform.path.ecg" : "sparkles" }
    var tint: Color { self == .codex ? .pulseTeal : .pulseOrange }
}

struct QuotaWindow: Codable, Hashable, Sendable {
    let usedPercent: Double
    let resetsAt: Date?
    let windowMinutes: Int?

    var remainingPercent: Double {
        max(0, min(100, 100 - usedPercent))
    }
}

struct UsagePoint: Codable, Hashable, Identifiable, Sendable {
    let date: Date
    let provider: ProviderKind
    let usedPercent: Double

    var id: String { "\(provider.rawValue)-\(date.timeIntervalSince1970)" }
}

enum ProviderConnectionState: String, Codable, Sendable {
    case connected
    case unavailable
    case loading
    case error
}

struct ProviderSnapshot: Identifiable, Sendable {
    let provider: ProviderKind
    let state: ProviderConnectionState
    let quota: QuotaWindow?
    let source: String
    let message: String?
    let updatedAt: Date
    let history: [UsagePoint]

    var id: String { provider.rawValue }
    var remainingPercent: Double? { quota?.remainingPercent }

    static func loading(_ provider: ProviderKind) -> ProviderSnapshot {
        ProviderSnapshot(
            provider: provider,
            state: .loading,
            quota: nil,
            source: "",
            message: nil,
            updatedAt: .now,
            history: []
        )
    }

    static func unavailable(_ provider: ProviderKind, message: String) -> ProviderSnapshot {
        ProviderSnapshot(
            provider: provider,
            state: .unavailable,
            quota: nil,
            source: "",
            message: message,
            updatedAt: .now,
            history: []
        )
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case russian
    case english

    var id: String { rawValue }
    var shortTitle: String { self == .russian ? "Русский" : "English" }

    static var systemDefault: AppLanguage {
        Locale.preferredLanguages.first?.hasPrefix("ru") == true ? .russian : .english
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case pulse
    case percentage
    case dual

    var id: String { rawValue }
}

enum RouterModel: String, Sendable {
    case luna = "Luna"
    case terra = "Terra"
    case sol = "Sol"
}

enum ReasoningEffort: String, Sendable {
    case low
    case medium
    case high
    case xhigh
}

enum UsageEstimate: String, Sendable {
    case low
    case medium
    case high
}

struct RouteRecommendation: Sendable {
    let model: RouterModel
    let effort: ReasoningEffort
    let provider: ProviderKind
    let estimate: UsageEstimate
    let rationaleRU: String
    let rationaleEN: String
}

extension Color {
    static let pulseTeal = Color(red: 0.19, green: 0.78, blue: 0.78)
    static let pulseOrange = Color(red: 1.0, green: 0.43, blue: 0.18)
    static let pulseGreen = Color(red: 0.25, green: 0.78, blue: 0.46)
}
