import SwiftUI
import MaitricsCore
import ServiceManagement

struct SettingsView: View {
    let settings: AppSettings
    @State private var greenThreshold: String = ""
    @State private var yellowThreshold: String = ""
    @State private var claudePath: String = ""
    @State private var launchAtLogin: Bool = false

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
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                GroupBox(label: Label("Icon Thresholds", systemImage: "gauge.with.dots.needle.33percent")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Token count thresholds for the menu bar icon color.")
                            .font(.caption).foregroundColor(.secondary)
                        HStack {
                            Circle().fill(.green).frame(width: 8, height: 8)
                            Text("Green below:")
                            TextField("100000", text: $greenThreshold)
                                .textFieldStyle(.roundedBorder).frame(width: 120)
                            Text("tokens").foregroundColor(.secondary)
                        }
                        HStack {
                            Circle().fill(.yellow).frame(width: 8, height: 8)
                            Text("Yellow below:")
                            TextField("500000", text: $yellowThreshold)
                                .textFieldStyle(.roundedBorder).frame(width: 120)
                            Text("tokens").foregroundColor(.secondary)
                        }
                        HStack {
                            Circle().fill(.red).frame(width: 8, height: 8)
                            Text("Red above yellow threshold").foregroundColor(.secondary)
                        }
                    }.padding(8)
                }

                GroupBox(label: Label("Model Pricing", systemImage: "dollarsign.circle")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Cost per 1M tokens (USD). Used for estimated costs.")
                            .font(.caption).foregroundColor(.secondary)
                        PricingRow(model: "Opus", input: $opusInput, output: $opusOutput, cacheRead: $opusCacheRead, cacheWrite: $opusCacheWrite)
                        PricingRow(model: "Sonnet", input: $sonnetInput, output: $sonnetOutput, cacheRead: $sonnetCacheRead, cacheWrite: $sonnetCacheWrite)
                        PricingRow(model: "Haiku", input: $haikuInput, output: $haikuOutput, cacheRead: $haikuCacheRead, cacheWrite: $haikuCacheWrite)
                    }.padding(8)
                }

                GroupBox(label: Label("General", systemImage: "gearshape")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Launch at login", isOn: $launchAtLogin)
                        HStack {
                            Text("Claude data path:")
                            TextField("~/.claude", text: $claudePath)
                                .textFieldStyle(.roundedBorder)
                        }
                    }.padding(8)
                }

                HStack {
                    Spacer()
                    Button("Reset to Defaults") { loadDefaults() }
                    Button("Save") { save() }.buttonStyle(.borderedProminent)
                }
            }.padding(20)
        }
        .frame(width: 450, height: 500)
        .onAppear { loadCurrent() }
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
            } catch { /* silently fail */ }
        }
    }
}

struct PricingRow: View {
    let model: String
    @Binding var input: String
    @Binding var output: String
    @Binding var cacheRead: String
    @Binding var cacheWrite: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model).font(.system(size: 12, weight: .semibold))
            HStack(spacing: 8) {
                PricingField(label: "Input", value: $input)
                PricingField(label: "Output", value: $output)
                PricingField(label: "Cache R", value: $cacheRead)
                PricingField(label: "Cache W", value: $cacheWrite)
            }
        }
    }
}

struct PricingField: View {
    let label: String
    @Binding var value: String
    var body: some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 8)).foregroundColor(.secondary)
            TextField("0", text: $value)
                .textFieldStyle(.roundedBorder).frame(width: 70).font(.system(size: 11))
        }
    }
}
