import ExpenseCore
import SwiftUI

struct OnboardingWelcomeView: View {
    var onContinue: () -> Void
    @AppStorage(DefaultCurrencySettings.defaultCodeKey) private var defaultCurrencyCode = DefaultCurrencySettings.fallbackCode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize = 100
    @State private var isRevealed = false
    @State private var didStartReveal = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 20)
                    identityBand
                    Spacer(minLength: 32)
                    storyBand
                    Spacer(minLength: 32)
                    footerCluster
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height)
                .padding(24)
            }
        }
        .onAppear(perform: startRevealIfNeeded)
    }

    private var identityBand: some View {
        VStack(spacing: 20) {
            Image("WelcomeAppIcon")
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.2237, style: .continuous))
                .shadow(color: Color.black.opacity(0.14), radius: 14, x: 0, y: 5)
                .accessibilityIdentifier("onboarding.icon")
                .accessibilityHidden(true)
                .onboardingReveal(isRevealed: isRevealed, reduceMotion: reduceMotion, delay: 0)

            Text("onboarding.welcome.title")
                .contentScaledFont(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .onboardingReveal(isRevealed: isRevealed, reduceMotion: reduceMotion, delay: 0.12)
        }
    }

    private var storyBand: some View {
        VStack(spacing: 18) {
            OnboardingBullet(symbol: "camera.viewfinder", title: "onboarding.bullet.capture.title", subtitle: "onboarding.bullet.capture.subtitle")
                .onboardingReveal(isRevealed: isRevealed, reduceMotion: reduceMotion, delay: 0.22)
            OnboardingBullet(symbol: "checkmark.seal", title: "onboarding.bullet.confirm.title", subtitle: "onboarding.bullet.confirm.subtitle")
                .onboardingReveal(isRevealed: isRevealed, reduceMotion: reduceMotion, delay: 0.30)
            OnboardingBullet(symbol: "square.and.arrow.up", title: "onboarding.bullet.export.title", subtitle: "onboarding.bullet.export.subtitle")
                .onboardingReveal(isRevealed: isRevealed, reduceMotion: reduceMotion, delay: 0.38)
        }
    }

    private var footerCluster: some View {
        VStack(spacing: 16) {
            Label("onboarding.privacy", systemImage: "lock.shield")
                .contentScaledFont(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityElement(children: .combine)

            OnboardingCurrencyRow(selectedCode: $defaultCurrencyCode)

            Button(action: onContinue) {
                Text("common.continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color("LedgerGreen"))
            .controlSize(.large)
            .accessibilityIdentifier("onboarding.continue")
        }
        .onboardingReveal(isRevealed: isRevealed, reduceMotion: reduceMotion, delay: 0.48)
    }

    private func startRevealIfNeeded() {
        guard didStartReveal == false else { return }
        didStartReveal = true
        if shouldAnimateReveal {
            isRevealed = true
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isRevealed = true
            }
        }
    }

    private var shouldAnimateReveal: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return reduceMotion == false && arguments.contains("--ui-testing") == false && arguments.contains("-SkipOnboarding") == false
    }
}

private struct OnboardingCurrencyRow: View {
    @Binding var selectedCode: String
    @State private var isShowingPicker = false

