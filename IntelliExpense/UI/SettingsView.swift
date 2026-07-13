import ExpenseCore
import SwiftUI

#if !INTELLI_EXPENSE_SANDBOX
import CloudKit

enum ICloudAccountStatus: Equatable {
    case checking
    case available
    case unavailable

    static func map(_ status: CKAccountStatus) -> ICloudAccountStatus {
        switch status {
        case .available:
            return .available
        case .couldNotDetermine, .noAccount, .restricted, .temporarilyUnavailable:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    var localizedKey: LocalizedStringKey {
        switch self {
        case .checking: "settings.icloud.checking"
        case .available: "settings.icloud.available"
        case .unavailable: "settings.icloud.unavailable"
        }
    }
}
#endif

struct SettingsView: View {
    @AppStorage(DefaultCurrencySettings.defaultCodeKey) private var defaultCurrencyCode = DefaultCurrencySettings.fallbackCode
    @AppStorage("defaultPaymentMethod") private var defaultPaymentMethodRawValue = PaymentMethod.card.rawValue
    #if os(macOS)
    @AppStorage(AgentImportSettings.requireReviewKey) private var agentEntriesRequireReview = true
    #endif
    #if INTELLI_EXPENSE_SANDBOX
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @AppStorage("sandboxShouldShowOnboarding") private var sandboxShouldShowOnboarding = false
    #else
    @State private var iCloudStatus = ICloudAccountStatus.checking
    #endif

    var body: some View {
        NavigationStack {
            Form {
                Section("settings.section.defaults") {
                    CurrencyPickerRow(
                        title: "settings.defaultCurrency",
                        selectedCode: $defaultCurrencyCode,
                        accessibilityIdentifier: "settings.currency.row"
                    )
                    Picker("settings.defaultPayment", selection: $defaultPaymentMethodRawValue) {
                        ForEach(PaymentMethod.allCases, id: \.self) { method in
                            Text(ExpenseFormatters.paymentName(method)).tag(method.rawValue)
                        }
                    }
                }
                #if os(macOS)
                Section("settings.section.agentEntries") {
                    Toggle("settings.agentEntries.requireReview", isOn: $agentEntriesRequireReview)
                    Text("settings.agentEntries.requireReview.footnote")
                        .contentScaledFont(.footnote)
                        .foregroundStyle(.secondary)
                }
                #endif
                #if INTELLI_EXPENSE_SANDBOX
                Section("Sandbox") {
                    Button(action: resetAndStartOnboarding) {
                        Label("Reset and start onboarding", systemImage: "arrow.counterclockwise")
                    }
                    .accessibilityIdentifier("settings.sandbox.replayOnboarding")
                }
                #else
                Section("settings.section.icloud") {
                    Label(iCloudStatus.localizedKey, systemImage: "icloud")
                }
                #endif
                Section("settings.section.privacy") {
                    Text("settings.privacy.message")
                }
                Section("settings.section.about") {
                    LabeledContent("settings.version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                }
            }
            .macGroupedForm(accessibilityIdentifier: "mac.settings.form")
            #if os(macOS)
            .frame(minWidth: 420, idealWidth: 520, maxWidth: 620)
            #endif
            .navigationTitle("tab.settings")
            .task {
                #if !INTELLI_EXPENSE_SANDBOX
                await refreshICloudStatus()
                #endif
            }
        }
    }

    #if INTELLI_EXPENSE_SANDBOX
    private func resetAndStartOnboarding() {
        hasSeenWelcome = false
        sandboxShouldShowOnboarding = true
    }
    #else
    private func refreshICloudStatus() async {
        do {
            let status = try await CKContainer(identifier: PersistenceStack.cloudKitContainerIdentifier).accountStatus()
            iCloudStatus = ICloudAccountStatus.map(status)
        } catch {
            iCloudStatus = .unavailable
        }
    }
    #endif
}

enum DefaultCurrencySettings {
    static let defaultCodeKey = "defaultCurrencyCode"
    static let seedFlagKey = "defaultCurrencyCodeSeededFromLocale"
    static let fallbackCode = "USD"

    static func seedIfNeeded(defaults: UserDefaults = .standard, locale: Locale = .current) {
        guard defaults.bool(forKey: seedFlagKey) == false else { return }

        if defaults.object(forKey: defaultCodeKey) is String {
            defaults.set(true, forKey: seedFlagKey)
            return
        }

        defaults.set(detectedCode(locale: locale), forKey: defaultCodeKey)
        defaults.set(true, forKey: seedFlagKey)
    }

    static func resetSeededDefault(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultCodeKey)
        defaults.removeObject(forKey: seedFlagKey)
    }

    static func storeSelectedCode(_ code: String, defaults: UserDefaults = .standard) {
        guard let normalizedCode = CurrencyCatalog.normalizedISOCode(code) else { return }
        defaults.set(normalizedCode, forKey: defaultCodeKey)
        defaults.set(true, forKey: seedFlagKey)
    }

    static func detectedCode(locale: Locale = .current) -> String {
        guard let code = locale.currency?.identifier,
              let normalizedCode = CurrencyCatalog.normalizedISOCode(code) else {
            return fallbackCode
        }
        return normalizedCode
    }
}

struct CurrencyOption: Identifiable, Hashable {
    var code: String
    var localizedName: String
    var symbol: String

    var id: String { code }

    var valueSummary: String {
        "\(symbol) · \(localizedName) · \(code)"
    }

    func matches(_ searchText: String) -> Bool {
        guard searchText.isEmpty == false else { return true }
        return code.localizedCaseInsensitiveContains(searchText)
            || localizedName.localizedCaseInsensitiveContains(searchText)
            || symbol.localizedCaseInsensitiveContains(searchText)
    }
}

enum CurrencyCatalog {
    static func normalizedISOCode(_ code: String) -> String? {
        let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalizedCode.isEmpty == false else { return nil }
        let currency = Locale.Currency(normalizedCode)
        guard currency.isISOCurrency else { return nil }
        return currency.identifier.uppercased()
    }

    static func option(for code: String, locale: Locale = .current) -> CurrencyOption? {
        guard let normalizedCode = normalizedISOCode(code) else { return nil }
        return CurrencyOption(
            code: normalizedCode,
            localizedName: localizedName(for: normalizedCode, locale: locale),
            symbol: symbol(for: normalizedCode, locale: locale)
        )
    }

    static func allOptions(locale: Locale = .current) -> [CurrencyOption] {
        let codes = Set(Locale.Currency.isoCurrencies.compactMap { currency in
            currency.isISOCurrency ? currency.identifier.uppercased() : nil
        })
        return codes
            .compactMap { option(for: $0, locale: locale) }
            .sorted { lhs, rhs in
                let nameOrder = lhs.localizedName.localizedStandardCompare(rhs.localizedName)
                if nameOrder == .orderedSame {
                    return lhs.code.localizedStandardCompare(rhs.code) == .orderedAscending
                }
                return nameOrder == .orderedAscending
            }
    }

    private static func localizedName(for code: String, locale: Locale) -> String {
        locale.localizedString(forCurrencyCode: code)
            ?? Locale(identifier: "en").localizedString(forCurrencyCode: code)
            ?? code
    }

    private static func symbol(for code: String, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.locale = locale
        return formatter.currencySymbol?.isEmpty == false ? formatter.currencySymbol : code
    }
}

struct CurrencyPickerRow: View {
    var title: LocalizedStringKey
    @Binding var selectedCode: String
    var accessibilityIdentifier: String

    @State private var isShowingPicker = false

    var body: some View {
        Button {
            isShowingPicker = true
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer(minLength: 12)
                CurrencyValueText(code: selectedCode)
                Image(systemName: "chevron.right")
                    .contentScaledFont(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
        .sheet(isPresented: $isShowingPicker) {
            NavigationStack {
                CurrencyPickerView(selectedCode: $selectedCode)
            }
        }
    }
}

struct CurrencyValueText: View {
    var code: String

    var body: some View {
        Text(summary)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var summary: String {
        CurrencyCatalog.option(for: code)?.valueSummary
            ?? code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

struct CurrencyPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedCode: String
    @State private var searchText = ""

    private let options = CurrencyCatalog.allOptions()

    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    TextField("currencyPicker.search", text: $searchText)
                        .receiptCharactersInputBehavior()
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("currencyPicker.search")
                }
            }

            if suggestedOptions.isEmpty == false {
                Section("currencyPicker.suggested") {
                    ForEach(suggestedOptions) { option in
                        currencyButton(option)
                    }
                }
            }

            Section {
                ForEach(filteredOptions) { option in
                    currencyButton(option)
                }
            }
        }
        .accessibilityIdentifier("currencyPicker.list")
        .navigationTitle("currencyPicker.title")
        .receiptInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("common.cancel") {
                    dismiss()
                }
            }
        }
    }

    private var selectedNormalizedCode: String? {
        CurrencyCatalog.normalizedISOCode(selectedCode)
    }

    private var suggestedOptions: [CurrencyOption] {
        var codes: [String] = []
        if let deviceCode = Locale.current.currency?.identifier,
           let normalizedCode = CurrencyCatalog.normalizedISOCode(deviceCode) {
            codes.append(normalizedCode)
        }
        if let selectedNormalizedCode {
            codes.append(selectedNormalizedCode)
        }
        return codes.reduce(into: [CurrencyOption]()) { result, code in
            guard result.contains(where: { $0.code == code }) == false,
                  let option = options.first(where: { $0.code == code }) ?? CurrencyCatalog.option(for: code) else {
                return
            }
            result.append(option)
        }
    }

    private var filteredOptions: [CurrencyOption] {
        let suggestedCodes = Set(suggestedOptions.map(\.code))
        return options
            .filter { suggestedCodes.contains($0.code) == false }
            .filter { $0.matches(searchText) }
    }

    private func currencyButton(_ option: CurrencyOption) -> some View {
        Button {
            selectedCode = option.code
            dismiss()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.localizedName)
                        .foregroundStyle(.primary)
                    Text("\(option.symbol) · \(option.code)")
                        .contentScaledFont(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selectedNormalizedCode == option.code {
                    Image(systemName: "checkmark")
                        .contentScaledFont(.body.weight(.semibold))
                        .foregroundStyle(Color("LedgerGreen"))
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("currency.option.\(option.code)")
    }
}
