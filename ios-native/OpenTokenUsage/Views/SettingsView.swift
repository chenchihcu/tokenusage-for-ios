import SwiftUI
import UIKit

struct SettingsView: View {
    /// Changes when the 設定 tab is tapped again.
    var scrollToTopToken = 0
    var refreshRelay: () async -> Void = {}
    @AppStorage(SettingsKey.refreshInterval) private var refreshInterval = 60
    @AppStorage(SettingsKey.haptics) private var haptics = true
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
    @State private var layer: Layer?
    @State private var account: DirectProvider?

    private enum Layer: String, Identifiable {
        case refresh, notices, quiet, version
        var id: String { rawValue }
        var title: String {
            switch self {
            case .refresh: return "更新"
            case .notices: return "通知"
            case .quiet: return "勿擾"
            case .version: return "版本"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let account {
                    Form {
                        Section {
                            Button(account.isRelayed ? "停用" : "登出", role: .destructive) {
                                signingOut = account
                            }
                            if account.isRelayed {
                                Button("檢查轉送") { signingIn = account }
                            }
                        }
                    }
                    .navigationTitle(account.name)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("設定") { self.account = nil }
                        }
                    }
                } else if let layer {
                    Form { layerForm(layer) }
                        .navigationTitle(layer.title)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("設定") { self.layer = nil }
                            }
                        }
                } else {
                    iconHome
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
                AccountAccess(provider: provider, onVerified: refreshRelay)
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
                        account = nil
                        reloadSignedIn()
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text(signingOut?.isRelayed == true ? "這支手機會停止讀取 Mac 轉送的資料。" : "這支手機會刪除此服務的登入憑證。")
            }
            .onChange(of: scrollToTopToken) {
                layer = nil
                account = nil
            }
        }
    }

    private var iconHome: some View {
        List {
            Section {
                HStack {
                    ForEach(DirectProvider.allCases) { provider in
                        Button {
                            if signedIn.contains(provider) {
                                account = provider
                            } else {
                                signingIn = provider
                            }
                        } label: {
                            ProviderBadge(id: provider.rawValue, name: provider.name, base: 36)
                                .opacity(signedIn.contains(provider) ? 1 : 0.35)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(signedIn.contains(provider)
                            ? "\(provider.name)，帳號"
                            : "\(provider.name)，登入")
                        Spacer(minLength: 0)
                    }
                }
            }
            Section {
                HStack {
                    layerButton("更新", systemImage: "arrow.clockwise", layer: .refresh)
                    Spacer(minLength: 0)
                    layerButton("通知", systemImage: "bell", layer: .notices)
                    Spacer(minLength: 0)
                    layerButton("勿擾", systemImage: "moon", layer: .quiet)
                    Spacer(minLength: 0)
                    layerButton("版本", systemImage: "number", layer: .version)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("設定")
    }

    private func layerButton(_ title: String, systemImage: String, layer: Layer) -> some View {
        Button {
            self.layer = layer
        } label: {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title2)
                Text(title)
                    .font(.caption)
            }
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func layerForm(_ layer: Layer) -> some View {
        switch layer {
        case .refresh:
            Section {
                Picker("自動更新", selection: $refreshInterval) {
                    ForEach(AppSettings.intervalOptions) { option in
                        Text(option.title).tag(option.seconds)
                    }
                }
                Toggle("觸覺回饋", isOn: $haptics)
                Picker("模型與價格更新", selection: $catalogSchedule) {
                    ForEach(ModelCatalog.Schedule.allCases) { Text($0.title).tag($0.rawValue) }
                }
            }
            Section {
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
        case .notices:
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
                if notificationsDenied {
                    Button("開啟設定") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
        case .quiet:
            Section {
                Toggle("勿擾時段", isOn: $quietHours)
                DatePicker("開始", selection: minutesBinding($quietStart, other: quietEnd),
                           displayedComponents: .hourAndMinute)
                DatePicker("結束", selection: minutesBinding($quietEnd, other: quietStart),
                           displayedComponents: .hourAndMinute)
            }
        case .version:
            Section {
                LabeledContent("版本", value: AppSettings.versionText())
                LabeledContent("更新時間", value: AppSettings.buildTimestampText())
            }
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
