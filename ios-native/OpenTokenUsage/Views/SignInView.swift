import SafariServices
import SwiftUI
import UIKit

/// The vendor's own page, in the system browser view. The app cannot read what is typed there.
struct BrowserPage: Identifiable {
    let id = UUID()
    let url: URL
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

@MainActor
@Observable
final class SignInModel {
    enum Phase: Equatable {
        case intro
        case working(String)
        case codexCode(String)
        case claudePaste
        case done
        case failed(String)
    }

    let provider: DirectProvider
    var phase: Phase = .intro
    var page: BrowserPage?
    var pastedCode = ""

    private var claudeAttempt: SignInService.ClaudeAttempt?
    private var task: Task<Void, Never>?

    init(provider: DirectProvider) { self.provider = provider }

    func start() {
        task?.cancel()
        switch provider {
        case .claude:
            let attempt = SignInService.claudeBegin()
            claudeAttempt = attempt
            page = BrowserPage(url: attempt.url)
            phase = .claudePaste
        case .codex:
            phase = .working("正在向 OpenAI 取得代碼…")
            task = Task {
                await run {
                    let attempt = try await SignInService.codexBegin()
                    self.phase = .codexCode(attempt.userCode)
                    self.page = BrowserPage(url: attempt.url)
                    return try await SignInService.codexFinish(attempt)
                }
            }
        case .cursor:
            let attempt = SignInService.cursorBegin()
            page = BrowserPage(url: attempt.url)
            phase = .working("等待你在 Cursor 頁面完成登入…")
            task = Task {
                await run { try await SignInService.cursorFinish(attempt) }
            }
        case .antigravity:
            // Settings opens RelaySetupView instead; there is no phone sign-in to start.
            phase = .failed(provider.signInSummary)
        }
    }

    func submitClaudeCode() {
        guard let attempt = claudeAttempt else { return }
        let pasted = pastedCode
        phase = .working("正在確認授權碼…")
        task = Task {
            await run { try await SignInService.claudeFinish(pasted: pasted, attempt: attempt) }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    private func run(_ work: () async throws -> Credential) async {
        do {
            let credential = try await work()
            CredentialStore.save(credential, for: provider)
            page = nil
            phase = .done
        } catch is CancellationError {
            // Closed by the person; nothing is stored.
        } catch {
            page = nil
            phase = .failed((error as? LocalizedError)?.errorDescription ?? "登入失敗，請再試一次。")
        }
    }
}

struct SignInView: View {
    @State private var model: SignInModel
    @Environment(\.dismiss) private var dismiss

    init(provider: DirectProvider) {
        _model = State(initialValue: SignInModel(provider: provider))
    }

    var body: some View {
        NavigationStack {
            Form {
                switch model.phase {
                case .intro:
                    Section {
                        Text(model.provider.signInSummary)
                        Text("App 不會看到你的密碼，只會把登入憑證存在這支手機的鑰匙圈。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Section {
                        Button("繼續") { model.start() }
                    }
                case .working(let message):
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(message)
                        }
                    }
                    reopenSection
                case .codexCode(let code):
                    Section {
                        Text(code)
                            .font(.title.monospaced().weight(.semibold))
                            .textSelection(.enabled)
                            .accessibilityLabel("代碼 \(code)")
                        Button("複製代碼", systemImage: "doc.on.doc") { UIPasteboard.general.string = code }
                    } header: {
                        Text("在 OpenAI 頁面輸入這組代碼")
                    } footer: {
                        Text("完成後這裡會自動繼續，最長等待 15 分鐘。")
                    }
                    reopenSection
                case .claudePaste:
                    Section {
                        TextField("授權碼", text: $model.pastedCode, axis: .vertical)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("貼上", systemImage: "doc.on.clipboard") {
                            model.pastedCode = UIPasteboard.general.string ?? ""
                        }
                    } header: {
                        Text("貼上登入頁顯示的授權碼")
                    }
                    Section {
                        Button("完成登入") { model.submitClaudeCode() }
                            .disabled(model.pastedCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    reopenSection
                case .done:
                    Section {
                        Label("已登入 \(model.provider.name)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.statusGreen)
                    }
                    Section {
                        Button("完成") { dismiss() }
                    }
                case .failed(let message):
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.statusOrange)
                    }
                    Section {
                        Button("再試一次") { model.start() }
                    }
                }
            }
            .navigationTitle("登入 \(model.provider.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.phase == .done ? "關閉" : "取消") {
                        model.cancel()
                        dismiss()
                    }
                }
            }
            .sheet(item: $model.page) { page in
                SafariView(url: page.url).ignoresSafeArea()
            }
        }
        .interactiveDismissDisabled(model.phase != .intro && model.phase != .done)
    }

    @ViewBuilder
    private var reopenSection: some View {
        Section {
            Button("重新開啟登入頁", systemImage: "safari") { model.start() }
        }
    }
}

/// Google Antigravity has no phone sign-in. The person's Mac relays its usage to their Worker
/// (`scripts/relay-antigravity-mac.py`) and the phone reads it from there. This sheet saves the
/// Worker's address once it has answered with a quota list.
struct RelaySetupView: View {
    let onVerified: () async -> Void
    enum Check: Equatable {
        /// Saved; the Mac's latest figures are from this time.
        case relayed(Date)
        /// Saved; the Worker answers but the Mac has not relayed anything yet.
        case waitingForMac
        /// Not saved.
        case failed(String)
    }

    @Environment(\.dismiss) private var dismiss
    @State private var address = Keychain.get(DirectProvider.antigravity.keychainKey) ?? AntigravityRelay.defaultBaseURL
    @State private var checking = false
    @State private var check: Check?
    @State private var refreshKey = ""
    @State private var requesting = false
    @State private var refreshMessage: String?
    @State private var refreshTask: Task<Void, Never>?