    var body: some View {
        Button {
            isShowingPicker = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "banknote")
                    .contentScaledFont(.subheadline.weight(.semibold))
                    .foregroundStyle(Color("LedgerGreen"))
                    .frame(width: 30, height: 30)
                    .background(Color("LedgerGreenSoft"), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("onboarding.currency.label")
                        .contentScaledFont(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                    CurrencyValueText(code: selectedCode)
                        .contentScaledFont(.footnote)
                }
                Spacer(minLength: 8)
                Text("onboarding.currency.change")
                    .contentScaledFont(.footnote.weight(.semibold))
                    .foregroundStyle(Color("LedgerGreen"))
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding.currency.row")
        .accessibilityElement(children: .combine)
        .sheet(isPresented: $isShowingPicker) {
            NavigationStack {
                CurrencyPickerView(selectedCode: $selectedCode)
            }
        }
    }
}

private struct OnboardingBullet: View {
    var symbol: String
    var title: LocalizedStringKey
    var subtitle: LocalizedStringKey
    @ScaledMetric(relativeTo: .headline) private var iconTileSize = 38

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .contentScaledFont(.headline)
                .imageScale(.medium)
                .foregroundStyle(Color("LedgerGreen"))
                .frame(width: iconTileSize, height: iconTileSize)
                .background(Color("LedgerGreenSoft"), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).contentScaledFont(.subheadline.weight(.semibold))
                Text(subtitle)
                    .contentScaledFont(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct OnboardingRevealModifier: ViewModifier {
    var isRevealed: Bool
    var reduceMotion: Bool
    var delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(isRevealed ? 1 : 0)
            .scaleEffect(reduceMotion || isRevealed ? 1 : 0.9)
            .offset(y: reduceMotion || isRevealed ? 0 : 8)
            .animation(animation, value: isRevealed)
    }

    private var animation: Animation? {
        guard reduceMotion == false else {
            return .easeOut(duration: 0.2)
        }
        return .easeOut(duration: 0.32).delay(delay)
    }
}

private extension View {
    func onboardingReveal(isRevealed: Bool, reduceMotion: Bool, delay: Double) -> some View {
        modifier(OnboardingRevealModifier(isRevealed: isRevealed, reduceMotion: reduceMotion, delay: delay))
    }
}

struct AppleIntelligenceGateView: View {
    var status: ModelAvailabilityStatus
    var openSettings: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: gateSymbol)
                .contentScaledFont(.largeTitle.weight(.semibold))
                .imageScale(.large)
                .foregroundStyle(Color("LedgerGreen"))
                .accessibilityHidden(true)
            Text(titleKey)
                .contentScaledFont(.title2.bold())
                .multilineTextAlignment(.center)
            Text(messageKey)
                .contentScaledFont(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if status == .appleIntelligenceNotEnabled {
                Text("onboarding.gate.path")
                    .contentScaledFont(.footnote)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Button("onboarding.gate.openSettings", action: openSettings)
                    .buttonStyle(.borderedProminent)
                    .tint(Color("LedgerGreen"))
                    .controlSize(.large)
                    .accessibilityIdentifier("gate.openSettings")
            }
            Spacer()
        }
        .padding(24)
    }

    private var gateSymbol: String {
        switch status {
        case .appleIntelligenceNotEnabled: "gearshape.2"
        case .deviceNotEligible: "iphone.slash"
        default: "exclamationmark.triangle"
        }
    }

    private var titleKey: LocalizedStringKey {
        switch status {
        case .appleIntelligenceNotEnabled: "onboarding.gate.notEnabled.title"
        case .deviceNotEligible: "onboarding.gate.notEligible.title"
        default: "onboarding.gate.unavailable.title"
        }
    }

    private var messageKey: LocalizedStringKey {
        switch status {
        case .appleIntelligenceNotEnabled: "onboarding.gate.notEnabled.message"
        case .deviceNotEligible: "onboarding.gate.notEligible.message"
        default: "onboarding.gate.unavailable.message"
        }
    }
}

struct AppleIntelligencePreparingNoticeView: View {
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "arrow.down.circle")
                .contentScaledFont(.largeTitle.weight(.semibold))
                .imageScale(.large)
                .foregroundStyle(Color("LedgerGreen"))
                .accessibilityHidden(true)
            Text("onboarding.modelReady.title")
                .contentScaledFont(.title2.bold())
                .multilineTextAlignment(.center)
            Text("onboarding.modelReady.message")
                .contentScaledFont(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("onboarding.modelReady.continue", action: onContinue)
                .buttonStyle(.borderedProminent)
                .tint(Color("LedgerGreen"))
                .controlSize(.large)
                .accessibilityIdentifier("modelReady.continue")
            Spacer()
        }
        .padding(24)
    }
}

struct CameraPermissionDeniedView: View {
    @Environment(\.dismiss) private var dismiss
    var openSettings: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "camera.badge.ellipsis")
                    .contentScaledFont(.largeTitle.weight(.semibold))
                    .imageScale(.large)
                    .foregroundStyle(Color("LedgerGreen"))
                    .accessibilityHidden(true)
                Text("capture.camera.denied.title")
                    .contentScaledFont(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("capture.camera.denied.message")
                    .contentScaledFont(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("capture.camera.denied.imports")
                    .contentScaledFont(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("capture.camera.denied.settings", action: openSettings)
                    .buttonStyle(.borderedProminent)
                    .tint(Color("LedgerGreen"))
                    .controlSize(.large)
                    .accessibilityIdentifier("cameraDenied.settings")
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.done") { dismiss() }
                }
            }
        }
    }
}
