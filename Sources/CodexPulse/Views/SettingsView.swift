import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Form {
            Section(tr(settings.language, "Интерфейс", "Interface")) {
                Picker(tr(settings.language, "Язык", "Language"), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.shortTitle).tag(language)
                    }
                }
                .pickerStyle(.segmented)

                Picker(tr(settings.language, "Тема", "Theme"), selection: $settings.theme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(L10n.themeTitle(theme, language: settings.language)).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(tr(settings.language, "Строка меню и виджет", "Menu bar and widget")) {
                Picker(tr(settings.language, "Значок", "Icon"), selection: $settings.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { style in
                        Text(L10n.menuStyleTitle(style, language: settings.language)).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                Toggle(tr(settings.language, "Виджет поверх окон", "Always-on-top widget"), isOn: $settings.showFloatingWidget)
                    .onChange(of: settings.showFloatingWidget) { _ in state.syncFloatingPanel() }
            }

            Section(tr(settings.language, "Обновление", "Refresh")) {
                Picker(tr(settings.language, "Интервал", "Interval"), selection: $settings.refreshMinutes) {
                    Text("2 min").tag(2)
                    Text("5 min").tag(5)
                    Text("15 min").tag(15)
                    Text("30 min").tag(30)
                }
            }

            Section(tr(settings.language, "Конфиденциальность", "Privacy")) {
                Label(
                    tr(settings.language, "Только чтение. Тексты задач и данные аккаунта не сохраняются.", "Read-only. Task text and account details are never stored."),
                    systemImage: "lock.shield"
                )
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}

struct QuickSettingsView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingRow(tr(settings.language, "Язык", "Language")) {
                Picker("", selection: $settings.language) {
                    Text("Русский").tag(AppLanguage.russian)
                    Text("English").tag(AppLanguage.english)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            Divider()
            settingRow(tr(settings.language, "Тема", "Theme")) {
                Picker("", selection: $settings.theme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(L10n.themeTitle(theme, language: settings.language)).tag(theme)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            Divider()
            settingRow(tr(settings.language, "Значок в строке меню", "Menu bar icon")) {
                Picker("", selection: $settings.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { style in
                        Text(L10n.menuStyleTitle(style, language: settings.language)).tag(style)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            Divider()
            Toggle(tr(settings.language, "Виджет поверх окон", "Always-on-top widget"), isOn: $settings.showFloatingWidget)
                .onChange(of: settings.showFloatingWidget) { _ in state.syncFloatingPanel() }
        }
    }

    private func settingRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }
}
