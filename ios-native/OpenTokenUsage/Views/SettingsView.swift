import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.refreshInterval) private var refreshInterval = 60
    @AppStorage(SettingsKey.smartAutoReset) private var smartAutoReset = true
    @AppStorage(SettingsKey.haptics) private var haptics = true
    @AppStorage(SettingsKey.apiBaseURL) private var apiBaseURL = AppSettings.defaultBaseURL

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

                Section {
                    TextField("伺服器位址", text: $apiBaseURL)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if apiBaseURL != AppSettings.defaultBaseURL {
                        Button("還原預設位址") { apiBaseURL = AppSettings.defaultBaseURL }
                    }
                } header: {
                    Text("伺服器")
                } footer: {
                    Text("必須是 https 位址；格式不正確時會改用預設位址。")
                }

                Section {
                    LabeledContent("版本", value: Bundle.main.appVersion)
                }
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

private extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}
