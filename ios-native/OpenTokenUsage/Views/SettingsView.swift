import SwiftUI
import UIKit

struct SettingsView: View {
    /// Changes when the 設定 tab is tapped again.
    var scrollToTopToken = 0
    @AppStorage(SettingsKey.refreshInterval) private var refreshInterval = 60
    @AppStorage(SettingsKey.haptics) private var haptics = true
    @AppStorage(SettingsKey.sampleData) private var sampleData = false
    @AppStorage(SettingsKey.catalogSchedule) private var catalogSchedule = ModelCatalog.Schedule.weekly.rawValue
    @State private var tokens: [DirectProvider: String] = [:]
    @State private var importMessage: String?
    @State private var signingIn: DirectProvider?
    @State private var signingOut: DirectProvider?
    @State private var signedIn: Set<DirectProvider> = []
    @AppStorage(ResetAlerts.enabledKey) private var resetAlerts = false
    @State private var notificationsDenied = false

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
                    Toggle("免費重置通知", isOn: Binding(get: { resetAlerts }, set: { on in
                        if on {
                            Task {
                                let granted = await ResetAlerts.requestPermission()
                                notificationsDenied = !granted
                            }
                        } else {
                            resetAlerts = false
                        }
                    }))
                } footer: {
                    if notificationsDenied {
                        Text("通知已關閉，可到 iOS「設定」›「通知」開啟。")
                    } else {
                        Text("Codex 或 Claude Code 出現免費重置時通知你。背景檢查的時間由 iOS 決定。")
                    }
                }

                Section {
                    Toggle("觸覺回饋", isOn: $haptics)
                }

                Section {
                    Picker("模型與價格更新", selection: $catalogSchedule) {
                        ForEach(ModelCatalog.Schedule.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                } footer: {
                    Text("各代理會新增或淘汰模型。App 依此頻率下載最新的模型清單與 API 牌價（LiteLLM 公開價格表），只下載公開資料，不傳送你的任何資訊。")
                }

                Section {
                    ForEach(DirectProvider.allCases) { provider in
                        if signedIn.contains(provider) {
                            LabeledContent(provider.name) {
                                Button("登出", role: .destructive) { signingOut = provider }
                            }
                        } else {
                            LabeledContent(provider.name) {
                                Button("登入") { signingIn = provider }
                            }
                        }
                    }
                    LabeledContent("Google Antigravity") {
                        Text("暫不支援手機登入").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("帳號")
                } footer: {
                    Text("登入在各服務的官方頁面進行。這些登入方式並非官方公開介面，服務更新後可能失效。")
                }

                Section {
                    DisclosureGroup("進階：手動貼上權杖") {
                        Button("從剪貼簿匯入權杖", systemImage: "doc.on.clipboard") { importFromClipboard() }
                        if let importMessage {
                            Text(importMessage).font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(DirectProvider.allCases) { provider in
                            SecureField(provider.tokenTitle, text: tokenBinding(provider))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                } footer: {
                    Text("只有在 App 內登入無法使用時才需要。")
                }

                Section {
                    Toggle("示範資料", isOn: $sampleData)
                } footer: {
                    Text("登入憑證只存在這支手機的鑰匙圈，App 直接向各服務查詢用量，不經過任何中繼伺服器。開啟示範資料時不會連線，顯示的不是你的真實用量。")
                }

                Section {
                    LabeledContent("版本", value: Bundle.main.appVersion)
                }
            }
            .scrollsToTop(on: scrollToTopToken)
            .task {
                notificationsDenied = await ResetAlerts.authorizationDenied()
            }
            .onAppear {
                for provider in DirectProvider.allCases { tokens[provider] = Keychain.get(provider.keychainKey) ?? "" }
                reloadSignedIn()
            }
            .sheet(item: $signingIn, onDismiss: reloadSignedIn) { provider in
                SignInView(provider: provider)
            }
            .confirmationDialog(
                "登出 \(signingOut?.name ?? "")？",
                isPresented: Binding(get: { signingOut != nil }, set: { if !$0 { signingOut = nil } }),
                titleVisibility: .visible
            ) {
                Button("登出", role: .destructive) {
                    if let provider = signingOut {
                        CredentialStore.delete(provider)
                        tokens[provider] = ""
                        reloadSignedIn()
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("這支手機會刪除此服務的登入憑證。")
            }
            .navigationTitle("設定")
        }
    }
}

private extension SettingsView {
    func reloadSignedIn() {
        signedIn = Set(DirectProvider.allCases.filter(\.isSignedIn))
    }

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
        reloadSignedIn()
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
