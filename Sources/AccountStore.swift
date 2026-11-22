import Foundation
import SwiftUI

struct Account: Codable, Identifiable, Equatable {
    var id = UUID()
    var account: String
    var password: String
    var lastRunDay: String = ""
    var lastResult: String = ""
}

final class AccountStore: ObservableObject {
    static let shared = AccountStore()
    private let key = "accounts_v1"

    @Published var accounts: [Account] = []
    @Published var currentID: UUID?

    private init() { load() }

    func load() {
        guard let data = KeychainStore.loadData(key),
              let list = try? JSONDecoder().decode([Account].self, from: data),
              !list.isEmpty else { return }
        accounts = list
        if currentID == nil || !accounts.contains(where: { $0.id == currentID }) {
            currentID = accounts.first?.id
        }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        KeychainStore.saveData(data, for: key)
    }

    func add(_ a: Account) {
        accounts.append(a)
        currentID = a.id
        save()
    }

    func remove(_ id: UUID) {
        accounts.removeAll { $0.id == id }
        if currentID == id { currentID = accounts.first?.id }
        save()
    }

    func update(_ a: Account) {
        guard let i = accounts.firstIndex(where: { $0.id == a.id }) else { return }
        accounts[i] = a
        save()
    }

    var current: Account? {
        guard let id = currentID else { return nil }
        return accounts.first { $0.id == id }
    }
}
