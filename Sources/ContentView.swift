import SwiftUI

struct ContentView: View {
    @AppStorage("zepp_account") private var savedAccount = ""
    @State private var account = ""
    @State private var password = ""
    @State private var stepsText = "23800"
    @State private var busy = false
    @State private var box: ResultBox?
    @State private var showGuide = true

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
                loginCard
                if showGuide { guideCard }
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
        .onAppear { if account.isEmpty { account = savedAccount } }
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

            Text("改 Zepp 数据，微信运动自动读")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 2)
    }

    // MARK: - 登录
    private var loginCard: some View {
        card {
            field("Zepp 手机号", text: $account, keyboard: .numberPad, secure: false, placeholder: "11 位手机号")
            field("Zepp 密码", text: $password, keyboard: .default, secure: true, placeholder: "登录密码")

            Divider()

            Link(destination: zeppStoreURL) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("还没有账号？去 App Store 下载 Zepp Life")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.accentColor)
            }

            Text("注册用手机号 + 短信验证码；注册完回这里填手机号密码登录")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 首次引导
    private var guideCard: some View {
        card {
            HStack {
                Text("首次使用 3 步")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("收起") { withAnimation { showGuide = false } }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
            }
            stepRow("1", "下载 Zepp Life 并用手机号注册 / 登录")
            stepRow("2", "微信 → 微信运动 → 设置 → 数据来源 → 添加「Zepp Life」")
            stepRow("3", "回这里点同步，微信运动下拉刷新")
        }
    }

    // MARK: - 步数
    private var stepsCard: some View {
        card {
            Text("目标步数")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("步数", text: $stepsText)
                .keyboardType(.numberPad)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8)],
                      spacing: 8) {
                ForEach(quick, id: \.self) { v in
                    Button {
                        stepsText = v
                    } label: {
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
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 主按钮
    private var primaryButton: some View {
        Button {
            Task { await run() }
        } label: {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(.white) }
                Text(busy ? "提交中…" : "开始同步")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(canSubmit ? Color.accentColor : Color.gray.opacity(0.35))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
    }

    private var canSubmit: Bool {
        !busy && !account.isEmpty && !password.isEmpty
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
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
            Text("账号只存在本机，不上传任何服务器")
            Text("v1.1")
                .foregroundStyle(.tertiary)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.top, 6)
    }

    // MARK: - 组件

    private func field(_ title: String, text: Binding<String>,
                       keyboard: UIKeyboardType, secure: Bool, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                        .keyboardType(keyboard)
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
                .font(.footnote)
                .foregroundStyle(.secondary)
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

    // MARK: - 动作

    private func run() async {
        guard let steps = Int(stepsText), steps >= 1000, steps <= 60000 else {
            box = ResultBox(ok: false, text: "步数填 1000–60000 之间")
            return
        }
        busy = true
        box = nil
        savedAccount = account
        do {
            let raw = try await ZeppClient.shared.push(account: account, password: password, steps: steps)
            let lowered = raw.lowercased()
            if lowered.contains("success") || raw.contains("\"code\":0") || raw.contains("\"code\": 0") {
                box = ResultBox(ok: true,
                                text: "\(steps) 步已提交。\n打开微信运动下拉刷新，等 1–3 分钟。")
            } else {
                box = ResultBox(ok: false, text: "接口返回：\(raw.prefix(220))")
            }
        } catch {
            box = ResultBox(ok: false, text: error.localizedDescription)
        }
        busy = false
    }
}

#Preview { ContentView() }
