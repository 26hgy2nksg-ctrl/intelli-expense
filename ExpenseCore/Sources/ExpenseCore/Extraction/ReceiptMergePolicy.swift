import Foundation

public enum FieldSource: Equatable, Sendable {
    case deterministic
    case model
}

public struct MergedFieldOption<Value: Equatable & Sendable>: Equatable, Sendable {
    public var value: Value
    public var source: FieldSource
    public var confidence: FieldConfidence?
    public var evidence: String?
    public var reason: String?

    public init(
        value: Value,
        source: FieldSource,
        confidence: FieldConfidence? = nil,
        evidence: String? = nil,
        reason: String? = nil
    ) {
        self.value = value
        self.source = source
        self.confidence = confidence
        self.evidence = evidence
        self.reason = reason
    }
}

public struct MergedField<Value: Equatable & Sendable>: Equatable, Sendable {
    public var options: [MergedFieldOption<Value>]

    public init(options: [MergedFieldOption<Value>] = []) {
        self.options = Array(options.prefix(2))
    }

    public var primary: MergedFieldOption<Value>? {
        options.first
    }
}

public struct MergedReceipt: Equatable, Sendable {
    public var vendor: MergedField<String>
    public var date: MergedField<Date>
    public var totalAmount: MergedField<Decimal>
    public var currencyCode: MergedField<String>
    public var paymentMethod: MergedField<PaymentMethod>
    public var expenseType: MergedField<ExpenseType>
    public var rawText: String
    public var requiresManualEntryFallback: Bool

    public init(
        vendor: MergedField<String> = MergedField(),
        date: MergedField<Date> = MergedField(),
        totalAmount: MergedField<Decimal> = MergedField(),
        currencyCode: MergedField<String> = MergedField(),
        paymentMethod: MergedField<PaymentMethod> = MergedField(),
        expenseType: MergedField<ExpenseType> = MergedField(),
        rawText: String,
        requiresManualEntryFallback: Bool = false
    ) {
        self.vendor = vendor
        self.date = date
        self.totalAmount = totalAmount
        self.currencyCode = currencyCode
        self.paymentMethod = paymentMethod
        self.expenseType = expenseType
        self.rawText = rawText
        self.requiresManualEntryFallback = requiresManualEntryFallback
    }
}

public struct ReceiptMergePolicy: Sendable {
    private let ambiguityFallbackThreshold: Int

    public init(ambiguityFallbackThreshold: Int = 3) {
        self.ambiguityFallbackThreshold = ambiguityFallbackThreshold
    }

    public func merge(deterministic: ParsedReceipt, model: ModelExtractedReceipt? = nil) -> MergedReceipt {
        if shouldFallbackToManualEntry(deterministic: deterministic, model: model) {
            return MergedReceipt(rawText: deterministic.rawText, requiresManualEntryFallback: true)
        }

        return MergedReceipt(
            vendor: mergeField(deterministic.vendor, model?.vendor ?? .unknown()),
            date: mergeDateField(deterministic.date, alternates: deterministic.dateAlternates, model?.date ?? .unknown()),
            totalAmount: mergeTotalAmountField(deterministic.totalAmount, model?.totalAmount ?? .unknown()),
            currencyCode: mergeField(deterministic.currencyCode, model?.currencyCode ?? .unknown()),
            paymentMethod: mergeField(deterministic.paymentMethod, model?.paymentMethod ?? .unknown()),
            expenseType: mergeModelOnlyField(model?.expenseType ?? .unknown()),
            rawText: deterministic.rawText
        )
    }

    private func mergeField<Value: Equatable & Sendable>(
        _ deterministic: ParsedField<Value>?,
        _ model: ModelField<Value>
    ) -> MergedField<Value> {
        var options: [MergedFieldOption<Value>] = []

        if let deterministic {
            options.append(
                MergedFieldOption(
                    value: deterministic.value,
                    source: .deterministic,
                    confidence: deterministic.confidence,
                    evidence: deterministic.evidence
                )
            )
        }

        guard model.isUnknown == false else {
            return MergedField(options: options)
        }

        if let primary = model.primary, options.contains(where: { $0.value == primary.value }) == false {
            options.append(modelOption(primary))
        }

        if deterministic == nil,
           let alternate = model.alternate,
           options.contains(where: { $0.value == alternate.value }) == false {
            options.append(modelOption(alternate))
        }

        return MergedField(options: options)
    }

