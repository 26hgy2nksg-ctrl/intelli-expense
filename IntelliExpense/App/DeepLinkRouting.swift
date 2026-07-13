import Foundation

/// The four first-class ways a receipt enters the app (PRD §5). Shared verbatim
/// by the app and the widget extension: the widget only ever turns a `CaptureKind`
/// into a `capture` deep link, and the app parses it back out and dispatches to the
/// existing in-app flow for that kind. Raw values are URL tokens and are never localized.
enum CaptureKind: String, Equatable, CaseIterable {
    case scan
    case photo
    case file
    case manual

    /// Maps a `kind` query value to a case. Absent or unrecognized values fall back
    /// to `.scan` so a bare `intelliexpense://capture` (the existing control and App
    /// Shortcut) keeps meaning "scan", and a garbage `kind` is never a dead tap.
    static func from(queryValue: String?) -> CaptureKind {
        guard let queryValue, let kind = CaptureKind(rawValue: queryValue) else { return .scan }
        return kind
    }
}

enum AppDeepLinkRoute: Equatable {
    case sharedInbox
    case capture(CaptureKind)
}

enum AppDeepLinkRouter {
    static func route(for url: URL, supportedSchemes: Set<String>) -> AppDeepLinkRoute? {
        guard let scheme = url.scheme, supportedSchemes.contains(scheme) else { return nil }

        switch url.host {
        case "shared-inbox":
            return .sharedInbox
        case "capture":
            return .capture(captureKind(from: url))
        default:
            return nil
        }
    }

    private static func captureKind(from url: URL) -> CaptureKind {
        let queryValue = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "kind" })?
            .value
        return CaptureKind.from(queryValue: queryValue)
    }

    /// Bare `<scheme>://capture` — backward-compatible with the scan-only route the
    /// App Intent bridge relies on. Parses back to `.capture(.scan)`.
    static func captureURL(forScheme scheme: String) -> URL {
        URL(string: "\(scheme)://capture")!
    }

    /// `<scheme>://capture?kind=<kind>` — the form every Quick Capture widget tile builds.
    static func captureURL(forScheme scheme: String, kind: CaptureKind) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "capture"
        components.queryItems = [URLQueryItem(name: "kind", value: kind.rawValue)]
        return components.url!
    }

    static var appScheme: String {
        #if INTELLI_EXPENSE_SANDBOX
        return "intelliexpense-sandbox"
        #else
        return "intelliexpense"
        #endif
    }

    static var captureURL: URL {
        captureURL(forScheme: appScheme)
    }

    static func captureURL(kind: CaptureKind) -> URL {
        captureURL(forScheme: appScheme, kind: kind)
    }
}

struct DeepLinkRequestState: Equatable {
    var sharedInboxOpenRequestID: UUID?
    var captureOpenRequestID: UUID?
    /// The capture kind requested by the most recent `capture` open. Carried alongside
    /// `captureOpenRequestID` so the per-open request-ID idempotency is unchanged.
    var captureRequestedKind: CaptureKind = .scan

    mutating func apply(_ route: AppDeepLinkRoute, requestID: UUID = UUID()) {
        switch route {
        case .sharedInbox:
            sharedInboxOpenRequestID = requestID
        case .capture(let kind):
            captureRequestedKind = kind
            captureOpenRequestID = requestID
        }
    }
}

struct DeepLinkRequestGate: Equatable {
    private var lastHandledRequestID: UUID?

    mutating func shouldHandle(_ requestID: UUID?) -> Bool {
        guard let requestID, requestID != lastHandledRequestID else { return false }
        lastHandledRequestID = requestID
        return true
    }
}
