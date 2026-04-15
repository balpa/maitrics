import SwiftUI
import MaitricsCore
import ServiceManagement

struct SettingsView: View {
    let settings: AppSettings
    @State private var greenThreshold: String = ""
    @State private var yellowThreshold: String = ""
    @State private var launchAtLogin: Bool = false
    @State private var pricingRefreshing = false
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // Connection status
                SectionLabel(text: "Connection")
                connectionStatus

                Divider().opacity(0.1)

                // Thresholds
                SectionLabel(text: "Icon Thresholds")
                VStack(alignment: .leading, spacing: 8) {
                    settingsRow(color: .green, label: "Green below", text: $greenThreshold)
                    settingsRow(color: .yellow, label: "Yellow below", text: $yellowThreshold)
                    HStack(spacing: 6) {
                        Circle().fill(.red).frame(width: 6, height: 6)
                        Text("Red above yellow threshold")
                            .font(.system(size: 10))
                            .foregroundColor(Color(white: 0.55))
                    }
                }
                .onChange(of: greenThreshold) { _, _ in debounceSaveThresholds() }
                .onChange(of: yellowThreshold) { _, _ in debounceSaveThresholds() }

                Divider().opacity(0.1)

                // Pricing (read-only)
                SectionLabel(text: "Model Pricing")
                pricingDisplay

                Divider().opacity(0.1)

                // General
                SectionLabel(text: "General")
                HStack {
                    Text("Launch at login")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.85))
                    Spacer()
                    Button(action: {
                        launchAtLogin.toggle()
                        settings.launchAtLogin = launchAtLogin
                        if #available(macOS 13.0, *) {
                            try? launchAtLogin ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                        }
                    }) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(launchAtLogin ? Color(red: 74/255, green: 222/255, blue: 128/255) : Color(white: 0.2))
                            .frame(width: 36, height: 20)
                            .overlay(
                                Circle()
                                    .fill(.white)
                                    .frame(width: 16, height: 16)
                                    .offset(x: launchAtLogin ? 8 : -8),
                                alignment: .center
                            )
                            .animation(.easeInOut(duration: 0.15), value: launchAtLogin)
                    }
                    .buttonStyle(.plain)
            .focusable(false)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .onAppear {
            greenThreshold = "\(settings.thresholdGreen)"
            yellowThreshold = "\(settings.thresholdYellow)"
            launchAtLogin = settings.launchAtLogin
        }
    }

    private func debounceSaveThresholds() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            guard !Task.isCancelled else { return }
            settings.thresholdGreen = Int(greenThreshold) ?? 100_000
            settings.thresholdYellow = Int(yellowThreshold) ?? 500_000
        }
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

            ForEach(["opus", "sonnet", "haiku"], id: \.self) { model in
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
                        // Force a fresh check by clearing the cache
                        try? FileManager.default.removeItem(atPath: NSHomeDirectory() + "/.claude/maitrics-pricing-cache.json")
                        await PricingUpdater.checkForUpdates(settings: settings)
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

    private func settingsRow(color: Color, label: String, text: Binding<String>) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Color(white: 0.7))
            TextField("100000", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 10, design: .monospaced))
                .padding(4)
                .background(Color.white.opacity(0.06))
                .cornerRadius(4)
                .frame(width: 80)
            Text("tokens")
                .font(.system(size: 9))
                .foregroundColor(Color(white: 0.5))
        }
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
