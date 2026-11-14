import Foundation
import StoreKit

/// Покупки платних циферблатів через App Store (StoreKit 2). ID товару — поле price запису в каталозі.
/// Працює лише в BandFace з App Store або TestFlight: у встановленому самостійно застосунку товарів немає,
/// і магазин показує «Платний» замість ціни.
@MainActor
final class StorePurchases: ObservableObject {
    /// Ціна мовою й валютою користувача: «39,99 ₴»
    @Published private(set) var prices: [String: String] = [:]
    /// Куплені товари (з App Store, зокрема на інших пристроях того самого Apple ID)
    @Published private(set) var owned: Set<String> = []
    private var products: [String: Product] = [:]
    private var updates: Task<Void, Never>?

    init() {
        // покупки, завершені поза застосунком (наприклад, «Відкласти покупку» або на іншому пристрої)
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let t) = result {
                    await t.finish()
                    self?.owned.insert(t.productID)
                }
            }
        }
    }

    deinit { updates?.cancel() }

    /// Товари каталогу: ціни й уже куплені
    func load(_ ids: Set<String>) async {
        let missing = ids.subtracting(products.keys)
        if !missing.isEmpty, let list = try? await Product.products(for: missing) {
            for p in list {
                products[p.id] = p
                prices[p.id] = p.displayPrice
            }
        }
        await refreshOwned()
    }

    func refreshOwned() async {
        var set: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.revocationDate == nil { set.insert(t.productID) }
        }
        owned = set
    }

    /// ID транзакції для завантаження файла: наявна покупка або нова. nil — користувач скасував
    func transaction(for productID: String) async throws -> String? {
        if let result = await Transaction.latest(for: productID), case .verified(let t) = result, t.revocationDate == nil {
            return String(t.id)
        }
        guard let product = products[productID] ?? (try? await Product.products(for: [productID]))?.first else {
            throw StoreError(String(localized: "Покупки доступні в BandFace з App Store"))
        }
        products[productID] = product
        switch try await product.purchase() {
        case .success(let result):
            guard case .verified(let t) = result else { throw StoreError(String(localized: "Покупку не підтверджено")) }
            await t.finish()
            owned.insert(productID)
            return String(t.id)
        case .pending:
            throw StoreError(String(localized: "Покупка очікує підтвердження"))
        case .userCancelled:
            return nil
        @unknown default:
            return nil
        }
    }

    /// «Відновити покупки»: синхронізація з App Store
    func restore() async throws {
        try await AppStore.sync()
        await refreshOwned()
    }
}
