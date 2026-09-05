//
//  ThirdPartyNoticesTests.swift
//  IlumionateTests
//

import Testing
@testable import Ilumionate

struct ThirdPartyNoticesTests {
    @Test("The app bundles notices for every resolved third-party package")
    func bundledNoticesCoverResolvedPackages() throws {
        let notices = try #require(ThirdPartyNotices.text())

        #expect(ThirdPartyNotices.missingComponents(in: notices).isEmpty)
        #expect(notices.contains("Apache License"))
        #expect(notices.contains("MIT License"))
        #expect(notices.contains("The SwiftASN1 Project"))
        #expect(notices.contains("The SwiftCrypto Project"))
    }
}
