import Foundation

public enum ReceiptLanguage: String, CaseIterable, Sendable {
    case english
    case german
    case french
    case japanese
    case hindi
}

public struct ReceiptLanguageProfile: Equatable, Sendable {
    public var language: ReceiptLanguage
    public var totalLabels: [String]
    public var subtotalLabels: [String]
    public var taxLabels: [String]
    public var cashHints: [String]
    public var cardHints: [String]
    public var dateFormats: [String]
    public var currencySymbols: [String: String]
    public var currencyCodes: [String]
    public var vendorSkipKeywords: [String]
    public var metadataKeywords: [String]

    public init(
        language: ReceiptLanguage,
        totalLabels: [String],
        subtotalLabels: [String],
        taxLabels: [String],
        cashHints: [String],
        cardHints: [String],
        dateFormats: [String],
        currencySymbols: [String: String],
        currencyCodes: [String],
        vendorSkipKeywords: [String],
        metadataKeywords: [String]
    ) {
        self.language = language
        self.totalLabels = totalLabels.map(Self.normalize)
        self.subtotalLabels = subtotalLabels.map(Self.normalize)
        self.taxLabels = taxLabels.map(Self.normalize)
        self.cashHints = cashHints.map(Self.normalize)
        self.cardHints = cardHints.map(Self.normalize)
        self.dateFormats = dateFormats
        self.currencySymbols = currencySymbols
        self.currencyCodes = currencyCodes.map { $0.uppercased() }
        self.vendorSkipKeywords = vendorSkipKeywords.map(Self.normalize)
        self.metadataKeywords = metadataKeywords.map(Self.normalize)
    }

    static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
    }
}

public enum ReceiptLanguageProfiles {
    public static let all: [ReceiptLanguageProfile] = [
        ReceiptLanguageProfile(
            language: .english,
            totalLabels: ["grand total", "amount due", "balance due", "total"],
            subtotalLabels: ["sub total", "subtotal"],
            taxLabels: ["tax", "vat", "gst", "cgst", "sgst"],
            cashHints: ["cash", "paid cash"],
            cardHints: ["card", "visa", "mastercard", "amex", "credit", "debit", "****"],
            dateFormats: ["yyyy-MM-dd", "MM/dd/yyyy", "M/d/yyyy", "dd/MM/yyyy", "d/M/yyyy", "MMM d, yyyy", "MMMM d, yyyy"],
            currencySymbols: ["$": "USD", "€": "EUR", "₹": "INR", "£": "GBP", "¥": "JPY"],
            currencyCodes: ["USD", "EUR", "INR", "GBP", "JPY", "CHF", "CAD", "AUD"],
            vendorSkipKeywords: ["date", "bill", "receipt", "ticket", "gstin"],
            metadataKeywords: [
                "bill", "receipt", "ticket", "invoice", "inv no", "inv#", "fssai", "gst no", "gstin",
                "tax id", "vat no", "tin", "phone", "tel", "order", "terminal", "auth", "transaction",
                "txn", "rrn", "reference", "ref no", "card no", "staff", "cashier", "table", "token"
            ]
        ),
        ReceiptLanguageProfile(
            language: .german,
            totalLabels: ["summe", "gesamtbetrag", "zu zahlen"],
            subtotalLabels: ["zwischensumme"],
            taxLabels: ["mwst", "ust"],
            cashHints: ["bar", "zahlung bar"],
            cardHints: ["karte", "visa", "mastercard", "ec-karte"],
            dateFormats: ["dd.MM.yyyy", "d.M.yyyy", "dd/MM/yyyy", "d/M/yyyy"],
            currencySymbols: ["€": "EUR", "CHF": "CHF"],
            currencyCodes: ["EUR", "CHF"],
            vendorSkipKeywords: ["datum", "beleg", "rechnung", "ticket"],
            metadataKeywords: ["rechnung", "beleg", "bon", "ust", "mwst", "terminal", "transaktion", "kasse", "kassierer"]
        ),
        ReceiptLanguageProfile(
            language: .french,
            totalLabels: ["total ttc", "montant du", "total"],
            subtotalLabels: ["sous-total", "sous total"],
            taxLabels: ["tva"],
            cashHints: ["especes", "espèces", "liquide"],
            cardHints: ["carte", "cb", "visa", "mastercard"],
            dateFormats: ["dd/MM/yyyy", "d/M/yyyy"],
            currencySymbols: ["€": "EUR"],
            currencyCodes: ["EUR", "CHF", "CAD"],
            vendorSkipKeywords: ["date", "ticket", "recu", "reçu", "facture"],
            metadataKeywords: ["ticket", "facture", "tva", "telephone", "téléphone", "commande", "caisse", "caissier", "table"]
        ),
        ReceiptLanguageProfile(
            language: .japanese,
            totalLabels: ["合計", "総合計"],
            subtotalLabels: ["小計"],
            taxLabels: ["消費税"],
            cashHints: ["現金"],
            cardHints: ["カード", "visa", "mastercard"],
            dateFormats: ["yyyy/MM/dd", "yyyy年M月d日"],
            currencySymbols: ["¥": "JPY"],
            currencyCodes: ["JPY"],
            vendorSkipKeywords: ["日付", "領収書", "レシート"],
            metadataKeywords: ["領収書", "レシート", "消費税", "電話", "注文", "端末", "取引"]
        ),
        ReceiptLanguageProfile(
            language: .hindi,
            totalLabels: ["कुल", "योग"],
            subtotalLabels: ["उप योग"],
            taxLabels: ["कर", "gst", "cgst", "sgst"],
            cashHints: ["नकद", "cash"],
            cardHints: ["card", "visa", "mastercard"],
            dateFormats: ["dd/MM/yyyy", "d/M/yyyy"],
            currencySymbols: ["₹": "INR"],
            currencyCodes: ["INR"],
            vendorSkipKeywords: ["दिनांक", "बिल", "रसीद", "gstin"],
            metadataKeywords: ["बिल", "रसीद", "gst", "gstin", "fssai", "फोन", "आदेश", "कैशियर", "टोकन"]
        )
    ]

