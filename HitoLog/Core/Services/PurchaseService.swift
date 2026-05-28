import StoreKit

enum PurchaseError: LocalizedError {
    case productNotFound
    case failedVerification
    case purchasePending

    var errorDescription: String? {
        switch self {
        case .productNotFound:    return "商品情報を取得できませんでした。しばらくしてから再試行してください。"
        case .failedVerification: return "購入の検証に失敗しました。サポートにお問い合わせください。"
        case .purchasePending:    return "購入が承認待ちです。保護者の承認後に本文が読めるようになります。"
        }
    }
}

struct PurchaseResult {
    let transactionID: String
    let productID: String
}

actor PurchaseService {
    static let shared = PurchaseService()
    private var productCache: [String: Product] = [:]
    private init() {}

    func fetchProduct(for price: ArticlePrice) async throws -> Product {
        guard let productID = price.iapProductID else {
            throw PurchaseError.productNotFound
        }
        if let cached = productCache[productID] { return cached }
        let fetched = try await Product.products(for: [productID])
        guard let product = fetched.first else {
            throw PurchaseError.productNotFound
        }
        productCache[productID] = product
        return product
    }

    // Returns nil if user cancelled; throws on error or pending.
    func purchase(price: ArticlePrice) async throws -> PurchaseResult? {
        let product = try await fetchProduct(for: price)
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            return PurchaseResult(
                transactionID: String(transaction.id),
                productID: product.id
            )
        case .userCancelled:
            return nil
        case .pending:
            throw PurchaseError.purchasePending
        @unknown default:
            throw PurchaseError.productNotFound
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw PurchaseError.failedVerification
        case .verified(let value):
            return value
        }
    }
}
