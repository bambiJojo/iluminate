//
//  ReadableWebTextExtractorTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

struct ReadableWebTextExtractorTests {
    @Test func extractsArticleTextWithoutPageChrome() throws {
        let html = """
        <html>
          <head>
            <title>Quiet Story</title>
            <style>.hidden { display: none; }</style>
            <script>window.unrelated = true</script>
          </head>
          <body>
            <header>Home Search Account</header>
            <nav>Browse Menu</nav>
            <article>
              <h1>Quiet Story</h1>
              <p>The first useful paragraph stays inside the reading flow.</p>
              <p>Another useful paragraph follows with enough words for extraction.</p>
            </article>
            <footer>Privacy Terms Contact</footer>
          </body>
        </html>
        """

        let text = try ReadableWebTextExtractor.extract(fromHTML: html)

        #expect(text.contains("Quiet Story"))
        #expect(text.contains("first useful paragraph"))
        #expect(text.contains("Another useful paragraph"))
        #expect(text.localizedCaseInsensitiveContains("Browse Menu") == false)
        #expect(text.localizedCaseInsensitiveContains("window.unrelated") == false)
        #expect(text.localizedCaseInsensitiveContains("Privacy Terms") == false)
    }

    @Test func removesGenericAdsFormsAndRelatedBlocks() throws {
        let html = """
        <main>
          <article class="story-body">
            <p>The opening line remains available to the reader.</p>
            <div class="cookie-banner">Accept cookies</div>
            <div id="ad-container">Advertisement</div>
            <aside class="related-stories">Related links</aside>
            <form><input value="Email"><button>Subscribe</button></form>
            <p>The closing line remains available to the reader too.</p>
          </article>
        </main>
        """

        let text = try ReadableWebTextExtractor.extract(fromHTML: html)

        #expect(text.contains("opening line"))
        #expect(text.contains("closing line"))
        #expect(text.localizedCaseInsensitiveContains("Accept cookies") == false)
        #expect(text.localizedCaseInsensitiveContains("Advertisement") == false)
        #expect(text.localizedCaseInsensitiveContains("Subscribe") == false)
    }

    @Test func decodesEntitiesAndNormalizesWhitespace() throws {
        let html = """
        <article>
          <p>Let&nbsp;the words &amp; breath move together.</p>
          <p>Extra       spacing should not reach the reader.</p>
        </article>
        """

        let text = try ReadableWebTextExtractor.extract(fromHTML: html)

        #expect(text.contains("Let the words & breath move together."))
        #expect(text.contains("Extra spacing should not reach the reader."))
        #expect(text.contains("      ") == false)
    }

    @Test func titleSelectionAndMinimumWordError() {
        let titledHTML = """
        <html><head><title>Quiet&nbsp;Focus &amp; Flow</title></head></html>
        """
        #expect(ReadableWebTextExtractor.title(fromHTML: titledHTML) == "Quiet Focus & Flow")

        #expect(throws: ReadableWebTextExtractionError.noReadableText) {
            try ReadableWebTextExtractor.extract(fromHTML: "<nav>Home Search</nav>")
        }
    }
}