    public static var allTotalLabels: Set<String> {
        Set(all.flatMap(\.totalLabels))
    }

    public static var allSubtotalLabels: Set<String> {
        Set(all.flatMap(\.subtotalLabels))
    }

    public static var allTaxLabels: Set<String> {
        Set(all.flatMap(\.taxLabels))
    }

    public static var allCashHints: Set<String> {
        Set(all.flatMap(\.cashHints))
    }

    public static var allCardHints: Set<String> {
        Set(all.flatMap(\.cardHints))
    }

    public static var allDateFormats: [String] {
        Array(Set(all.flatMap(\.dateFormats))).sorted()
    }

    public static var allCurrencySymbols: [String: String] {
        all.reduce(into: [:]) { result, profile in
            for (symbol, code) in profile.currencySymbols {
                result[symbol] = code
            }
        }
    }

    public static var allCurrencyCodes: Set<String> {
        Set(all.flatMap(\.currencyCodes))
    }

    public static var allVendorSkipKeywords: Set<String> {
        Set(all.flatMap(\.vendorSkipKeywords))
    }

    public static var allMetadataKeywords: Set<String> {
        Set(all.flatMap(\.metadataKeywords))
    }

    static func containsApproximateTotalLabel(in value: String) -> Bool {
        let normalized = ReceiptLanguageProfile.normalize(value)
        if allTotalLabels.contains(where: normalized.contains) {
            return true
        }
        let words = normalized.split { $0.isLetter == false && $0.isNumber == false }.map(String.init)
        let labelWords = allTotalLabels
            .flatMap { $0.split { $0.isLetter == false && $0.isNumber == false } }
            .map(String.init)
            .filter { $0.count >= 4 }
        return words.contains { word in
            labelWords.contains { labelWord in
                guard word.count == labelWord.count else { return false }
                return zip(word, labelWord).lazy.filter { $0 != $1 }.prefix(2).count <= 1
            }
        }
    }

    static func isLikelyLocationHeader(_ value: String, in lines: [String]) -> Bool {
        let normalizedValue = ReceiptLanguageProfile.normalize(value)
            .filter { $0.isLetter || $0.isNumber }
        guard normalizedValue.count >= 4 else { return false }

        return lines.contains { line in
            let normalizedLine = ReceiptLanguageProfile.normalize(line)
            let compactLine = normalizedLine.filter { $0.isLetter || $0.isNumber }
            guard compactLine != normalizedValue, compactLine.contains(normalizedValue) else { return false }
            let digitCount = line.filter(\.isNumber).count
            return digitCount >= 4
                || allVendorSkipKeywords.contains(where: normalizedLine.contains)
                || allMetadataKeywords.contains(where: normalizedLine.contains)
        }
    }

    static func profiles(relevantTo text: String, locale: Locale) -> [ReceiptLanguageProfile] {
        let normalizedText = ReceiptLanguageProfile.normalize(text)
        let preferredLanguage = ReceiptLanguage(locale: locale)

        return all.enumerated()
            .map { index, profile in
                (
                    index: index,
                    profile: profile,
                    score: relevanceScore(for: profile, in: normalizedText),
                    isPreferred: profile.language == preferredLanguage
                )
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                if lhs.isPreferred != rhs.isPreferred {
                    return lhs.isPreferred
                }
                return lhs.index < rhs.index
            }
            .map(\.profile)
    }

    private static func relevanceScore(for profile: ReceiptLanguageProfile, in normalizedText: String) -> Int {
        let signals = profile.totalLabels
            + profile.subtotalLabels
            + profile.taxLabels
            + profile.cashHints
            + profile.cardHints
            + profile.vendorSkipKeywords
            + profile.metadataKeywords
        return signals.reduce(0) { score, signal in
            normalizedText.contains(signal) ? score + 1 : score
        }
    }
}

private extension ReceiptLanguage {
    init?(locale: Locale) {
        guard let languageCode = locale.language.languageCode?.identifier else {
            return nil
        }
        switch languageCode {
        case "en": self = .english
        case "de": self = .german
        case "fr": self = .french
        case "ja": self = .japanese
        case "hi": self = .hindi
        default: return nil
        }
    }
}
