import SwiftUI

struct ContentView: View {
    @AppStorage("zepp_account") private var savedAccount = ""
    @State private var account = ""
    @State private var password = ""
    @State private var stepsText = "23800"
    @State private var busy = false
    @State private var result = ""
    @State private var ok = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Zepp 账号") {
                    TextField("手机号（11 位）", text: $account)
                        .keyboardType(.numberPad)
                        .textContentType(.username)
                    SecureField("密码", text: $password)
                        .textContentType(.password)
                }

                Section("目标步数") {
                    TextField("步数", text: $stepsText)
                        .keyboardType(.numberPad)
                    HStack(spacing: 8) {
                        ForEach([18000, 23800, 28800, 33333], id: \.self) { v in
                            Button("\(v)") { stepsText = String(v) }
                                .buttonStyle(.bordered)
                                .font(.footnote)
                        }
                    }
                }

                Section {
                    Button {
                        Task { await run() }
                    } label: {
                        HStack {
                            Spacer()
                            Text(busy ? "提交中…" : "开始同步").bold()
                            Spacer()
                        }
                    }
                    .disabled(busy || account.isEmpty || password.isEmpty)
                }

                if !result.isEmpty {
                    Section("结果") {
                        Text(result)
                            .font(.footnote)
                            .foregroundStyle(ok ? .green : .red)
                    }
                }

                Section("说明") {
                    Text("① 微信 → 微信运动 → 设置 → 数据来源 → 添加「Zepp Life」")
                        .font(.footnote)
                    Text("② 回到这里点同步，然后打开微信运动下拉刷新，等 1–3 分钟")
                        .font(.footnote)
                    Text("③ 微信运动走的是 Zepp 的数据，不是手机健康，所以本 App 不需要健康权限")
                        .font(.footnote)
                    Text("建议 20000–35000，超过 60000 容易异常")
                        .font(.footnote)
                }
            }
            .navigationTitle("步数同步")
            .onAppear { if account.isEmpty { account = savedAccount } }
        }
    }

    private func run() async {
        guard let steps = Int(stepsText), steps >= 1000, steps <= 60000 else {
            result = "步数填 1000–60000 之间"
            ok = false
            return
        }
        busy = true
        result = ""
        savedAccount = account
        do {
            let raw = try await ZeppClient.shared.push(account: account, password: password, steps: steps)
            if raw.lowercased().contains("success") || raw.contains("\"code\":0") || raw.contains("\"code\": 0") {
                ok = true
                result = "✅ 提交成功：\(steps) 步\n微信运动下拉刷新，等 1–3 分钟\n\n接口返回：\(raw.prefix(200))"
            } else {
                ok = false
                result = "⚠️ 返回不像成功：\(raw.prefix(300))"
            }
        } catch {
            ok = false
            result = "❌ \(error.localizedDescription)"
        }
        busy = false
    }
}

#Preview { ContentView() }
