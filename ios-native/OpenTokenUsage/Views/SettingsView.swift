import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.refreshInterval) private var refreshInterval = 60
    @AppStorage(SettingsKey.smartAutoReset) private var smartAutoReset = true
    @AppStorage(SettingsKey.haptics) private var haptics = true
    @AppStorage(SettingsKey.sampleData) private var sampleData = false
    @State private var tokens: [DirectProvider: String] = [:]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("自動更新", selection: $refreshInterval) {
                        ForEach(AppSettings.intervalOptions) { option in
                            Text(option.title).tag(option.seconds)
                        }
                    }
                } footer: {
                    Text("只在 App 開啟時更新，不會在背景使用網路。")
                }

                Section {
                    Toggle("重置時間到了就顯示為已補滿", isOn: $smartAutoReset)
                    Toggle("觸覺回饋", isOn: $haptics)
                }

                ForEach(DirectProvider.allCases) { provider in
                    Section {
                        SecureField(provider.tokenTitle, text: tokenBinding(provider))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } header: {
                        Text(provider.name)
                    } footer: {
                        Text(provider.tokenHelp)
                    }
                }

                Section {
                    Toggle("示範資料", isOn: $sampleData)
                } footer: {
                    Text("權杖只存在這支手機的鑰匙圈，App 直接向各平台查詢用量，不經過任何中繼伺服器。開啟示範資料時不會連線。")
                }

                Section {
                    LabeledContent("版本", value: Bundle.main.appVersion)
                }
            }
            .onAppear {
                for provider in DirectProvider.allCases { tokens[provider] = provider.token ?? "" }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

private extension SettingsView {
    /// Saves to the Keychain as the person types or pastes.
    func tokenBinding(_ provider: DirectProvider) -> Binding<String> {
        Binding {
            tokens[provider] ?? ""
        } set: { value in
            tokens[provider] = value
            Keychain.set(value, for: provider.keychainKey)
        }
    }
}

private extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}
