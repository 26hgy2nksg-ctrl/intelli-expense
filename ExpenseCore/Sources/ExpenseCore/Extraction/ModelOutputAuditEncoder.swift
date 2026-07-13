import Foundation

public struct ModelOutputAuditContext: Equatable, Sendable {
    public var imageInputUsed: Bool
    public var attachmentCount: Int
    public var attachmentLongEdges: [Int]
    public var attemptCount: Int
    public var acceptance: ModelOutputAcceptance

    public init(
        imageInputUsed: Bool,
        attachmentCount: Int,
        attachmentLongEdges: [Int] = [],
        attemptCount: Int,
        acceptance: ModelOutputAcceptance
    ) {
        self.imageInputUsed = imageInputUsed
        self.attachmentCount = attachmentCount
        self.attachmentLongEdges = attachmentLongEdges
        self.attemptCount = attemptCount
        self.acceptance = acceptance
    }
}

public enum ModelOutputAuditEncoder {
    public static func json(for receipt: ModelExtractedReceipt) throws -> String {
        try json(
            for: receipt,
            context: ModelOutputAuditContext(
                imageInputUsed: false,
                attachmentCount: 0,
                attemptCount: 1,
                acceptance: ModelOutputAcceptance()
            )
        )
    }

    public static func json(for receipt: ModelExtractedReceipt, context: ModelOutputAuditContext) throws -> String {
        let object: [String: Any] = [
            "version": 2,
            "imageInputUsed": context.imageInputUsed,
            "attachmentCount": context.attachmentCount,
            "attachmentLongEdges": context.attachmentLongEdges,
            "attemptCount": context.attemptCount,
            "acceptance": acceptanceObject(context.acceptance),
            "rawOutput": rawOutputObject(receipt)
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private static func rawOutputObject(_ receipt: ModelExtractedReceipt) -> [String: Any] {
        [
            "vendor": stringField(receipt.vendor),
            "date": dateField(receipt.date),
            "totalAmount": decimalField(receipt.totalAmount),
            "currencyCode": stringField(receipt.currencyCode),
            "paymentMethod": paymentMethodField(receipt.paymentMethod),
            "expenseType": expenseTypeField(receipt.expenseType)
        ]
    }

    private static func acceptanceObject(_ acceptance: ModelOutputAcceptance) -> [String: Any] {
        [
            "vendor": candidateAcceptanceObject(acceptance.vendor),
            "date": candidateAcceptanceObject(acceptance.date),
            "totalAmount": candidateAcceptanceObject(acceptance.totalAmount),
            "currencyCode": candidateAcceptanceObject(acceptance.currencyCode),
            "paymentMethod": candidateAcceptanceObject(acceptance.paymentMethod),
            "expenseType": candidateAcceptanceObject(acceptance.expenseType)
        ]
    }

    private static func candidateAcceptanceObject(_ acceptance: ModelCandidateAcceptance) -> [String: Any] {
        [
            "primary": acceptance.primary?.rawValue ?? NSNull(),
            "alternate": acceptance.alternate?.rawValue ?? NSNull()
        ]
    }

    private static func stringField(_ field: ModelField<String>) -> [String: Any] {
        fieldObject(
            primary: field.primary.map { candidate(value: $0.value, reason: $0.reason) },
            alternate: field.alternate.map { candidate(value: $0.value, reason: $0.reason) },
            isUnknown: field.isUnknown
        )
    }

    private static func dateField(_ field: ModelField<Date>) -> [String: Any] {
        fieldObject(
            primary: field.primary.map { candidate(value: iso8601String($0.value), reason: $0.reason) },
            alternate: field.alternate.map { candidate(value: iso8601String($0.value), reason: $0.reason) },
            isUnknown: field.isUnknown
        )
    }

    private static func decimalField(_ field: ModelField<Decimal>) -> [String: Any] {
        fieldObject(
            primary: field.primary.map { candidate(value: decimalString($0.value), reason: $0.reason) },
            alternate: field.alternate.map { candidate(value: decimalString($0.value), reason: $0.reason) },
            isUnknown: field.isUnknown
        )
    }

    private static func paymentMethodField(_ field: ModelField<PaymentMethod>) -> [String: Any] {
        fieldObject(
            primary: field.primary.map { candidate(value: $0.value.rawValue, reason: $0.reason) },
            alternate: field.alternate.map { candidate(value: $0.value.rawValue, reason: $0.reason) },
            isUnknown: field.isUnknown
        )
    }

    private static func expenseTypeField(_ field: ModelField<ExpenseType>) -> [String: Any] {
        fieldObject(
            primary: field.primary.map { candidate(value: $0.value.rawValue, reason: $0.reason) },
            alternate: field.alternate.map { candidate(value: $0.value.rawValue, reason: $0.reason) },
            isUnknown: field.isUnknown
        )
    }

    private static func fieldObject(primary: [String: Any]?, alternate: [String: Any]?, isUnknown: Bool) -> [String: Any] {
        [
            "primary": primary ?? NSNull(),
            "alternate": alternate ?? NSNull(),
            "isUnknown": isUnknown
        ]
    }

    private static func candidate(value: String, reason: String?) -> [String: Any] {
        [
            "value": value,
            "reason": reason ?? NSNull()
        ]
    }

    private static func decimalString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    private static func iso8601String(_ value: Date) -> String {
        ISO8601DateFormatter().string(from: value)
    }
}
