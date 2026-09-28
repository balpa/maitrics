import SwiftUI
import MaitricsCore
import ServiceManagement

struct SettingsView: View {
    let settings: AppSettings
    var onCostModeChange: () -> Void = {}
    @State private var launchAtLogin: Bool = false
    @State private var refreshMode: RefreshMode = .adaptive
    @State private var notificationsEnabled = true
    @State private var alertThresholds: Set<Int> = []
    @State private var notifyOnReset = true
    @State private var pricingRefreshing = false
    @State private var includeCacheInCost = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // Connection status
                SectionLabel(text: "Connection")
                connectionStatus

                Divider().opacity(0.1)

                SectionLabel(text: "Refresh")
                refreshSettings

                Divider().opacity(0.1)

                SectionLabel(text: "Notifications")
                notificationSettings

                Divider().opacity(0.1)

                // Pricing (read-only)
                SectionLabel(text: "Model Pricing")
                costModeSetting
                pricingDisplay

                Divider().opacity(0.1)

                // General
                SectionLabel(text: "General")
                HStack {
                    Text("Launch at login")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.85))
                    Spacer()
                    SwitchToggle(isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, enabled in
                            settings.launchAtLogin = enabled
                            try? enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                        }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .onAppear {
            includeCacheInCost = settings.includeCacheInCost
            launchAtLogin = settings.launchAtLogin
            refreshMode = settings.refreshMode
            notificationsEnabled = settings.notificationsEnabled
            alertThresholds = Set(settings.alertThresholds)
            notifyOnReset = settings.notifyOnReset
        }
    }

    private static let thresholdOptions = [50, 70, 80, 90, 95]

    private var costModeSetting: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Include cache tokens in cost")
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.85))
                Spacer()
                SwitchToggle(isOn: $includeCacheInCost)
                    .onChange(of: includeCacheInCost) { _, enabled in
                        guard enabled != settings.includeCacheInCost else { return }
                        settings.includeCacheInCost = enabled
                        onCostModeChange()
                    }
            }
            Text(includeCacheInCost
                 ? "API-equivalent cost: input, output, cache read and cache write"
                 : "Input and output tokens only")
                .font(.system(size: 9))
                .foregroundColor(Color(white: 0.5))
        }
    }

    private var refreshSettings: some View {
        VStack(alignment: .leading, spacing: 6) {
            ChipPicker(options: RefreshMode.allCases, selection: $refreshMode, label: \.label)
                .onChange(of: refreshMode) { _, mode in settings.refreshMode = mode }
            Text(refreshDescription)
                .font(.system(size: 9))
                .foregroundColor(Color(white: 0.5))
        }
    }

    private var refreshDescription: String {
        switch refreshMode {
        case .adaptive: return "Every minute while Claude Code is running, every 10 minutes when idle"
        case .manual: return "Only when the popover opens or Claude Code writes its stats"
        default: return "Every \(refreshMode.rawValue), and when the popover opens"
        }
    }

    private var notificationSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Usage alerts")
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.85))
                Spacer()
                SwitchToggle(isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, enabled in settings.notificationsEnabled = enabled }
            }
            if notificationsEnabled {
                HStack(spacing: 6) {
                    Text("Notify at")
                        .font(.system(size: 10))
                        .foregroundColor(Color(white: 0.7))
                    ForEach(Self.thresholdOptions, id: \.self) { value in
                        let selected = alertThresholds.contains(value)
                        Button(action: { toggleThreshold(value) }) {
                            Text("\(value)%")
                                .font(.system(size: 9, weight: selected ? .bold : .regular))
                                .foregroundColor(selected ? .white : Color(white: 0.65))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(selected ? Color.blue.opacity(0.6) : Color.white.opacity(0.06))
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }
                }
                HStack {
                    Text("Notify when a limit resets")
                        .font(.system(size: 10))
                        .foregroundColor(Color(white: 0.7))
                    Spacer()
                    SwitchToggle(isOn: $notifyOnReset)
                        .onChange(of: notifyOnReset) { _, enabled in settings.notifyOnReset = enabled }
                }
                Button("Send test notification") {
                    NotificationService.shared.post(title: "Session limit at 80%", body: "Maitrics notifications are working.")
                }
                .buttonStyle(.plain)
                .focusable(false)
                .font(.system(size: 9))
                .foregroundColor(Color(red: 96/255, green: 165/255, blue: 250/255))
            }
        }
    }

    private func toggleThreshold(_ value: Int) {
        if alertThresholds.contains(value) {
            alertThresholds.remove(value)
        } else {
            alertThresholds.insert(value)
        }
        settings.alertThresholds = Array(alertThresholds)
    }


    @State private var isRelogging = false

    private var connectionStatus: some View {
        VStack(alignment: .leading, spacing: 6) {
            if UsageAPIClient.hasToken {
                HStack(spacing: 6) {
                    Circle().fill(Color(red: 74/255, green: 222/255, blue: 128/255)).frame(width: 6, height: 6)
                    Text("Connected via Claude Code")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(white: 0.85))
                    Spacer()
                    Button("Re-login") {
                        relogin()
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .font(.system(size: 9))
                    .foregroundColor(Color(white: 0.55))
                }
                if let error = UsageAPIClient.lastError {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 9))
                        Text(errorMessage(error))
                        Spacer()
                        Button("Re-login to fix") {
                            relogin()
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Color(red: 96/255, green: 165/255, blue: 250/255))
                    }
                    .font(.system(size: 9))
                    .foregroundColor(Color(red: 255/255, green: 176/255, blue: 85/255))
                }
            } else {
                HStack(spacing: 6) {
                    Circle().fill(Color(red: 255/255, green: 85/255, blue: 85/255)).frame(width: 6, height: 6)
                    Text("Not connected")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(white: 0.85))
                    Spacer()
                    Button("Login") {
                        relogin()
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Color(red: 96/255, green: 165/255, blue: 250/255))
                }
                Text("Claude Code CLI required")
                    .font(.system(size: 9))
                    .foregroundColor(Color(white: 0.5))
            }

            if isRelogging {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.small)
                    Text("Opening Claude Code login...")
                        .font(.system(size: 9))
                        .foregroundColor(Color(white: 0.6))
                }
            }
        }
    }

    private func relogin() {
        isRelogging = true
        // Launch `claude` CLI which triggers the OAuth flow in browser
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["claude", "--login"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
            await MainActor.run { isRelogging = false }
        }
    }

    private var pricingDisplay: some View {
        VStack(alignment: .leading, spacing: 8) {
            let pricing = PricingUpdater.effectivePricing

            ForEach(["fable", "opus", "sonnet", "haiku"], id: \.self) { model in
                if let tier = pricing[model] {
                    HStack {
                        Text(model.capitalized)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color(white: 0.85))
                            .frame(width: 50, alignment: .leading)
                        Group {
                            label("In", value: tier.inputPer1M)
                            label("Out", value: tier.outputPer1M)
                            label("C.R", value: tier.cacheReadPer1M)
                            label("C.W", value: tier.cacheWritePer1M)
                        }
                    }
                }
            }

            HStack {
                if let version = PricingUpdater.lastUpdateDate {
                    Text("Updated: \(version)")
                } else {
                    Text("Using built-in defaults")
                }
                Spacer()
                Button(action: {
                    pricingRefreshing = true
                    Task {
                        await PricingUpdater.checkForUpdates(settings: settings, force: true)
                        await MainActor.run { pricingRefreshing = false }
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: pricingRefreshing ? "arrow.clockwise" : "arrow.clockwise")
                            .rotationEffect(pricingRefreshing ? .degrees(360) : .degrees(0))
                        Text("Refresh")
                    }
                }
                .buttonStyle(.plain)
            .focusable(false)
                .font(.system(size: 9))
                .foregroundColor(Color(white: 0.6))
                .disabled(pricingRefreshing)
            }
            .font(.system(size: 9))
            .foregroundColor(Color(white: 0.5))
        }
    }

    private func label(_ name: String, value: Double) -> some View {
        VStack(spacing: 1) {
            Text(name)
                .font(.system(size: 7))
                .foregroundColor(Color(white: 0.5))
            Text("$\(value, specifier: value < 1 ? "%.2f" : "%.0f")")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color(white: 0.7))
        }
        .frame(maxWidth: .infinity)
    }


    private func errorMessage(_ error: UsageAPIClient.APIError) -> String {
        switch error {
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter { return "Rate limited. Retry in \(seconds)s" }
            return "Rate limited. Try again later"
        case .unauthorized:
            return "Token expired. Re-login to Claude Code"
        case .serverError(let code):
            return "API error (\(code))"
        case .networkError(let msg):
            return "Network: \(msg)"
        }
    }
}

struct SwitchToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button(action: { isOn.toggle() }) {
            RoundedRectangle(cornerRadius: 10)
                .fill(isOn ? Color(red: 74/255, green: 222/255, blue: 128/255) : Color(white: 0.2))
                .frame(width: 36, height: 20)
                .overlay(
                    Circle()
                        .fill(.white)
                        .frame(width: 16, height: 16)
                        .offset(x: isOn ? 8 : -8),
                    alignment: .center
                )
                .animation(.easeInOut(duration: 0.15), value: isOn)
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}
