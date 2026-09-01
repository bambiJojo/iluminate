//
//  AppSupportLinkTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

struct AppSupportLinkTests {
    @Test("Every in-app help link is a public HTTPS URL")
    func linksArePublicHTTPSURLs() throws {
        for link in AppSupportLink.allCases {
            let url = try #require(link.url)

            #expect(url.scheme == "https")
            #expect(url.host == "github.com")
        }
    }

    @Test("Support and privacy open their published project pages")
    func linksUsePublishedProjectPages() {
        #expect(
            AppSupportLink.support.url?.absoluteString
                == "https://github.com/bambiJojo/iluminate/issues"
        )
        #expect(
            AppSupportLink.privacyPolicy.url?.absoluteString
                == "https://github.com/bambiJojo/iluminate/blob/main/PRIVACY_POLICY.md"
        )
    }
}
