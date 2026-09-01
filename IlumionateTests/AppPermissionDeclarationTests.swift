import Foundation
import Testing

@Suite("App permission declarations")
struct AppPermissionDeclarationTests {
    @Test("The shipping app does not declare the unused Apple Speech permission")
    func shippingAppDoesNotDeclareUnusedAppleSpeechPermission() throws {
        let appBundle = try #require(
            Bundle.allBundles.first {
                $0.bundleIdentifier == "com.byronquine.lumenSync"
            }
        )

        #expect(appBundle.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") == nil)
    }
}
