import SwiftUI
import MaitricsCore
import ServiceManagement

struct SettingsView: View {
    let settings: AppSettings
    @State private var greenThreshold: String = ""
    @State private var yellowThreshold: String = ""
    @State private var claudePath: String = ""
    @State private var launchAtLogin: Bool = false
    @State private var saved = false

    @State private var opusInput: String = ""
    @State private var opusOutput: String = ""
    @State private var opusCacheRead: String = ""
    @State private var opusCacheWrite: String = ""
    @State private var sonnetInput: String = ""
    @State private var sonnetOutput: String = ""
    @State private var sonnetCacheRead: String = ""
    @State private var sonnetCacheWrite: String = ""
    @State private var haikuInput: String = ""
    @State private var haikuOutput: String = ""
    @State private var haikuCacheRead: String = ""
    @State private var haikuCacheWrite: String = ""

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
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

                Divider().opacity(0.1)

                // Pricing
                SectionLabel(text: "Model Pricing (per 1M tokens)")
                VStack(alignment: .leading, spacing: 10) {
                    pricingRow(model: "Opus", input: $opusInput, output: $opusOutput, cacheR: $opusCacheRead, cacheW: $opusCacheWrite)
                    pricingRow(model: "Sonnet", input: $sonnetInput, output: $sonnetOutput, cacheR: $sonnetCacheRead, cacheW: $sonnetCacheWrite)
                    pricingRow(model: "Haiku", input: $haikuInput, output: $haikuOutput, cacheR: $haikuCacheRead, cacheW: $haikuCacheWrite)
                }

                Divider().opacity(0.1)

                // General
                SectionLabel(text: "General")
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.85))
                        .toggleStyle(.switch)
                        .controlSize(.small)

                    HStack(spacing: 8) {
                        Text("Data path")
                            .font(.system(size: 10))
                            .foregroundColor(Color(white: 0.6))
                        TextField("~/.claude", text: $claudePath)
                            .textFieldStyle(.plain)
                            .font(.system(size: 10))
                            .padding(4)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(4)
                    }
                }

                // Actions
                HStack {
                    Button("Reset") { loadDefaults() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundColor(Color(white: 0.55))

                    Spacer()

                    if saved {
                        Text("Saved")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color(red: 74/255, green: 222/255, blue: 128/255))
                            .transition(.opacity)
                    }

                    Button("Save") {
                        save()
                        withAnimation { saved = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { saved = false }
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.6))
                    .cornerRadius(4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .onAppear { loadCurrent() }
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

    private func pricingRow(model: String, input: Binding<String>, output: Binding<String>, cacheR: Binding<String>, cacheW: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(model)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color(white: 0.85))
            HStack(spacing: 4) {
                pricingField("In", value: input)
                pricingField("Out", value: output)
                pricingField("C.Read", value: cacheR)
                pricingField("C.Write", value: cacheW)
            }
        }
    }

    private func pricingField(_ label: String, value: Binding<String>) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(Color(white: 0.5))
            TextField("0", text: value)
                .textFieldStyle(.plain)
                .font(.system(size: 10, design: .monospaced))
                .padding(3)
                .background(Color.white.opacity(0.06))
                .cornerRadius(3)
                .frame(maxWidth: .infinity)
        }
    }

    private func loadCurrent() {
        greenThreshold = "\(settings.thresholdGreen)"
        yellowThreshold = "\(settings.thresholdYellow)"
        claudePath = settings.claudeDataPath
        launchAtLogin = settings.launchAtLogin
        let pricing = settings.customPricing ?? [:]
        let opus = pricing["opus"] ?? CostCalculator.defaultPricing["opus"]!
        let sonnet = pricing["sonnet"] ?? CostCalculator.defaultPricing["sonnet"]!
        let haiku = pricing["haiku"] ?? CostCalculator.defaultPricing["haiku"]!
        opusInput = "\(opus.inputPer1M)"; opusOutput = "\(opus.outputPer1M)"
        opusCacheRead = "\(opus.cacheReadPer1M)"; opusCacheWrite = "\(opus.cacheWritePer1M)"
        sonnetInput = "\(sonnet.inputPer1M)"; sonnetOutput = "\(sonnet.outputPer1M)"
        sonnetCacheRead = "\(sonnet.cacheReadPer1M)"; sonnetCacheWrite = "\(sonnet.cacheWritePer1M)"
        haikuInput = "\(haiku.inputPer1M)"; haikuOutput = "\(haiku.outputPer1M)"
        haikuCacheRead = "\(haiku.cacheReadPer1M)"; haikuCacheWrite = "\(haiku.cacheWritePer1M)"
    }

    private func loadDefaults() {
        greenThreshold = "100000"; yellowThreshold = "500000"
        claudePath = NSHomeDirectory() + "/.claude"
        let opus = CostCalculator.defaultPricing["opus"]!
        let sonnet = CostCalculator.defaultPricing["sonnet"]!
        let haiku = CostCalculator.defaultPricing["haiku"]!
        opusInput = "\(opus.inputPer1M)"; opusOutput = "\(opus.outputPer1M)"
        opusCacheRead = "\(opus.cacheReadPer1M)"; opusCacheWrite = "\(opus.cacheWritePer1M)"
        sonnetInput = "\(sonnet.inputPer1M)"; sonnetOutput = "\(sonnet.outputPer1M)"
        sonnetCacheRead = "\(sonnet.cacheReadPer1M)"; sonnetCacheWrite = "\(sonnet.cacheWritePer1M)"
        haikuInput = "\(haiku.inputPer1M)"; haikuOutput = "\(haiku.outputPer1M)"
        haikuCacheRead = "\(haiku.cacheReadPer1M)"; haikuCacheWrite = "\(haiku.cacheWritePer1M)"
    }

    private func save() {
        settings.thresholdGreen = Int(greenThreshold) ?? 100_000
        settings.thresholdYellow = Int(yellowThreshold) ?? 500_000
        settings.claudeDataPath = claudePath
        settings.launchAtLogin = launchAtLogin
        settings.customPricing = [
            "opus": PricingTier(inputPer1M: Double(opusInput) ?? 15, outputPer1M: Double(opusOutput) ?? 75, cacheReadPer1M: Double(opusCacheRead) ?? 1.5, cacheWritePer1M: Double(opusCacheWrite) ?? 18.75),
            "sonnet": PricingTier(inputPer1M: Double(sonnetInput) ?? 3, outputPer1M: Double(sonnetOutput) ?? 15, cacheReadPer1M: Double(sonnetCacheRead) ?? 0.3, cacheWritePer1M: Double(sonnetCacheWrite) ?? 3.75),
            "haiku": PricingTier(inputPer1M: Double(haikuInput) ?? 0.8, outputPer1M: Double(haikuOutput) ?? 4, cacheReadPer1M: Double(haikuCacheRead) ?? 0.08, cacheWritePer1M: Double(haikuCacheWrite) ?? 1.0),
        ]
        if #available(macOS 13.0, *) {
            do {
                if launchAtLogin { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {}
        }
    }
}
