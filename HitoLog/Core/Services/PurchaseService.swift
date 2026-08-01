import FirebaseFunctions
import Foundation
import StoreKit

enum PurchaseError: LocalizedError {
    case productNotFound
    case failedVerification
    case purchasePending
    case invalidServerResponse

    var errorDescription: String? {
        switch self {
        case .productNotFound:    return "商品情報を取得できませんでした。しばらくしてから再試行してください。".localized
        case .failedVerification: return "購入の検証に失敗しました。サポートにお問い合わせください。".localized
        case .purchasePending:    return "購入が承認待ちです。保護者の承認後に本文が読めるようになります。".localized
        case .invalidServerResponse: return "購入情報を確認できませんでした。通信環境を確認して再試行してください。".localized
        }
    }
}

struct PurchaseResult {
    let transactionID: String
    let productID: String
    let expirationDate: Date?
}

actor PurchaseService {
    static let shared = PurchaseService()
    private var productCache: [String: Product] = [:]
    private var transactionUpdatesTask: Task<Void, Never>?
    private init() {}

    func fetchProduct(for price: ArticlePrice) async throws -> Product {
        guard let productID = price.iapProductID else {
            throw PurchaseError.productNotFound
        }
        return try await fetchProduct(productID: productID)
    }

    func fetchProduct(productID: String) async throws -> Product {
        if let cached = productCache[productID] { return cached }
        let fetched = try await Product.products(for: [productID])
        guard let product = fetched.first else {
            throw PurchaseError.productNotFound
        }
        productCache[productID] = product
        return product
    }

    // Returns nil if user cancelled; throws on error or pending.
    func purchase(price: ArticlePrice, articleID: String) async throws -> PurchaseResult? {
        let product = try await fetchProduct(for: price)
        return try await purchase(
            product: product,
            purpose: ["kind": "article", "articleID": articleID]
        )
    }

    func purchase(membershipPlan: CreatorMembershipPlan, creatorID: String) async throws -> PurchaseResult? {
        let product = try await fetchProduct(productID: membershipPlan.productID)
        return try await purchase(
            product: product,
            purpose: ["kind": "membership", "creatorID": creatorID]
        )
    }

    func purchase(
        supportAmount: SupportAmount,
        recipientID: String,
        targetType: String,
        targetID: String?
    ) async throws -> PurchaseResult? {
        let product = try await fetchProduct(productID: supportAmount.productID)
        var purpose: [String: Any] = [
            "kind": "support",
            "recipientID": recipientID,
            "targetType": targetType
        ]
        if let targetID {
            purpose["targetID"] = targetID
        }
        return try await purchase(product: product, purpose: purpose)
    }

    private func purchase(product: Product, purpose: [String: Any]) async throws -> PurchaseResult? {
        let intentID = try await createPurchaseIntent(productID: product.id, purpose: purpose)
        let result = try await product.purchase(options: [.appAccountToken(intentID)])
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            guard transaction.productID == product.id, transaction.appAccountToken == intentID else {
                throw PurchaseError.failedVerification
            }
            try await completePurchase(signedTransaction: verification.jwsRepresentation)
            await transaction.finish()
            return PurchaseResult(
                transactionID: String(transaction.id),
                productID: product.id,
                expirationDate: transaction.expirationDate
            )
        case .userCancelled:
            return nil
        case .pending:
            throw PurchaseError.purchasePending
        @unknown default:
            throw PurchaseError.productNotFound
        }
    }

    func startTransactionListener() {
        guard transactionUpdatesTask == nil else { return }
        transactionUpdatesTask = Task { [weak self] in
            for await verification in Transaction.updates {
                guard let self else { return }
                try? await self.completeAndFinish(verification)
            }
        }
    }

    @discardableResult
    func recoverUnfinishedPurchases() async -> Int {
        var recoveredCount = 0
        for await verification in Transaction.unfinished {
            do {
                try await completeAndFinish(verification)
                recoveredCount += 1
            } catch {
                // StoreKit keeps the transaction unfinished. A later session retries it.
            }
        }
        return recoveredCount
    }

    private func completeAndFinish(_ verification: VerificationResult<Transaction>) async throws {
        let transaction = try checkVerified(verification)
        try await completePurchase(signedTransaction: verification.jwsRepresentation)
        await transaction.finish()
    }

    private func createPurchaseIntent(productID: String, purpose: [String: Any]) async throws -> UUID {
        let response = try await Functions.functions(region: "asia-northeast1")
            .httpsCallable("createPurchaseIntent")
            .call(["productID": productID, "purpose": purpose])
        guard let data = response.data as? [String: Any],
              let rawIntentID = data["intentID"] as? String,
              let intentID = UUID(uuidString: rawIntentID) else {
            throw PurchaseError.invalidServerResponse
        }
        return intentID
    }

    private func completePurchase(signedTransaction: String) async throws {
        _ = try await Functions.functions(region: "asia-northeast1")
            .httpsCallable("completePurchase")
            .call(["signedTransaction": signedTransaction])
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
