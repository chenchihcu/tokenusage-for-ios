import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.refreshInterval) private var refreshInterval = 60
    @AppStorage(SettingsKey.leftHanded) private var leftHanded = false
    @AppStorage(SettingsKey.haptics) private var haptics = true
    @AppStorage(SettingsKey.sampleData) private var sampleData = false
    @State private var tokens: [DirectProvider: String] = [:]
    @State private var importMessage: String?

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
                    Text("App 開啟時依此頻率更新。Claude Code 最快每 5 分鐘、Codex 與 Cursor 最快每 1 分鐘查詢一次，避免被服務拒絕。")
                }

                Section {
                    Picker("慣用手", selection: $leftHanded) {
                        Text("右手").tag(false)
                        Text("左手").tag(true)
                    }
                    Toggle("觸覺回饋", isOn: $haptics)
                }

                Section {
                    Button("從剪貼簿匯入權杖", systemImage: "doc.on.clipboard") { importFromClipboard() }
                } footer: {
                    Text(importMessage ?? "在電腦上複製整份權杖文字，再按這裡一次存好全部。")
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
    func importFromClipboard() {
        let found = TokenImport.parse(UIPasteboard.general.string ?? "")
        guard !found.isEmpty else {
            importMessage = "剪貼簿裡沒有找到權杖。"
            return
        }
        for (provider, value) in found {
            Keychain.set(value, for: provider.keychainKey)
            tokens[provider] = value
        }
        UIPasteboard.general.string = ""
        let names = DirectProvider.allCases.filter { found[$0] != nil }.map(\.name)
        importMessage = "已匯入：\(names.joined(separator: "、"))。剪貼簿已清空。"
    }

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
