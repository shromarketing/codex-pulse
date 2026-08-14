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

enum ClaudeUsageSource: String, CaseIterable, Identifiable, Sendable {
    case off
    case browserExtension
    case web
    case oauth
    case automatic

    var id: String { rawValue }

    var commandValue: String? {
        switch self {
        case .off: nil
        case .browserExtension: nil
        case .web: "web"
        case .oauth: "oauth"
        case .automatic: "auto"
        }
    }
}

struct QuotaWindow: Codable, Hashable, Sendable {
    let usedPercent: Double
    let resetsAt: Date?
    let windowMinutes: Int?

    var remainingPercent: Double {
        max(0, min(100, 100 - usedPercent))
    }
}

struct CodexQuotaBucket: Hashable, Identifiable, Sendable {
    let id: String
    let name: String?
    let planType: String?
    let primary: QuotaWindow?
    let secondary: QuotaWindow?
    let creditBalance: String?
    let hasCredits: Bool?
    let unlimitedCredits: Bool
}

struct CodexAccountDetails: Hashable, Sendable {
    let quotaBuckets: [CodexQuotaBucket]
    let planType: String?
    let creditBalance: String?
    let resetCreditsAvailable: Int

    static let empty = CodexAccountDetails(
        quotaBuckets: [],
        planType: nil,
        creditBalance: nil,
        resetCreditsAvailable: 0
    )
}

enum ClaudeQuotaScope: String, Hashable, Sendable {
    case session
    case weekly
    case modelWeekly
}

struct ClaudeQuotaMeter: Hashable, Identifiable, Sendable {
    let id: String
    let scope: ClaudeQuotaScope
    let providerTitle: String?
    let window: QuotaWindow
    let usageKnown: Bool
}

struct ClaudeAccountDetails: Hashable, Sendable {
    let quotaMeters: [ClaudeQuotaMeter]
    let planName: String?
    let creditBalance: String?

    static let empty = ClaudeAccountDetails(
        quotaMeters: [],
        planName: nil,
        creditBalance: nil
    )
}

struct ClaudeProviderData: Sendable {
    let snapshot: ProviderSnapshot
    let accountDetails: ClaudeAccountDetails

    static func unavailable(message: String) -> ClaudeProviderData {
        ClaudeProviderData(
            snapshot: .unavailable(.claude, message: message),
            accountDetails: .empty
        )
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

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case russian
    case english

    var id: String { rawValue }
    var shortTitle: String { self == .russian ? "Русский" : "English" }
    var locale: Locale { Locale(identifier: self == .russian ? "ru_RU" : "en_US") }

    static var systemDefault: AppLanguage {
        Locale.preferredLanguages.first?.hasPrefix("ru") == true ? .russian : .english
    }
}

enum AppTheme: String, CaseIterable, Identifiable, Sendable {
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

enum MenuBarStyle: String, CaseIterable, Identifiable, Sendable {
    case pulse
    case percentage
    case dual
    case smart
    case today
    case pace

    var id: String { rawValue }
}

enum ExperienceMode: String, CaseIterable, Identifiable, Sendable {
    case simple
    case pro
    var id: String { rawValue }
}

enum WidgetPresentation: String, CaseIterable, Identifiable, Sendable {
    case mini
    case compact
    case focus
    case adaptive
    var id: String { rawValue }
}

enum UsagePeriod: Int, CaseIterable, Identifiable, Sendable {
    case week = 7
    case month = 30
    case quarter = 90
    var id: Int { rawValue }
}

enum RouterModel: String, CaseIterable, Codable, Sendable {
    case luna = "Luna"
    case terra = "Terra"
    case sol = "Sol"
}

enum ReasoningEffort: String, CaseIterable, Codable, Sendable {
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

enum RouterAnalysisMode: String, CaseIterable, Identifiable, Sendable {
    case ai
    case local

    var id: String { rawValue }
}

enum RouterSource: String, Sendable {
    case codexAI
    case localRules
    case localFallback
}

enum RouterConfidence: String, Codable, Sendable {
    case low
    case medium
    case high
}

enum RouterTaskShape: String, Codable, Sendable {
    case quick
    case writing
    case research
    case coding
    case design
    case documents
    case automation
    case architecture
    case review
    case other
}

struct RouteStage: Codable, Sendable {
    let model: RouterModel
    let effort: ReasoningEffort
    let titleRU: String
    let titleEN: String
}

struct RouteRecommendation: Sendable {
    let model: RouterModel
    let effort: ReasoningEffort
    let provider: ProviderKind
    let estimate: UsageEstimate
    let source: RouterSource
    let confidence: RouterConfidence
    let taskShape: RouterTaskShape
    let needsSplit: Bool
    let stages: [RouteStage]
    let rationaleRU: String
    let rationaleEN: String
    let estimatedTokensLow: Int64?
    let estimatedTokensHigh: Int64?
}

extension Color {
    static let pulseTeal = Color(red: 0.19, green: 0.78, blue: 0.78)
    static let pulseOrange = Color(red: 1.0, green: 0.43, blue: 0.18)
    static let pulseGreen = Color(red: 0.25, green: 0.78, blue: 0.46)
}
