import SwiftUI

struct ContentView: View {
    @State private var account = ""
    @State private var password = ""
    @AppStorage("auto_run") private var autoRun = false
    @AppStorage("last_steps") private var lastSteps = "20000"
    @AppStorage("last_success_at") private var lastSuccessAt = ""
    // 冷却用时间戳（退出 App 也继续算）
    @AppStorage("cooldown_until") private var cooldownUntil: Double = 0

    @State private var stepsText = "20000"
    @State private var busy = false
    @State private var box: ResultBox?
    @State private var now = Date()
    @State private var showGuide = false
    @State private var history: [String] = []

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let quick = ["12000", "20000", "23800", "28800"]
    private let zeppStoreURL = URL(string: "https://apps.apple.com/cn/app/id938688461")!
    private let minSteps = 9000
    private let maxSteps = 60000

    struct ResultBox: Equatable {
        let ok: Bool
        let text: String
    }

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
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { hideKeyboard() }
            }
        }
        .onReceive(timer) { now = $0 }
        .onAppear {
            loadSaved()
            if autoRun, canSubmit { Task { await runOnce() } }
        }
    }

    // MARK: - 顶部
    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.walk.motion")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.65)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text("步数同步").font(.title2.bold())
            Text(lastSuccessAt.isEmpty ? "改 Zepp 数据，微信运动自动读" : "上次成功：\(lastSuccessAt)")
                .font(.footnote).foregroundStyle(.secondary)
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
                .font(.caption).buttonStyle(.plain).foregroundStyle(Color.accentColor)
            }
            field("Zepp 账号", text: $account, keyboard: .emailAddress, secure: false, placeholder: "手机号 或 注册邮箱")
            field("Zepp 密码", text: $password, keyboard: .default, secure: true, placeholder: "登录密码")

            Toggle(isOn: $autoRun) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("打开 App 自动同步").font(.footnote)
                    Text("一天一次就够，刷多了会被华米限流").font(.caption2).foregroundStyle(.secondary)
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
                .font(.footnote.weight(.medium)).foregroundStyle(Color.accentColor)
            }
        }
    }

    private var guideCard: some View {
        card {
            stepRow("1", "装 Zepp Life 登录，绑定一个设备（手环/手表），让它有步数数据")
            stepRow("2", "微信 → 微信运动 → 设置 → 数据来源 → 添加「Zepp Life」")
            stepRow("3", "回这里点同步；微信运动下拉刷新，等 1–3 分钟")
            stepRow("4", "刚开通微信运动的号当天不统计，次日才显示")
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
                .onChange(of: stepsText) { newValue in
                    let digits = newValue.filter { $0.isNumber }
                    if digits != newValue { stepsText = digits }
                    if digits.count > 5 { stepsText = String(digits.prefix(5)) }
                }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(quick, id: \.self) { v in
                    Button { stepsText = v } label: {
                        Text(v)
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(stepsText == v ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemFill))
                            .foregroundStyle(stepsText == v ? Color.accentColor : Color.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("范围 \(minSteps)–\(maxSteps)。低于 9000 微信可能不统计，建议 20000 以上")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 主按钮
    private var primaryButton: some View {
        Button {
            hideKeyboard()
            Task { await runOnce() }
        } label: {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(.white) }
                Text(buttonTitle).font(.headline)
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

    private var cooldownLeft: Int {
        max(0, Int(cooldownUntil - now.timeIntervalSince1970))
    }

    private var buttonTitle: String {
        if busy { return "提交中…" }
        if cooldownLeft > 0 { return "\(cooldownLeft) 秒后可再次同步" }
        return "开始同步"
    }

    private var canSubmit: Bool {
        !busy && cooldownLeft == 0 && isValidAccount(account) && !password.isEmpty
    }

    // MARK: - 结果
    private func resultCard(_ b: ResultBox) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: b.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(b.ok ? .green : .orange)
                .font(.system(size: 18))
            VStack(alignment: .leading, spacing: 6) {
                Text(b.ok ? "华米已收到" : "没成功").font(.subheadline.weight(.semibold))
                Text(b.text).font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if b.ok {
                    Text("微信没变是正常的：① 打开微信运动下拉刷新 ② 刚开的号次日才统计 ③ 明天看「昨天」的数据")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
            Text("v1.3").foregroundStyle(.tertiary)
        }
        .font(.caption2).foregroundStyle(.secondary).padding(.top, 6)
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
            Text(n).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .background(Color(.tertiarySystemFill))
                .clipShape(Circle())
            Text(text).font(.footnote).foregroundStyle(.secondary)
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

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
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
        if lastSteps.count >= 4 { stepsText = lastSteps }
        history = UserDefaults.standard.stringArray(forKey: "history") ?? []
    }

    private func saveHistory(_ line: String) {
        var list = UserDefaults.standard.stringArray(forKey: "history") ?? []
        list.insert(line, at: 0)
        if list.count > 5 { list = Array(list.prefix(5)) }
        UserDefaults.standard.set(list, forKey: "history")
        history = list
    }

    private func runOnce() async {
        guard isValidAccount(account) else {
            box = ResultBox(ok: false, text: "账号填 11 位手机号 或 注册邮箱")
            return
        }
        guard let steps = Int(stepsText) else {
            box = ResultBox(ok: false, text: "步数填数字")
            return
        }
        guard steps >= minSteps, steps <= maxSteps else {
            box = ResultBox(ok: false, text: "步数要在 \(minSteps)–\(maxSteps) 之间")
            return
        }

        busy = true
        box = nil
        KeychainStore.save(account, for: "account")
        KeychainStore.save(password, for: "password")
        lastSteps = stepsText

        do {
            let raw = try await ZeppClient.shared.push(account: account, password: password, steps: steps)
            let lowered = raw.lowercased()
            if lowered.contains("success") || raw.contains("\"code\":0") || raw.contains("\"code\": 0") {
                let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
                lastSuccessAt = "\(ts) \(steps) 步"
                box = ResultBox(ok: true, text: "\(steps) 步已写入华米服务器。")
                saveHistory("✅ \(ts)  \(steps) 步")
            } else {
                box = ResultBox(ok: false, text: "接口返回：\(raw.prefix(220))")
                saveHistory("⚠️ \(steps) 步 · 返回异常")
            }
        } catch {
            let msg = error.localizedDescription
            let rateLimited = msg.contains("429") || msg.lowercased().contains("too many")
            if rateLimited {
                cooldownUntil = Date().timeIntervalSince1970 + 900   // 15 分钟
                box = ResultBox(ok: false, text: "华米限流了（429）。15 分钟内别点，退出这个页面也算数。")
                saveHistory("❌ \(steps) 步 · 429 限流")
            } else {
                cooldownUntil = Date().timeIntervalSince1970 + 30
                box = ResultBox(ok: false, text: msg)
                saveHistory("❌ \(steps) 步 · \(msg.prefix(40))")
            }
        }
        busy = false
    }
}

#Preview { ContentView() }
