import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: SettingsStore
    @State private var showsClaudeCookieConsent = false

    var body: some View {
        Form {
            experienceSection
            interfaceSection
            providersSection
            widgetSection
            menuBarSection
            analyticsSection
            notificationsSection
            if settings.experienceMode == .pro { proSection }
            privacySection
        }
        .formStyle(.grouped)
        .padding(18)
    }

    private var providersSection: some View {
        Section(tr(settings.language, "Сервисы", "Providers")) {
            LabeledContent {
                HStack(spacing: 7) {
                    Circle()
                        .fill(connectionColor(state.claude.state))
                        .frame(width: 7, height: 7)
                    Text(claudeConnectionTitle)
                }
            } label: {
                Label("Claude Web", systemImage: ProviderKind.claude.symbol)
                    .foregroundStyle(ProviderKind.claude.tint)
            }

            if settings.experienceMode == .pro {
                Picker(tr(settings.language, "Источник Claude", "Claude source"), selection: $settings.claudeUsageSource) {
                    ForEach(ClaudeUsageSource.allCases) { source in
                        Text(claudeUsageSourceTitle(source, language: settings.language)).tag(source)
                    }
                }
            }

            if settings.claudeUsageSource == .off {
                Button {
                    state.beginClaudeConnectorPairing()
                } label: {
                    Label(tr(settings.language, "Подключить Claude Web", "Connect Claude Web"), systemImage: "puzzlepiece.extension")
                }
                .disabled(state.claude.state == .loading)
            } else if settings.claudeUsageSource == .browserExtension {
                claudeConnectorControls
            } else if settings.claudeUsageSource == .web && !settings.claudeBrowserCookieImportAllowed {
                Button {
                    showsClaudeCookieConsent = true
                } label: {
                    Label(
                        tr(settings.language, "Разрешить чтение сессии Chrome", "Allow Chrome session access"),
                        systemImage: "lock.open"
                    )
                }
                .disabled(state.claude.state == .loading)
            } else {
                HStack {
                    Button {
                        Task { await state.refreshClaudeConnection() }
                    } label: {
                        Label(tr(settings.language, "Проверить подключение", "Test connection"), systemImage: "arrow.clockwise")
                    }
                    .disabled(state.claude.state == .loading)
                    Spacer()
                    Button(role: .destructive) {
                        settings.claudeUsageSource = .off
                        settings.claudeBrowserCookieImportAllowed = false
                    } label: {
                        Text(tr(settings.language, "Отключить", "Disconnect"))
                    }
                }
            }

            if state.claude.state != .connected,
               settings.claudeUsageSource != .off,
               let message = state.claude.message {
                Label(claudeRecoveryText(message), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if state.claude.state == .connected {
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr(settings.language, "Живые лимиты Claude", "Live Claude limits"))
                            .font(.callout.weight(.semibold))
                        Text(
                            tr(settings.language, "Получено из Chrome ", "Received from Chrome ")
                            + localizedDate(state.claude.updatedAt, language: settings.language, dateStyle: .none, timeStyle: .short)
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let plan = state.claudeAccountDetails.planName {
                        Text(plan).font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(claudeQuotaMeters(state.claudeAccountDetails, language: settings.language)) { meter in
                    ClaudeQuotaMeterView(meter: meter, language: settings.language, compact: true)
                        .padding(.vertical, 4)
                }
            }

            Text(tr(
                settings.language,
                "Pulse Connector передаёт из Chrome только проценты и время сброса. Cookie и история чатов не покидают браузер. Legacy-режим CodexBar может сохранить зашифрованную сессию в macOS Keychain.",
                "Pulse Connector sends only percentages and reset times from Chrome. Cookies and chat history never leave the browser. Legacy CodexBar mode may cache the encrypted session in macOS Keychain."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onChange(of: settings.claudeUsageSource) { _ in
            if settings.claudeUsageSource == .browserExtension {
                state.refreshClaudeConnectorState()
                if !state.claudeConnectorPaired && state.claudePairingCode == nil {
                    state.beginClaudeConnectorPairing()
                }
            } else {
                Task { await state.refreshClaudeConnection() }
            }
        }
        .alert(
            tr(settings.language, "Разрешить чтение сессии Chrome?", "Allow Chrome session access?"),
            isPresented: $showsClaudeCookieConsent
        ) {
            Button(tr(settings.language, "Отмена", "Cancel"), role: .cancel) {}
            Button(tr(settings.language, "Разрешить и подключить", "Allow and connect")) {
                settings.claudeBrowserCookieImportAllowed = true
                if settings.claudeUsageSource == .web {
                    Task { await state.refreshClaudeConnection() }
                } else {
                    settings.claudeUsageSource = .web
                }
            }
        } message: {
            Text(tr(
                settings.language,
                "CodexBar прочитает cookies claude.ai, чтобы запросить проценты лимитов и время сброса. Pulse не получает и не хранит cookies, но CodexBar может закэшировать зашифрованный заголовок сессии в macOS Keychain. Доступ можно отключить здесь в любой момент.",
                "CodexBar will read claude.ai cookies to request quota percentages and reset times. Pulse never receives or stores cookies, but CodexBar may cache the encrypted session header in macOS Keychain. You can disconnect it here at any time."
            ))
        }
    }

    @ViewBuilder
    private var claudeConnectorControls: some View {
        if state.claudeConnectorPaired {
            HStack {
                Label(tr(settings.language, "Расширение связано", "Extension paired"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.pulseGreen)
                Spacer()
                Button(tr(settings.language, "Переподключить", "Pair again")) {
                    state.beginClaudeConnectorPairing()
                }
                Button(role: .destructive) {
                    state.revokeClaudeConnector()
                } label: {
                    Text(tr(settings.language, "Отключить", "Disconnect"))
                }
            }
        } else {
            if let code = state.claudePairingCode {
                LabeledContent(tr(settings.language, "Код подключения", "Pairing code")) {
                    HStack(spacing: 8) {
                        Text(code)
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .textSelection(.enabled)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(code, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help(tr(settings.language, "Скопировать код", "Copy code"))
                    }
                }
            }
            HStack {
                Button {
                    revealClaudeExtension()
                } label: {
                    Label(tr(settings.language, "Показать расширение", "Show extension folder"), systemImage: "folder")
                }
                Button {
                    state.beginClaudeConnectorPairing()
                } label: {
                    Label(tr(settings.language, "Новый код", "New code"), systemImage: "arrow.clockwise")
                }
            }
            Text(tr(
                settings.language,
                "В Chrome откройте chrome://extensions, включите режим разработчика, выберите «Загрузить распакованное расширение» и укажите папку PulseConnector. Затем введите код выше в расширении.",
                "In Chrome, open chrome://extensions, enable Developer mode, choose Load unpacked, and select the PulseConnector folder. Then enter the code above in the extension."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func revealClaudeExtension() {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("PulseConnector")
        let development = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("BrowserExtension/PulseConnector")
        let target = bundled.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil } ?? development
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    private var experienceSection: some View {
        Section(tr(settings.language, "Режим", "Experience")) {
            Picker(tr(settings.language, "Интерфейс", "Interface"), selection: $settings.experienceMode) {
                ForEach(ExperienceMode.allCases) { mode in
                    Text(L10n.experienceTitle(mode, language: settings.language)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            Text(settings.experienceMode == .simple
                 ? tr(settings.language, "Только понятные решения и безопасные пресеты.", "Clear decisions and safe presets only.")
                 : tr(settings.language, "Подробная аналитика, пороги и диагностика.", "Detailed analytics, thresholds, and diagnostics."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var interfaceSection: some View {
        Section(tr(settings.language, "Интерфейс", "Interface")) {
            Picker(tr(settings.language, "Язык", "Language"), selection: $settings.language) {
                ForEach(AppLanguage.allCases) { language in Text(language.shortTitle).tag(language) }
            }
            .pickerStyle(.segmented)

            Picker(tr(settings.language, "Тема", "Theme"), selection: $settings.theme) {
                ForEach(AppTheme.allCases) { theme in Text(L10n.themeTitle(theme, language: settings.language)).tag(theme) }
            }
            .pickerStyle(.segmented)

            Toggle(tr(settings.language, "Запускать при входе", "Launch at login"), isOn: $settings.launchAtLogin)
            if !settings.launchAtLoginError.isEmpty {
                Text(tr(settings.language, "Не удалось включить автозапуск: ", "Could not enable launch at login: ") + settings.launchAtLoginError)
                    .font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var widgetSection: some View {
        Section(tr(settings.language, "Виджет", "Widget")) {
            Toggle(tr(settings.language, "Показывать поверх окон", "Show above windows"), isOn: $settings.showFloatingWidget)
                .onChange(of: settings.showFloatingWidget) { _ in state.syncFloatingPanel() }

            Picker(tr(settings.language, "Размер", "Size"), selection: $settings.widgetPresentation) {
                ForEach(WidgetPresentation.allCases) { value in
                    Text(L10n.widgetTitle(value, language: settings.language)).tag(value)
                }
            }
            Button(tr(settings.language, "Показать виджет сейчас", "Show widget now")) {
                settings.showFloatingWidget = true
                FloatingPanelController.shared.showAndFocus()
            }

            if settings.experienceMode == .pro {
                HStack {
                    Text(tr(settings.language, "Прозрачность", "Opacity"))
                    Slider(value: $settings.widgetOpacity, in: 0.45 ... 1.0)
                    Text("\(Int(settings.widgetOpacity * 100))%")
                        .font(.caption.monospacedDigit()).frame(width: 42)
                }
                Toggle(tr(settings.language, "Закрепить положение", "Lock position"), isOn: $settings.widgetLocked)
                Toggle(tr(settings.language, "Пропускать клики", "Click through"), isOn: $settings.widgetClickThrough)
                Toggle(tr(settings.language, "Показывать на всех рабочих столах", "Show on all Spaces"), isOn: $settings.widgetAllSpaces)
            }
        }
    }

    private var menuBarSection: some View {
        Section(tr(settings.language, "Строка меню", "Menu bar")) {
            Picker(tr(settings.language, "Представление", "Preset"), selection: $settings.menuBarStyle) {
                ForEach(availableMenuStyles) { style in
                    Text(L10n.menuStyleTitle(style, language: settings.language)).tag(style)
                }
            }
            Text(tr(settings.language, "Пульс + процент остаётся основным спокойным пресетом.", "Pulse + percentage remains the calm default."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var analyticsSection: some View {
        Section(tr(settings.language, "Использование и расходы", "Usage and costs")) {
            Toggle(tr(settings.language, "Детальная аналитика токенов", "Detailed token analytics"), isOn: $settings.analyticsEnabled)
                .onChange(of: settings.analyticsEnabled) { _ in Task { await state.refresh(forceAnalytics: true) } }
            Picker(tr(settings.language, "Период", "Period"), selection: $settings.usagePeriod) {
                Text("7d").tag(UsagePeriod.week)
                Text("30d").tag(UsagePeriod.month)
                Text("90d").tag(UsagePeriod.quarter)
            }
            .pickerStyle(.segmented)
            .onChange(of: settings.usagePeriod) { period in state.selectUsagePeriod(period) }
            Toggle(tr(settings.language, "Показывать оценочную стоимость", "Show estimated cost"), isOn: $settings.showEstimatedCost)
            LabeledContent(
                tr(settings.language, "Claude Web", "Claude Web"),
                value: tr(settings.language, "Лимиты, сбросы и темп", "Quotas, resets, and pace")
            )
            LabeledContent(
                tr(settings.language, "Токены и проекты Claude Web", "Claude Web tokens and projects"),
                value: tr(settings.language, "Источник не предоставляет", "Not provided by source")
            )
            Text(tr(
                settings.language,
                "Pulse локально хранит историю процентов каждого окна Codex и Claude. Токены, модели, проекты и стоимость показываются только для источников, которые действительно передают эти агрегаты. Тексты задач не сохраняются.",
                "Pulse stores percentage history for every Codex and Claude window locally. Tokens, models, projects, and cost appear only for sources that actually provide those aggregates. Task text is never stored."
            ))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var notificationsSection: some View {
        Section(tr(settings.language, "Оповещения", "Alerts")) {
            Toggle(tr(settings.language, "Предупреждать о лимите", "Quota alerts"), isOn: $settings.notificationsEnabled)
            Toggle(tr(settings.language, "Прогнозировать исчерпание", "Predict exhaustion"), isOn: $settings.predictiveAlerts)
            Toggle(tr(settings.language, "Звук", "Sound"), isOn: $settings.notificationSound)
            if settings.notificationsEnabled {
                Button(tr(settings.language, "Разрешить системные уведомления", "Allow system notifications")) {
                    Task {
                        let allowed = await state.requestNotificationPermission()
                        state.notificationPermissionMessage = allowed
                            ? tr(settings.language, "Уведомления разрешены", "Notifications allowed")
                            : tr(settings.language, "Разрешение не выдано", "Permission not granted")
                    }
                }
                if !state.notificationPermissionMessage.isEmpty {
                    Text(state.notificationPermissionMessage).font(.caption).foregroundStyle(.secondary)
                }
            }
            if settings.experienceMode == .pro {
                Stepper(
                    tr(settings.language, "Предупреждение: \(settings.warningThreshold)%", "Warning: \(settings.warningThreshold)%"),
                    value: $settings.warningThreshold,
                    in: 10 ... 90,
                    step: 5
                )
                Stepper(
                    tr(settings.language, "Критично: \(settings.criticalThreshold)%", "Critical: \(settings.criticalThreshold)%"),
                    value: $settings.criticalThreshold,
                    in: 5 ... 50,
                    step: 5
                )
            }
        }
    }

    private var proSection: some View {
        Section(tr(settings.language, "Расширенные", "Advanced")) {
            Picker(tr(settings.language, "Обновление", "Refresh"), selection: $settings.refreshMinutes) {
                Text("2 min").tag(2)
                Text("5 min").tag(5)
                Text("15 min").tag(15)
                Text("30 min").tag(30)
            }
            Toggle(tr(settings.language, "Проверять статус подключённых сервисов", "Check connected service status"), isOn: $settings.statusChecksEnabled)
                .onChange(of: settings.statusChecksEnabled) { _ in Task { await state.refresh(forceAnalytics: true) } }
            Toggle(tr(settings.language, "Показывать неподключённые сервисы", "Show disconnected providers"), isOn: $settings.showUnavailableProviders)
            LabeledContent(tr(settings.language, "Источник Codex", "Codex source"), value: state.codex.source.isEmpty ? "—" : state.codex.source)
            if state.claude.state == .connected || settings.showUnavailableProviders {
                LabeledContent(tr(settings.language, "Активный источник Claude", "Active Claude source"), value: state.claude.source.isEmpty ? tr(settings.language, "Не настроен", "Not configured") : state.claude.source)
            }
        }
    }

    private var privacySection: some View {
        Section(tr(settings.language, "Конфиденциальность", "Privacy")) {
            Label(
                tr(settings.language, "Только чтение. Pulse не хранит промпты, cookies, ключи и не использует скрытую телеметрию.", "Read-only. Pulse stores no prompts, cookies, keys, or hidden telemetry."),
                systemImage: "lock.shield"
            )
            .foregroundStyle(.secondary)
        }
    }

    private var availableMenuStyles: [MenuBarStyle] {
        settings.experienceMode == .simple
            ? [.pulse, .percentage, .dual, .smart]
            : MenuBarStyle.allCases
    }

    private var claudeConnectionTitle: String {
        switch state.claude.state {
        case .connected:
            return state.claudeAccountDetails.planName
                ?? tr(settings.language, "Подключён", "Connected")
        case .loading:
            return tr(settings.language, "Подключаем…", "Connecting…")
        case .error:
            return tr(settings.language, "Ошибка подключения", "Connection error")
        case .unavailable:
            if settings.claudeUsageSource == .browserExtension {
                return state.claudeConnectorPaired
                    ? tr(settings.language, "Ожидаем данные из Chrome", "Waiting for Chrome data")
                    : tr(settings.language, "Нужно связать расширение", "Extension pairing required")
            }
            return settings.claudeUsageSource == .off
                ? tr(settings.language, "Не подключён", "Not connected")
                : tr(settings.language, "Требуется разрешение", "Permission required")
        }
    }

    private func claudeRecoveryText(_ message: String) -> String {
        if message.localizedCaseInsensitiveContains("session key")
            || message.localizedCaseInsensitiveContains("browser cookies")
        {
            return tr(
                settings.language,
                "Сессия Claude в Chrome пока не найдена. Убедитесь, что claude.ai открыт и выполнен вход, затем разрешите доступ к Chrome Safe Storage и повторите проверку.",
                "The Claude session was not found in Chrome. Make sure claude.ai is open and signed in, allow Chrome Safe Storage access, then test again."
            )
        }
        if message.localizedCaseInsensitiveContains("explicit confirmation") {
            return tr(
                settings.language,
                "Подтвердите чтение сессии Chrome. После этого Pulse проверит подключение автоматически.",
                "Confirm Chrome session access. Pulse will then test the connection automatically."
            )
        }
        if message.localizedCaseInsensitiveContains("Pulse Connector") {
            return tr(
                settings.language,
                "Установите Pulse Connector в тот профиль Chrome, где открыт Claude, введите код подключения и нажмите «Обновить» в расширении.",
                "Install Pulse Connector in the Chrome profile where Claude is open, enter the pairing code, and press Refresh in the extension."
            )
        }
        return message
    }

    private func connectionColor(_ value: ProviderConnectionState) -> Color {
        switch value {
        case .connected: .pulseGreen
        case .loading: .yellow
        case .unavailable: .secondary
        case .error: .red
        }
    }
}

struct QuickSettingsView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("", selection: $settings.experienceMode) {
                ForEach(ExperienceMode.allCases) { mode in Text(L10n.experienceTitle(mode, language: settings.language)).tag(mode) }
            }
            .labelsHidden().pickerStyle(.segmented)
            Divider()
            Picker(tr(settings.language, "Виджет", "Widget"), selection: $settings.widgetPresentation) {
                ForEach(WidgetPresentation.allCases) { value in Text(L10n.widgetTitle(value, language: settings.language)).tag(value) }
            }
            Picker(tr(settings.language, "Строка меню", "Menu bar"), selection: $settings.menuBarStyle) {
                ForEach(MenuBarStyle.allCases) { style in Text(L10n.menuStyleTitle(style, language: settings.language)).tag(style) }
            }
            Toggle(tr(settings.language, "Виджет поверх окон", "Always-on-top widget"), isOn: $settings.showFloatingWidget)
                .onChange(of: settings.showFloatingWidget) { _ in state.syncFloatingPanel() }
        }
    }
}
