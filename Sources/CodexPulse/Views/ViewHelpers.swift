import Foundation
import SwiftUI

func tr(_ language: AppLanguage, _ ru: String, _ en: String) -> String {
    L10n.text(language, ru: ru, en: en)
}

func percentText(_ value: Double?) -> String {
    guard let value else { return "—" }
    return "\(Int(value.rounded()))%"
}

func resetText(_ date: Date?, language: AppLanguage) -> String {
    guard let date else { return tr(language, "Нет данных", "No data") }
    let interval = max(0, date.timeIntervalSinceNow)
    let days = Int(interval) / 86_400
    let hours = (Int(interval) % 86_400) / 3_600
    let minutes = (Int(interval) % 3_600) / 60
    if days > 0 { return tr(language, "через \(days) д \(hours) ч", "in \(days)d \(hours)h") }
    if hours > 0 { return tr(language, "через \(hours) ч \(minutes) мин", "in \(hours)h \(minutes)m") }
    return tr(language, "через \(minutes) мин", "in \(minutes)m")
}

struct PulseSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }
}

extension View {
    func pulseSurface() -> some View { modifier(PulseSurfaceModifier()) }
}