    private func mergeDateField(
        _ deterministic: ParsedField<Date>?,
        alternates: [ParsedField<Date>],
        _ model: ModelField<Date>
    ) -> MergedField<Date> {
        var options: [MergedFieldOption<Date>] = []

        if let deterministic {
            options.append(
                MergedFieldOption(
                    value: deterministic.value,
                    source: .deterministic,
                    confidence: deterministic.confidence,
                    evidence: deterministic.evidence
                )
            )
        }

        for alternate in alternates where options.count < 2 && options.contains(where: { $0.value == alternate.value }) == false {
            options.append(
                MergedFieldOption(
                    value: alternate.value,
                    source: .deterministic,
                    confidence: alternate.confidence,
                    evidence: alternate.evidence
                )
            )
        }

        guard model.isUnknown == false else {
            return MergedField(options: options)
        }

        if let primary = model.primary, options.count < 2, options.contains(where: { $0.value == primary.value }) == false {
            options.append(modelOption(primary))
        }

        if deterministic == nil,
           let alternate = model.alternate,
           options.count < 2,
           options.contains(where: { $0.value == alternate.value }) == false {
            options.append(modelOption(alternate))
        }

        return MergedField(options: options)
    }

    private func mergeTotalAmountField(
        _ deterministic: ParsedField<Decimal>?,
        _ model: ModelField<Decimal>
    ) -> MergedField<Decimal> {
        guard let deterministic,
              deterministic.confidence == .low,
              model.isUnknown == false,
              let modelPrimary = model.primary,
              modelPrimary.acceptanceTier != .imageGrounded else {
            return mergeField(deterministic, model)
        }

        var options = [modelOption(modelPrimary)]
        if modelPrimary.value != deterministic.value {
            options.append(
                MergedFieldOption(
                    value: deterministic.value,
                    source: .deterministic,
                    confidence: deterministic.confidence,
                    evidence: deterministic.evidence
                )
            )
        }

        if options.count < 2,
           let alternate = model.alternate,
           options.contains(where: { $0.value == alternate.value }) == false {
            options.append(modelOption(alternate))
        }

        return MergedField(options: options)
    }

    private func mergeModelOnlyField<Value: Equatable & Sendable>(_ model: ModelField<Value>) -> MergedField<Value> {
        guard model.isUnknown == false else {
            return MergedField()
        }

        var options: [MergedFieldOption<Value>] = []
        if let primary = model.primary {
            options.append(modelOption(primary))
        }
        if let alternate = model.alternate, options.contains(where: { $0.value == alternate.value }) == false {
            options.append(modelOption(alternate))
        }
        return MergedField(options: options)
    }

    private func modelOption<Value: Equatable & Sendable>(_ candidate: ModelFieldCandidate<Value>) -> MergedFieldOption<Value> {
        MergedFieldOption(
            value: candidate.value,
            source: .model,
            confidence: candidate.acceptanceTier == .imageGrounded ? .low : .medium,
            reason: candidate.reason
        )
    }

    private func shouldFallbackToManualEntry(deterministic: ParsedReceipt, model: ModelExtractedReceipt?) -> Bool {
        guard let model else {
            return false
        }

        let deterministicFieldCount = [
            deterministic.vendor != nil,
            deterministic.date != nil,
            deterministic.totalAmount != nil,
            deterministic.currencyCode != nil,
            deterministic.paymentMethod != nil
        ].filter { $0 }.count

        guard deterministicFieldCount == 0 else {
            return false
        }

        let alternateCount = [
            model.vendor.alternate != nil,
            model.date.alternate != nil,
            model.totalAmount.alternate != nil,
            model.currencyCode.alternate != nil,
            model.paymentMethod.alternate != nil,
            model.expenseType.alternate != nil
        ].filter { $0 }.count

        return alternateCount > ambiguityFallbackThreshold
    }
}
