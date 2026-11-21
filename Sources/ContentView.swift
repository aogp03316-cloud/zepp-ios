import SwiftUI

struct ContentView: View {
    // 记住的账号（钥匙串）
    @State private var account = ""
    @State private var password = ""
    // 偏好
    @AppStorage("auto_run") private var autoRun = false
    @AppStorage("last_steps") private var lastSteps = "23800"
    @AppStorage("last_success_at") private var lastSuccessAt = ""
    // 状态
    @State private var stepsText = "23800"
    @State private var busy = false
    @State private var box: ResultBox?
    @State private var cooldown = 0
    @State private var retryCountdown = 0
    @State private var showGuide = false
    @State private var history: [String] = []

    struct ResultBox: Equatable {
        let ok: Bool
        let text: String
    }

    private let quick = ["18000", "23800", "28800", "33333"]
    private let zeppStoreURL = URL(string: "https://apps.apple.com/cn/app/id938688461")!

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                accountCard
                if showGuide { guideCard }
                stepsCard
                primaryButton
                if let box { resultCard(box) }
                if !history.isEmpty { historyCard }
                footer
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .dynamicTypeSize(.small ... .xxLarge)
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            loadSaved()
            if autoRun, canSubmit {
                Task { await runOnce() }
            }
        }
    }

    // MARK: - 顶部
    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.walk.motion")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(
                    LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.65)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text("步数同步")
                .font(.title2.bold())

            if lastSuccessAt.isEmpty {
                Text("改 Zepp 数据，微信运动自动读")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("上次成功：\(lastSuccessAt)")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 2)
    }

    // MARK: - 账号
    private var accountCard: some View {
        card {
            HStack {
                Text("账号").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(showGuide ? "收起说明" : "怎么用") {
                    withAnimation { showGuide.toggle() }
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }

            field("Zepp 账号", text: $account, keyboard: .emailAddress, secure: false, placeholder: "手机号 或 注册邮箱")
            field("Zepp 密码", text: $password, keyboard: .default, secure: true, placeholder: "登录密码")

            Toggle(isOn: $autoRun) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("打开 App 自动同步").font(.footnote)
                    Text("每天一次就够，刷多了会被华米限流")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .tint(.accentColor)

            Divider()

            Link(destination: zeppStoreURL) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("还没有账号？去 App Store 下载 Zepp Life")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption2)
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.accentColor)
            }
        }
    }

    private var guideCard: some View {
        card {
            stepRow("1", "装 Zepp Life，用手机号或邮箱登录（顺便验证密码对不对）")
            stepRow("2", "微信 → 微信运动 → 设置 → 数据来源 → 添加「Zepp Life」")
            stepRow("3", "回这里点同步；微信运动下拉刷新，等 1–3 分钟")
            stepRow("4", "一天刷一次就够，频繁点会被华米限流（429）")
        }
    }

    // MARK: - 步数
    private var stepsCard: some View {
        card {
            Text("目标步数").font(.caption).foregroundStyle(.secondary)

            TextField("步数", text: $stepsText)
                .keyboardType(.numberPad)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(quick, id: \.self) { v in
                    Button { stepsText = v } label: {
                        Text(v)
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(stepsText == v ? Color.accentColor.opacity(0.18)
                                                       : Color(.tertiarySystemFill))
                            .foregroundStyle(stepsText == v ? Color.accentColor : Color.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("建议 20000–35000，超过 60000 容易被判异常")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 主按钮
    private var primaryButton: some View {
        Button {
            Task { await runOnce() }
        } label: {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(.white) }
                Text(buttonTitle)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(canSubmit ? Color.accentColor : Color.gray.opacity(0.35))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
    }

    private var buttonTitle: String {
        if busy { return "提交中…" }
        if retryCountdown > 0 { return "\(retryCountdown) 秒后自动重试" }
        if cooldown > 0 { return "\(cooldown) 秒后可再次同步" }
        return "开始同步"
    }

    private var canSubmit: Bool {
        !busy && cooldown == 0 && retryCountdown == 0 && isValidAccount(account) && !password.isEmpty
    }

    // MARK: - 结果
    private func resultCard(_ b: ResultBox) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: b.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(b.ok ? .green : .orange)
                .font(.system(size: 18))
            VStack(alignment: .leading, spacing: 4) {
                Text(b.ok ? "提交成功" : "没成功")
                    .font(.subheadline.weight(.semibold))
                Text(b.text)
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((b.ok ? Color.green : Color.orange).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var historyCard: some View {
        card {
            Text("最近记录").font(.caption).foregroundStyle(.secondary)
            ForEach(history, id: \.self) { line in
                Text(line).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("账号密码存在本机钥匙串，不上传任何服务器")
            Text("v1.2").foregroundStyle(.tertiary)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.top, 6)
    }

    // MARK: - 组件
    private func field(_ title: String, text: Binding<String>,
                       keyboard: UIKeyboardType, secure: Bool, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text).keyboardType(keyboard)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Color(.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func stepRow(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(n)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .background(Color(.tertiarySystemFill))
                .clipShape(Circle())
            Text(text)
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - 逻辑
    private func isValidAccount(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.contains("@") { return t.contains(".") && t.count >= 5 }
        return t.count == 11 && t.allSatisfy { $0.isNumber }
    }

    private func loadSaved() {
        if account.isEmpty { account = KeychainStore.load("account") ?? "" }
        if password.isEmpty { password = KeychainStore.load("password") ?? "" }
        stepsText = lastSteps
        history = UserDefaults.standard.stringArray(forKey: "history") ?? []
    }

    private func saveHistory(_ line: String) {
        var list = UserDefaults.standard.stringArray(forKey: "history") ?? []
        list.insert(line, at: 0)
        if list.count > 5 { list = Array(list.prefix(5)) }
        UserDefaults.standard.set(list, forKey: "history")
        history = list
    }

    private func startCooldown(_ seconds: Int) async {
        cooldown = seconds
        while cooldown > 0 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            cooldown -= 1
        }
    }

    private func runOnce(attempt: Int = 0) async {
        guard isValidAccount(account) else {
            box = ResultBox(ok: false, text: "账号填 11 位手机号 或 注册邮箱")
            return
        }
        guard let steps = Int(stepsText), steps >= 1000, steps <= 60000 else {
            box = ResultBox(ok: false, text: "步数填 1000–60000 之间")
            return
        }

        busy = true
        if attempt == 0 { box = nil }
        KeychainStore.save(account, for: "account")
        KeychainStore.save(password, for: "password")

        do {
            let raw = try await ZeppClient.shared.push(account: account, password: password, steps: steps)
            let lowered = raw.lowercased()
            if lowered.contains("success") || raw.contains("\"code\":0") || raw.contains("\"code\": 0") {
                let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
                lastSuccessAt = "\(ts) \(steps) 步"
                box = ResultBox(ok: true, text: "\(steps) 步已提交。\n打开微信运动下拉刷新，等 1–3 分钟。")
                saveHistory("✅ \(ts)  \(steps) 步")
                busy = false
                await startCooldown(60)
                return
            }
            box = ResultBox(ok: false, text: "接口返回：\(raw.prefix(220))")
            saveHistory("⚠️ \(steps) 步 · 返回异常")
            busy = false
            await startCooldown(30)
        } catch {
            let msg = error.localizedDescription
            let rateLimited = msg.contains("429") || msg.lowercased().contains("too many")
            if rateLimited && attempt < 2 {
                busy = false
                retryCountdown = 60
                while retryCountdown > 0 {
                    box = ResultBox(ok: false, text: "华米限流了（点太频繁）。\n\(retryCountdown) 秒后自动重试…")
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    retryCountdown -= 1
                }
                retryCountdown = 0
                await runOnce(attempt: attempt + 1)
                return
            }
            box = ResultBox(ok: false, text: rateLimited
                            ? "华米限流（429）。停 20 分钟再试，别连续点。"
                            : msg)
            saveHistory("❌ \(steps) 步 · \(msg.prefix(40))")
            busy = false
            await startCooldown(30)
        }
    }
}

#Preview { ContentView() }
