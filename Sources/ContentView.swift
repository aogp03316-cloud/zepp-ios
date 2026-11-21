import SwiftUI

struct ContentView: View {
    @AppStorage("zepp_account") private var savedAccount = ""
    @State private var account = ""
    @State private var password = ""
    @State private var stepsText = "23800"
    @State private var busy = false
    @State private var box: ResultBox?

    struct ResultBox: Equatable {
        let ok: Bool
        let text: String
    }

    private let quick = ["18000", "23800", "28800", "33333"]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                card {
                    field("Zepp 手机号", text: $account, keyboard: .numberPad, secure: false, placeholder: "11 位手机号")
                    field("Zepp 密码", text: $password, keyboard: .default, secure: true, placeholder: "登录密码")
                }
                card { stepsBlock }
                primaryButton
                if let box { resultCard(box) }
                card { tips }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .dynamicTypeSize(.small ... .xxLarge)
        .scrollDismissesKeyboard(.interactively)
        .onAppear { if account.isEmpty { account = savedAccount } }
    }

    // MARK: - 区块

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("步数同步")
                .font(.largeTitle.bold())
            Text("改 Zepp 数据 → 微信运动自动读")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 2)
    }

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

    private var stepsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
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
            .background(canSubmit ? Color.accentColor : Color.gray.opacity(0.4))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
    }

    private var canSubmit: Bool {
        !busy && !account.isEmpty && !password.isEmpty
    }

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

    private var tips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("怎么用")
                .font(.caption)
                .foregroundStyle(.secondary)
            tipRow("1", "微信 → 微信运动 → 设置 → 数据来源 → 添加「Zepp Life」")
            tipRow("2", "这里点开始同步，回微信运动下拉刷新，等 1–3 分钟")
            tipRow("3", "微信读的是 Zepp 的数据，不需要健康权限")
        }
    }

    private func tipRow(_ n: String, _ text: String) -> some View {
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
                                text: "\(steps) 步已提交。\n打开微信运动下拉刷新，等 1–3 分钟。\n返回：\(raw.prefix(120))")
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
