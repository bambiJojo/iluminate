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
            #expect(url.host == "quineent.wixsite.com")
        }
    }

    @Test("Support and privacy open their published website pages")
    func linksUsePublishedWebsitePages() {
        #expect(
            AppSupportLink.support.url?.absoluteString
                == "https://quineent.wixsite.com/lumesync/support"
        )
        #expect(
            AppSupportLink.privacyPolicy.url?.absoluteString
                == "https://quineent.wixsite.com/lumesync/privacy-policy"
        )
    }
}
