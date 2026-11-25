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
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
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
