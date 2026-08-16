import Foundation

public struct OCRInputPage: Equatable, Sendable {
    public var id: String
    public var pageIndex: Int
    public var imageData: Data

    public init(id: String, pageIndex: Int, imageData: Data) {
        self.id = id
        self.pageIndex = pageIndex
        self.imageData = imageData
    }
}

public struct OCRTextPage: Equatable, Sendable {
    public var id: String
    public var pageIndex: Int
    public var text: String
    public var confidence: Double?

    public init(id: String, pageIndex: Int, text: String, confidence: Double? = nil) {
        self.id = id
        self.pageIndex = pageIndex
        self.text = text
        self.confidence = confidence
    }
}

public struct OCRResult: Equatable, Sendable {
    public var pages: [OCRTextPage]
    public var rawText: String
    public var skippedPageIndices: [Int]

    public init(pages: [OCRTextPage], skippedPageIndices: [Int] = []) {
        let orderedPages = pages.sorted { lhs, rhs in
            if lhs.pageIndex == rhs.pageIndex {
                lhs.id < rhs.id
            } else {
                lhs.pageIndex < rhs.pageIndex
            }
        }
        self.pages = orderedPages
        self.rawText = orderedPages.map(\.text).joined(separator: "\n")
        self.skippedPageIndices = skippedPageIndices.sorted()
    }

    public var aggregateConfidence: Double? {
        let confidences = pages.compactMap(\.confidence)
        return confidences.min()
    }
}

public protocol OCRServicing: Sendable {
    func recognizeText(from pages: [OCRInputPage]) async throws -> OCRResult
}

public protocol ExtractionModelServicing: Sendable {
    func extractReceipt(from request: ExtractionModelRequest) async throws -> ModelExtractedReceipt
}

public protocol ModelAvailabilityProviding: Sendable {
    func currentAvailability() async -> ModelAvailabilityStatus
    func supportsLocale(_ locale: Locale) -> Bool
    func supportsImageInput() -> Bool
}

public extension ModelAvailabilityProviding {
    func supportsLocale(_ locale: Locale) -> Bool {
        _ = locale
        return true
    }

    func supportsImageInput() -> Bool {
        false
    }
}

public enum ModelAvailabilityStatus: Equatable, Sendable {
    case available
    case modelNotReady
    case appleIntelligenceNotEnabled
    case deviceNotEligible
    case unknownUnavailable

    public var blocksCapture: Bool {
        switch self {
        case .available, .modelNotReady, .unknownUnavailable:
            false
        case .appleIntelligenceNotEnabled, .deviceNotEligible:
            true
        }
    }
}

public enum OCRServiceError: Error, Equatable, Sendable {
    case configuredFailure(String)
}

public enum ExtractionModelError: Error, Equatable, Sendable {
    case unsupportedLanguageOrLocale(String)
    case timedOut
    case modelUnavailable(ModelAvailabilityStatus)
    case generationFailed(String)
    case contextSizeExceeded
}

public struct ExtractionModelImage: Equatable, Sendable {
    public var pageIndex: Int
    public var imageData: Data
    public var longEdgePixels: Int

    public init(pageIndex: Int, imageData: Data, longEdgePixels: Int) {
        self.pageIndex = pageIndex
        self.imageData = imageData
        self.longEdgePixels = longEdgePixels
    }
}

public struct ExtractionModelRequest: Equatable, Sendable {
    public var rawText: String
    public var localeIdentifier: String
    public var deterministicReceipt: ParsedReceipt?
    public var promptEvidence: ReceiptPromptEvidence?
    public var images: [ExtractionModelImage]
    public var timeoutSeconds: TimeInterval?

    public init(
        rawText: String,
        localeIdentifier: String,
        deterministicReceipt: ParsedReceipt? = nil,
        promptEvidence: ReceiptPromptEvidence? = nil,
        images: [ExtractionModelImage] = [],
        timeoutSeconds: TimeInterval? = nil
    ) {
        self.rawText = rawText
        self.localeIdentifier = localeIdentifier
        self.deterministicReceipt = deterministicReceipt
        self.promptEvidence = promptEvidence
        self.images = images.sorted { $0.pageIndex < $1.pageIndex }
        self.timeoutSeconds = timeoutSeconds
    }
}

