import SwiftUI
import UIKit

struct SettingsView: View {
    /// Changes when the 設定 tab is tapped again.
    var scrollToTopToken = 0
    var refreshRelay: () async -> Void = {}
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
    @AppStorage(QuotaAlerts.enabledKey) private var quotaAlerts = false
    @AppStorage(AlertCenter.timingKey) private var alertTiming = "standard"
    @AppStorage(AlertCenter.limitResetKey) private var limitResetAlerts = false
    @AppStorage(AlertCenter.unusedKey) private var unusedReminders = false
    @AppStorage(AlertCenter.weeklyKey) private var weeklySummary = false
    @AppStorage(AlertCenter.quietKey) private var quietHours = false
    @AppStorage(AlertCenter.quietStartKey) private var quietStart = QuietHours.defaultStart
    @AppStorage(AlertCenter.quietEndKey) private var quietEnd = QuietHours.defaultEnd
    @State private var notificationsDenied = false

    var body: some View {
        NavigationStack {
            Form {
                MainPageNavigation()
                // Signing in is what makes the app useful, so it comes first.
                Section {
                    ForEach(DirectProvider.allCases) { provider in
                        if signedIn.contains(provider) {
                            LabeledContent {
                                if provider.isRelayed {
                                    Button("檢查轉送") { signingIn = provider }
                                    Button("停用", role: .destructive) { signingOut = provider }
                                } else {
                                    Button("登出", role: .destructive) { signingOut = provider }
                                }
                            } label: {
                                VendorLabel(id: provider.rawValue, name: provider.name)
                            }
                        } else {
                            LabeledContent {
                                Button(provider.isRelayed ? "Mac 轉送" : "登入") { signingIn = provider }
                            } label: {
                                VendorLabel(id: provider.rawValue, name: provider.name)
                            }
                        }
                    }
                } header: {
                    Text("帳號")
                } footer: {
                    Text("登入在各服務的官方頁面進行。這些登入方式並非官方公開介面，服務更新後可能失效。Google Antigravity 不能在手機登入，改由你的 Mac 讀取用量後經 Worker 轉送。")
                }

                Section {
                    Picker("自動更新", selection: $refreshInterval) {
                        ForEach(AppSettings.intervalOptions) { option in
                            Text(option.title).tag(option.seconds)
                        }
                    }
                } footer: {
                    Text("App 開啟時依此頻率更新。Claude Code 最快每 5 分鐘、Codex 與 Cursor 最快每 1 分鐘查詢一次，避免被服務拒絕。Antigravity 最快每 1 分鐘讀取 Worker，但只有 Mac 轉送後（約每 5 分鐘）數字才會變。")
                }

                Section {
                    Toggle("免費重置通知", isOn: permissionBinding($resetAlerts))
                    Toggle("額度警示通知", isOn: permissionBinding($quotaAlerts))
                    if quotaAlerts {
                        Picker("提醒時機", selection: $alertTiming) {
                            Text("標準（80%、95%）").tag("standard")
                            Text("提早（50%、80%、95%）").tag("early")
                        }
                    }
                    Toggle("用完與重置", isOn: permissionBinding($limitResetAlerts))
                    Toggle("未用完提醒", isOn: permissionBinding($unusedReminders))
                    Toggle("每週摘要", isOn: permissionBinding($weeklySummary))
                } header: {
                    Text("通知")
                } footer: {
                    if notificationsDenied {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("通知已關閉，需要到 iOS「設定」開啟。")
                            Button("開啟設定") {
                                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .font(.footnote.weight(.semibold))
                        }
                    } else {
                        Text("免費重置：Codex 或 Claude Code 出現免費重置時通知你。額度警示：任一週期用到設定的比例，或照目前速度會在重置前用完時通知你。用完與重置：週期用完時通知，用到 80% 以上的週期重置時再通知一次。未用完提醒：每週額度重置前 12 小時仍用不到一半時提醒。每週摘要：週一早上 9 點。每個週期各通知一次；背景檢查的時間由 iOS 決定。")
                    }
                }

                Section {
                    Toggle("勿擾時段", isOn: $quietHours)
                    if quietHours {
                        DatePicker("開始", selection: minutesBinding($quietStart, other: quietEnd),
                                   displayedComponents: .hourAndMinute)
                        DatePicker("結束", selection: minutesBinding($quietEnd, other: quietStart),
                                   displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    Text("這段時間內的額度通知會留到結束時才送出；到時已不正確的（例如週期已重置）就不送。開始與結束不能相同。")
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
                    DisclosureGroup("進階：手動貼上權杖") {
                        Button("從剪貼簿匯入權杖", systemImage: "doc.on.clipboard") { importFromClipboard() }
                        if let importMessage {
                            Text(importMessage).font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(DirectProvider.allCases.filter { !$0.isRelayed }) { provider in
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
                    Text("登入憑證只存在這支手機的鑰匙圈，App 直接向 Claude Code、Codex 與 Cursor 查詢用量，不經過中繼伺服器；只有 Google Antigravity 是讀取你的 Mac 上傳到 Worker 的資料。開啟示範資料時不會連線，顯示的不是你的真實用量。")
                }

                Section {
                    LabeledContent("版本", value: AppSettings.versionText())
                    LabeledContent("更新時間", value: AppSettings.buildTimestampText())
                }

                // TEMPORARY (spec-token-usage-codex-cursor.md §12, P1). Remove before release.
                Section {
                    NavigationLink("Cursor Token 測試（暫時）") { CursorTokenProbeView() }
                }
            }
            .scrollsToTop(on: scrollToTopToken)
            .task {
                notificationsDenied = await ResetAlerts.authorizationDenied()
            }
            // Any notification choice re-plans what is pending from the cached figures.
            .onChange(of: [quotaAlerts, limitResetAlerts, unusedReminders, weeklySummary, quietHours]) {
                Task { await AlertCenter.resync() }
            }
            .onChange(of: [alertTiming, String(quietStart), String(quietEnd)]) {
                Task { await AlertCenter.resync() }
            }
            .onAppear {
                for provider in DirectProvider.allCases { tokens[provider] = Keychain.get(provider.keychainKey) ?? "" }
                reloadSignedIn()
            }
            .sheet(item: $signingIn, onDismiss: reloadSignedIn) { provider in
                if provider.isRelayed {
                    RelaySetupView(onVerified: refreshRelay)
                } else {
                    SignInView(provider: provider)
                }
            }
            .confirmationDialog(
                signingOut?.isRelayed == true ? "停用 \(signingOut?.name ?? "") 轉送？" : "登出 \(signingOut?.name ?? "")？",
                isPresented: Binding(get: { signingOut != nil }, set: { if !$0 { signingOut = nil } }),
                titleVisibility: .visible
            ) {
                Button(signingOut?.isRelayed == true ? "停用" : "登出", role: .destructive) {
                    if let provider = signingOut {
                        CredentialStore.delete(provider)
                        tokens[provider] = ""
                        reloadSignedIn()
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text(signingOut?.isRelayed == true ? "這支手機會停止讀取 Mac 轉送的資料。" : "這支手機會刪除此服務的登入憑證。")
            }
            .navigationTitle("設定")
            .alignedMainPage()
        }
    }
}

private extension SettingsView {
    /// Turning a notification switch on asks for permission first (FR-A2); denied leaves it off.
    func permissionBinding(_ value: Binding<Bool>) -> Binding<Bool> {
        Binding {
            value.wrappedValue
        } set: { on in
            guard on else {
                value.wrappedValue = false
                return
            }
            Task {
                let granted = await ResetAlerts.askNotificationPermission()
                value.wrappedValue = granted
                notificationsDenied = !granted
            }
        }
    }

    /// Minutes after midnight as a time of day. A time equal to the other end is refused, so
    /// quiet hours can never be empty (§6).
    func minutesBinding(_ minutes: Binding<Int>, other: Int) -> Binding<Date> {
        Binding {
            Calendar.current.date(byAdding: .minute, value: minutes.wrappedValue,
                                  to: Calendar.current.startOfDay(for: Date())) ?? Date()
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            let value = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            if value != other { minutes.wrappedValue = value }
        }
    }

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
