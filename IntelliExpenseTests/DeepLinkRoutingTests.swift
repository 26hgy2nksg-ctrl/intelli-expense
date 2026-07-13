import XCTest
@testable import IntelliExpense

final class DeepLinkRoutingTests: XCTestCase {
    func testCaptureHostRoutesForDurableScheme() {
        let url = URL(string: "intelliexpense://capture")!

        XCTAssertEqual(
            AppDeepLinkRouter.route(for: url, supportedSchemes: ["intelliexpense"]),
            .capture(.scan)
        )
    }

    func testUnknownHostsAreIgnored() {
        let url = URL(string: "intelliexpense://unknown")!

        XCTAssertNil(AppDeepLinkRouter.route(for: url, supportedSchemes: ["intelliexpense"]))
    }

    func testCaptureKindQueryItemParsesEachKind() {
        for kind in CaptureKind.allCases {
            let url = URL(string: "intelliexpense://capture?kind=\(kind.rawValue)")!
            XCTAssertEqual(
                AppDeepLinkRouter.route(for: url, supportedSchemes: ["intelliexpense"]),
                .capture(kind),
                "kind=\(kind.rawValue) should route to .capture(.\(kind.rawValue))"
            )
        }
    }

    func testBareCaptureAndUnknownKindFallBackToScan() {
        XCTAssertEqual(
            AppDeepLinkRouter.route(for: URL(string: "intelliexpense://capture")!, supportedSchemes: ["intelliexpense"]),
            .capture(.scan)
        )
        XCTAssertEqual(
            AppDeepLinkRouter.route(for: URL(string: "intelliexpense://capture?kind=nonsense")!, supportedSchemes: ["intelliexpense"]),
            .capture(.scan)
        )
        XCTAssertEqual(
            AppDeepLinkRouter.route(for: URL(string: "intelliexpense://capture?other=photo")!, supportedSchemes: ["intelliexpense"]),
            .capture(.scan)
        )
    }

    func testSchemesRemainSplitBetweenDurableAndSandboxLanes() {
        XCTAssertEqual(
            AppDeepLinkRouter.route(
                for: URL(string: "intelliexpense-sandbox://capture")!,
                supportedSchemes: ["intelliexpense-sandbox"]
            ),
            .capture(.scan)
        )
        XCTAssertNil(
            AppDeepLinkRouter.route(
                for: URL(string: "intelliexpense-sandbox://capture")!,
                supportedSchemes: ["intelliexpense"]
            )
        )
        XCTAssertEqual(AppDeepLinkRouter.captureURL(forScheme: "intelliexpense").absoluteString, "intelliexpense://capture")
        XCTAssertEqual(AppDeepLinkRouter.captureURL(forScheme: "intelliexpense-sandbox").absoluteString, "intelliexpense-sandbox://capture")
    }

    func testCaptureKindURLsRoundTripPerLane() {
        for scheme in ["intelliexpense", "intelliexpense-sandbox"] {
            for kind in CaptureKind.allCases {
                let url = AppDeepLinkRouter.captureURL(forScheme: scheme, kind: kind)
                XCTAssertEqual(url.absoluteString, "\(scheme)://capture?kind=\(kind.rawValue)")
                XCTAssertEqual(
                    AppDeepLinkRouter.route(for: url, supportedSchemes: [scheme]),
                    .capture(kind),
                    "\(scheme) kind=\(kind.rawValue) must round-trip"
                )
            }
        }
    }

    func testCaptureRequestIDIsConsumedExactlyOncePerOpenAndCarriesKind() {
        let first = UUID()
        let second = UUID()
        var state = DeepLinkRequestState()
        var gate = DeepLinkRequestGate()

        state.apply(.capture(.photo), requestID: first)
        XCTAssertEqual(state.captureRequestedKind, .photo)
        XCTAssertTrue(gate.shouldHandle(state.captureOpenRequestID))
        XCTAssertFalse(gate.shouldHandle(state.captureOpenRequestID))

        state.apply(.capture(.manual), requestID: second)
        XCTAssertEqual(state.captureRequestedKind, .manual)
        XCTAssertTrue(gate.shouldHandle(state.captureOpenRequestID))
    }

    func testSharedInboxRouteLeavesCaptureKindUntouched() {
        var state = DeepLinkRequestState()
        state.apply(.capture(.file))
        XCTAssertEqual(state.captureRequestedKind, .file)

        state.apply(.sharedInbox)
        XCTAssertEqual(state.captureRequestedKind, .file, "shared-inbox opens must not mutate the capture kind")
    }

    func testCaptureKindDispatchesToMatchingInAppFlow() {
        XCTAssertEqual(CaptureKind.scan.externalCaptureAction, .accessoryCapture(.cameraScan))
        XCTAssertEqual(CaptureKind.photo.externalCaptureAction, .accessoryCapture(.photoImport))
        XCTAssertEqual(CaptureKind.file.externalCaptureAction, .fileImport)
        XCTAssertEqual(CaptureKind.manual.externalCaptureAction, .manualEntry)
    }
}