    private var saved: Bool {
        switch check {
        case .relayed, .waitingForMac: return true
        default: return false
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Google 不允許在手機登入 Antigravity。改由你的 Mac 讀取用量（透過 CodexBar），每 5 分鐘上傳到你的 Worker，這支手機再從 Worker 讀取。")
                    Text("Mac 關機或睡眠時不會更新；App 會標出資料是什麼時候的。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    TextField("https://…", text: $address)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    // Copied on the Mac, pasted here (Universal Clipboard). Same button as Claude's code.
                    Button("貼上", systemImage: "doc.on.clipboard") {
                        if let text = UIPasteboard.general.string {
                            address = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                } header: {
                    Text("Worker 網址")
                } footer: {
                    Text("在 Mac 執行 scripts/install-antigravity-relay-mac.sh 後，Mac 會上傳到這個網址。")
                }
                Section {
                    Button {
                        Task { await verify() }
                    } label: {
                        if checking {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("正在確認…")
                            }
                        } else {
                            Text("確認並開啟")
                        }
                    }
                    .disabled(checking || AntigravityRelay.normalizedBase(address) == nil)
                }
                if let base = AntigravityRelay.normalizedBase(address), base.hasPrefix("https://") {
                    Section {
                        SecureField("手機更新金鑰", text: $refreshKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button(requesting ? "等待 Mac 回覆…" : "請 Mac 立即更新") {
                            refreshTask = Task { await requestRefresh(base: base) }
                        }
                        .disabled(requesting || checking || refreshKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if let refreshMessage { Text(refreshMessage).font(.footnote) }
                    } footer: {
                        Text("Mac 必須開機、保持連線，並執行轉送程式。")
                    }
                    .task(id: base) {
                        refreshKey = Keychain.get(Self.refreshKeyName(base)) ?? ""
                        refreshMessage = nil
                    }
                }
                if let check {
                    Section { outcome(check) }
                }
            }
            .navigationTitle("Antigravity 轉送")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(saved ? "完成" : "取消") { dismiss() }
                }
            }
        }
        .interactiveDismissDisabled(checking)
        .onDisappear { refreshTask?.cancel() }
    }

    @ViewBuilder
    private func outcome(_ check: Check) -> some View {
        switch check {
        case .relayed(let date):
            Label {
                Text("已開啟。Mac 上次轉送：\(date, style: .relative)前")
            } icon: {
                Image(systemName: "checkmark.circle.fill")
            }
            .foregroundStyle(Color.statusGreen)
        case .waitingForMac:
            Label("已開啟。Worker 可以連線，但 Mac 還沒有轉送 Antigravity 資料。", systemImage: "clock.badge.exclamationmark")
                .foregroundStyle(Color.statusOrange)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.statusOrange)
        }
    }

    private static func refreshKeyName(_ base: String) -> String {
        "opentokenusage.antigravity.refresh:" + base
    }

    private func requestRefresh(base: String) async {
        guard let url = URL(string: base + "/api/antigravity/refresh") else { return }
        requesting = true
        refreshMessage = nil
        defer { requesting = false }
        let key = refreshKey.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
            request.httpMethod = "POST"
            request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request, delegate: NoRefreshRedirect())
            switch (response as? HTTPURLResponse)?.statusCode {
            case 202: break
            case 401:
                refreshMessage = "手機更新金鑰不正確。"
                return
            default:
                refreshMessage = "Worker 尚未啟用立即更新。"
                return
            }

            struct Ticket: Decodable { let requested_at: String }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions.insert(.withFractionalSeconds)
            guard let requested = formatter.date(from: try JSONDecoder().decode(Ticket.self, from: data).requested_at) else {
                refreshMessage = "Worker 回傳的更新時間無法讀取。"
                return
            }
            Keychain.set(key, for: Self.refreshKeyName(base))
            let deadline = ContinuousClock.now + .seconds(75)
            while ContinuousClock.now < deadline {
                try await Task.sleep(for: .seconds(5))
                let (snapshot, _) = try await URLSession.shared.data(for: DirectProvider.antigravity.request(token: base))
                if let date = AntigravityRelay.parse(snapshot)?.fetchedDate, date >= requested {
                    Keychain.set(base, for: DirectProvider.antigravity.keychainKey)
                    check = .relayed(date)
                    refreshMessage = "已收到新的額度資料。"
                    await onVerified()
                    return
                }
            }
            refreshMessage = "尚未收到新資料。請確認 Mac 已開機並能讀取 Antigravity。"
        } catch is CancellationError {
            return
        } catch {
            refreshMessage = "無法連線到 Worker，請檢查網路後重試。"
        }
    }

    private final class NoRefreshRedirect: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    private func verify() async {
        guard let base = AntigravityRelay.normalizedBase(address) else {
            check = .failed("網址需要以 https:// 開頭。")
            return
        }
        checking = true
        defer { checking = false }
        do {
            let (data, response) = try await URLSession.shared.data(for: DirectProvider.antigravity.request(token: base))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                check = .failed("這個網址沒有回應額度資料（\(status)）。請確認網址正確、Worker 已部署。")
                return
            }
            switch AntigravityRelay.read(data) {
            case .quota(let quota):
                Keychain.set(base, for: DirectProvider.antigravity.keychainKey)
                address = base
                check = .relayed(quota.fetchedDate ?? Date())
            case .nothingRelayed:
                Keychain.set(base, for: DirectProvider.antigravity.keychainKey)
                address = base
                check = .waitingForMac
            case .unreadable:
                check = .failed("這個網址不是 OpenTokenUsage 的 Worker。")
            }
        } catch {
            check = .failed("無法連線到這個網址，請檢查網路與網址。")
        }
    }
}
