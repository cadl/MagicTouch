import Foundation
import Testing
@testable import MagicTouch

struct UpdateManagerTests {
    private let publicKey = Data(repeating: 1, count: 32).base64EncodedString()

    @Test @MainActor func acceptsHTTPSFeedAndEd25519PublicKey() {
        #expect(UpdateManager.hasValidConfiguration([
            "SUFeedURL": "https://updates.example.com/appcast.xml",
            "SUPublicEDKey": publicKey
        ]))
    }

    @Test @MainActor func rejectsMissingOrUnresolvedReleaseConfiguration() {
        #expect(!UpdateManager.hasValidConfiguration([:]))
        #expect(!UpdateManager.hasValidConfiguration([
            "SUFeedURL": "$(SPARKLE_FEED_URL)",
            "SUPublicEDKey": "$(SPARKLE_PUBLIC_ED_KEY)"
        ]))
    }

    @Test @MainActor func rejectsInsecureFeedOrInvalidPublicKey() {
        for feed in ["http://updates.example.com/appcast.xml", "https:///", ""] {
            #expect(!UpdateManager.hasValidConfiguration([
                "SUFeedURL": feed, "SUPublicEDKey": publicKey
            ]))
        }
        for key in ["", "invalid", Data(repeating: 1, count: 31).base64EncodedString()] {
            #expect(!UpdateManager.hasValidConfiguration([
                "SUFeedURL": "https://updates.example.com/appcast.xml", "SUPublicEDKey": key
            ]))
        }
    }
}
