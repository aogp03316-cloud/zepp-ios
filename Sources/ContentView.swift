import SwiftUI

struct ContentView: View {
    @ObservedObject private var store = AccountStore.shared
    @AppStorage("last_steps") private var lastSteps = "20000"
    @AppStorage("cooldown_until") private var cooldownUntil: Double = 0

    @State private var stepsText = "20000"
    @State private var busy = false
    @State private var box: ResultBox?
    @State private var now = Date()
    @State private var showAdd = false
    @State private var newAccount = ""
    @State private var newPassword = ""
    @State private var confirmDelete = false

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
                accountSwitcher
                if let cur = store.current {
                    currentCard(cur)
                } else {
                    emptyCard
                }
                stepsCard
                primaryButton
                if let box { resultCard(box) }
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
            if lastSteps.count >= 4 { stepsText = lastSteps }
        }
        .sheet(isPresented: $showAdd) { addSheet }
        .confirmationDialog("删除这个账号？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let cur = store.current { store.remove(cur.id) }
            }
            Button("取消", role: .cancel) {}
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
            Text(store.accounts.isEmpty ? "先添加一个 Zepp 账号" : "共 \(store.accounts.count) 个账号，点卡片切换")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 2)
    }

    // MARK: - 账号切换
    private var accountSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.accounts) { a in
                    Button {
                        store.currentID = a.id
                        box = nil
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(shortName(a.account))
                                .font(.footnote.weight(.medium))
                                .lineLimit(1)
                                .foregroundStyle(store.currentID == a.id ? Color.accentColor : Color.primary)
                            Text(a.lastRunDay.isEmpty ? "未使用" : a.lastRunDay)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .frame(width: 140, alignment: .leading)
                        .background(store.currentID == a.id
                                    ? Color.accentColor.opacity(0.15)
                                    : Color(.secondarySystemGroupedBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(store.currentID == a.id ? Color.accentColor : Color.clear, lineWidth: 1.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                Button { showAdd = true } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "plus").font(.system(size: 16, weight: .semibold))
                        Text("添加").font(.caption2)
                    }
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 60, height: 48)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 2)
        }
    }

    private func shortName(_ s: String) -> String {
        if let at = s.firstIndex(of: "@") {
            let name = String(s[s.startIndex..<at])
            return name.count > 12 ? String(name.suffix(12)) + "@…" : s
        }
        return s
    }

    // MARK: - 当前账号
    private func currentCard(_ cur: Account) -> some View {
        card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("当前账号").font(.caption).foregroundStyle(.secondary)
                    Text(cur.account)
                        .font(.subheadline.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    if !cur.lastResult.isEmpty {
                        Text("上次：\(cur.lastResult)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Button {
                    confirmDelete = true
                } label: {
                    Image(systemName: "trash")
                        .font(.footnote)
                        .foregroundStyle(.red.opacity(0.8))
                        .padding(8)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            Divider()

            Button {
                hideKeyboard()
                Task { await warmUp() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "leaf.fill")
                    Text("新号先打底：写一条 800 步").fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption2)
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(busy || cooldownLeft > 0)

            Link(destination: zeppStoreURL) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("去 App Store 下载 Zepp Life").fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption2)
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.accentColor)
            }
        }
    }

    private var emptyCard: some View {
        card {
            VStack(spacing: 10) {
                Text("还没有账号").font(.subheadline.weight(.medium))
                Text("点上面的「+ 添加」，填 Zepp 的手机号或邮箱 + 密码")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    showAdd = true
                } label: {
                    Text("添加账号")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
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
            Task { await sync() }
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
        !busy && cooldownLeft == 0 && store.current != nil
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
                    Text("微信没变是正常的：① 下拉刷新微信运动 ② 刚开的号次日才统计 ③ 明天看「昨天」")
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

    private var footer: some View {
        VStack(spacing: 4) {
            Text("账号密码存在本机钥匙串，不上传任何服务器")
            Text("v1.4").foregroundStyle(.tertiary)
        }
        .font(.caption2).foregroundStyle(.secondary).padding(.top, 6)
    }

    // MARK: - 添加账号
    private var addSheet: some View {
        NavigationStack {
            Form {
                Section("Zepp 账号") {
                    TextField("手机号 或 注册邮箱", text: $newAccount)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("登录密码", text: $newPassword)
                }
                Section {
                    Button("保存并切换") { saveNew() }
                        .disabled(!isValidAccount(newAccount) || newPassword.isEmpty)
                } footer: {
                    Text("账号密码只存在本机钥匙串，卸载才清除")
                }
            }
            .navigationTitle("添加账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        showAdd = false
                        newAccount = ""
                        newPassword = ""
                    }
                }
            }
        }
    }

    private func saveNew() {
        let a = Account(account: newAccount.trimmingCharacters(in: .whitespacesAndNewlines),
                        password: newPassword)
        store.add(a)
        newAccount = ""
        newPassword = ""
        showAdd = false
    }

    // MARK: - 组件
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

    private static func todayCN() -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return f.string(from: Date())
    }

    private func warmUp() async {
        guard var cur = store.current else { return }
        busy = true
        box = nil
        do {
            let raw = try await ZeppClient.shared.push(account: cur.account, password: cur.password, steps: 800)
            let lowered = raw.lowercased()
            if lowered.contains("success") || raw.contains("\"code\":0") || raw.contains("\"code\": 0") {
                cur.lastRunDay = Self.todayCN()
                cur.lastResult = "打底 800 步"
                store.update(cur)
                box = ResultBox(ok: true,
                                text: "已写入 800 步打底数据。\n现在去 Zepp Life 看看首页有没有步数。")
            } else {
                box = ResultBox(ok: false, text: "打底失败：\(raw.prefix(200))")
            }
        } catch {
            let msg = error.localizedDescription
            if msg.contains("429") {
                cooldownUntil = Date().timeIntervalSince1970 + 900
                box = ResultBox(ok: false, text: "华米限流（429）。15 分钟内别点。")
            } else {
                box = ResultBox(ok: false, text: msg)
            }
        }
        busy = false
    }

    private func sync() async {
        guard var cur = store.current else { return }
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
        lastSteps = stepsText

        do {
            let raw = try await ZeppClient.shared.push(account: cur.account, password: cur.password, steps: steps)
            let lowered = raw.lowercased()
            if lowered.contains("success") || raw.contains("\"code\":0") || raw.contains("\"code\": 0") {
                cur.lastRunDay = Self.todayCN()
                cur.lastResult = "\(steps) 步 ✅"
                store.update(cur)
                box = ResultBox(ok: true, text: "\(steps) 步已写入华米服务器。")
            } else {
                cur.lastResult = "\(steps) 步 · 异常"
                store.update(cur)
                box = ResultBox(ok: false, text: "接口返回：\(raw.prefix(220))")
            }
        } catch {
            let msg = error.localizedDescription
            if msg.contains("429") {
                cooldownUntil = Date().timeIntervalSince1970 + 900
                box = ResultBox(ok: false, text: "华米限流（429）。15 分钟内别点，退出这个页面也算数。")
            } else {
                cooldownUntil = Date().timeIntervalSince1970 + 30
                box = ResultBox(ok: false, text: msg)
            }
        }
        busy = false
    }
}

#Preview { ContentView() }