public enum ModelOutputAcceptanceTier: String, Equatable, Sendable {
    case evidenceSupported
    case imageGrounded
    case rejected
}

public struct ModelFieldCandidate<Value: Equatable & Sendable>: Equatable, Sendable {
    public var value: Value
    public var reason: String?
    public var acceptanceTier: ModelOutputAcceptanceTier?

    public init(value: Value, reason: String? = nil, acceptanceTier: ModelOutputAcceptanceTier? = nil) {
        self.value = value
        self.reason = reason
        self.acceptanceTier = acceptanceTier
    }
}

public struct ModelField<Value: Equatable & Sendable>: Equatable, Sendable {
    public var primary: ModelFieldCandidate<Value>?
    public var alternate: ModelFieldCandidate<Value>?
    public var isUnknown: Bool

    private init(primary: ModelFieldCandidate<Value>?, alternate: ModelFieldCandidate<Value>?, isUnknown: Bool) {
        self.primary = primary
        self.alternate = alternate
        self.isUnknown = isUnknown
    }

    public static func known(primary value: Value, alternate: ModelFieldCandidate<Value>? = nil) -> Self {
        Self(
            primary: ModelFieldCandidate(value: value),
            alternate: alternate,
            isUnknown: false
        )
    }

    public static func known(
        primary: ModelFieldCandidate<Value>,
        alternate: ModelFieldCandidate<Value>? = nil
    ) -> Self {
        Self(primary: primary, alternate: alternate, isUnknown: false)
    }

    public static func unknown() -> Self {
        Self(primary: nil, alternate: nil, isUnknown: true)
    }
}

public struct ModelExtractedReceipt: Equatable, Sendable {
    public var vendor: ModelField<String>
    public var date: ModelField<Date>
    public var totalAmount: ModelField<Decimal>
    public var currencyCode: ModelField<String>
    public var paymentMethod: ModelField<PaymentMethod>
    public var expenseType: ModelField<ExpenseType>

    public init(
        vendor: ModelField<String> = .unknown(),
        date: ModelField<Date> = .unknown(),
        totalAmount: ModelField<Decimal> = .unknown(),
        currencyCode: ModelField<String> = .unknown(),
        paymentMethod: ModelField<PaymentMethod> = .unknown(),
        expenseType: ModelField<ExpenseType> = .unknown()
    ) {
        self.vendor = vendor
        self.date = date
        self.totalAmount = totalAmount
        self.currencyCode = currencyCode
        self.paymentMethod = paymentMethod
        self.expenseType = expenseType
    }
}

public struct FakeOCRService: OCRServicing {
    private let result: Result<OCRResult, OCRServiceError>

    public init(result: Result<OCRResult, OCRServiceError>) {
        self.result = result
    }

    public func recognizeText(from pages: [OCRInputPage]) async throws -> OCRResult {
        _ = pages
        return try result.get()
    }
}

public struct FakeExtractionModelService: ExtractionModelServicing {
    private let result: Result<ModelExtractedReceipt, ExtractionModelError>

    public init(result: Result<ModelExtractedReceipt, ExtractionModelError>) {
        self.result = result
    }

    public func extractReceipt(from request: ExtractionModelRequest) async throws -> ModelExtractedReceipt {
        _ = request
        return try result.get()
    }
}

public struct FakeModelAvailabilityProvider: ModelAvailabilityProviding {
    private let status: ModelAvailabilityStatus
    private let localeSupport: Bool
    private let imageInputSupport: Bool

    public init(
        status: ModelAvailabilityStatus,
        supportsLocale: Bool = true,
        supportsImageInput: Bool = false
    ) {
        self.status = status
        self.localeSupport = supportsLocale
        self.imageInputSupport = supportsImageInput
    }

    public func currentAvailability() async -> ModelAvailabilityStatus {
        status
    }

    public func supportsLocale(_ locale: Locale) -> Bool {
        _ = locale
        return localeSupport
    }

    public func supportsImageInput() -> Bool {
        imageInputSupport
    }
}
