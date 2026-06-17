//  ReadableWebTextExtractorTests.swift
//  IlumionateTests

import Foundation
import Testing
@testable import Ilumionate

struct ReadableWebTextExtractorTests {

    @Test func extractsArticleTextWithoutPageChrome() throws {
        let html = """
        <!doctype html>
        <html>
          <head>
            <title>Example</title>
            <style>.hidden { display: none; }</style>
            <script>alert("not reader text")</script>
          </head>
          <body>
            <header>Home Search Login</header>
            <nav>Home Browse Account</nav>
            <article>
              <h1>Quiet Focus</h1>
              <p>Breathe in slowly and let attention settle on this sentence.</p>
              <p>Follow the rhythm of the words as the page becomes simple.</p>
            </article>
            <footer>Privacy Policy Terms Contact</footer>
          </body>
        </html>
        """

        let text = try ReadableWebTextExtractor.extract(fromHTML: html)

        #expect(text.contains("Quiet Focus"))
        #expect(text.contains("Breathe in slowly"))
        #expect(text.contains("Follow the rhythm"))
        #expect(text.localizedCaseInsensitiveContains("Home Search Login") == false)
        #expect(text.localizedCaseInsensitiveContains("alert") == false)
        #expect(text.localizedCaseInsensitiveContains("Privacy Policy") == false)
    }

    @Test func removesInlineAdsCookiesAndRelatedBlocks() throws {
        let html = """
        <html>
          <body>
            <main>
              <article>
                <p>The first useful line stays in the reader text.</p>
                <div class="cookie-banner">Accept cookies to continue</div>
                <div id="ad-container">Advertisement Buy something now</div>
                <aside class="related-stories">Related posts and links</aside>
                <p>The second useful line also stays for uninterrupted pacing.</p>
              </article>
            </main>
          </body>
        </html>
        """

        let text = try ReadableWebTextExtractor.extract(fromHTML: html)

        #expect(text.contains("The first useful line"))
        #expect(text.contains("The second useful line"))
        #expect(text.localizedCaseInsensitiveContains("Accept cookies") == false)
        #expect(text.localizedCaseInsensitiveContains("Advertisement") == false)
        #expect(text.localizedCaseInsensitiveContains("Related posts") == false)
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
        #expect(text.contains("&nbsp;") == false)
    }

    @Test func extractsPageTitle() {
        let html = """
        <html>
          <head><title>Quiet&nbsp;Focus &amp; Flow</title></head>
          <body><article><p>Enough readable words live in the body.</p></article></body>
        </html>
        """

        #expect(ReadableWebTextExtractor.title(fromHTML: html) == "Quiet Focus & Flow")
    }

    @Test func truncatesKnownSiteBoilerplateAfterScript() throws {
        let html = """
        <article>
          <h1>Progressive Relaxation</h1>
          <p>The useful induction text stays in the reader flow with enough words.</p>
          <p>Another calming paragraph belongs to the script body.</p>
          <p>&lt; &lt; &lt; Return to Free Hypnosis Scripts page</p>
          <h2>Search For Hypnosis &amp; Hypnotherapy</h2>
          <p>Could you help us by sharing this site?</p>
          <h2>Recent Comments</h2>
        </article>
        """

        let text = try ReadableWebTextExtractor.extract(fromHTML: html)

        #expect(text.contains("Progressive Relaxation"))
        #expect(text.contains("Another calming paragraph"))
        #expect(text.localizedCaseInsensitiveContains("Search For Hypnosis") == false)
        #expect(text.localizedCaseInsensitiveContains("Could you help us") == false)
        #expect(text.localizedCaseInsensitiveContains("Recent Comments") == false)
    }

    @Test func prefersWordPressScriptBodyOverHeroTitleAndSidebar() throws {
        let html = """
        <html>
          <body>
            <main id="inner-wrap" role="main">
              <section class="entry-hero post-hero-section">
                <div class="entry-taxonomies"><a>Induction Script</a></div>
                <h1 class="entry-title">Dave Elman &#8211; Induction &#8211; Deep Trance Hypnosis</h1>
              </section>
              <article class="entry content-bg single-entry">
                <div class="entry-content-wrap">
                  <div class="entry-content single-content">
                    <p>This is the induction for a related script page.</p>
                    <p>Are you ready to be hypnotized? Follow these simple instructions and let attention settle into the words.</p>
                    <p>Take a long deep breath, close the eyes, and let the body relax more completely with each exhale.</p>
                    <div class="awac-wrapper">
                      <p><a href="/free-hypnosis-scripts/">&lt; &lt; &lt; Return to Free Hypnosis Scripts page</a></p>
                    </div>
                    <div class="awac-wrapper">
                      <h2>Search For Hypnosis &amp; Hypnotherapy</h2>
                      <p>Could you help us by sharing this site?</p>
                    </div>
                  </div>
                </div>
              </article>
              <aside class="primary-sidebar">
                <h2>Recent Comments</h2>
                <p>Sidebar links and unrelated background content.</p>
              </aside>
              <div id="comments" class="comments-area">
                <h3>Leave a Reply</h3>
                <p>Your email address will not be published.</p>
              </div>
            </main>
          </body>
        </html>
        """

        let text = try ReadableWebTextExtractor.extract(fromHTML: html)

        #expect(text.hasPrefix("This is the induction"))
        #expect(text.contains("Are you ready to be hypnotized?"))
        #expect(text.localizedCaseInsensitiveContains("Deep Trance Hypnosis") == false)
        #expect(text.localizedCaseInsensitiveContains("Induction Script") == false)
        #expect(text.localizedCaseInsensitiveContains("Recent Comments") == false)
        #expect(text.localizedCaseInsensitiveContains("Leave a Reply") == false)
    }

    @Test func rejectsChromeOnlyPages() {
        let html = """
        <html>
          <body>
            <nav>Home Search Login</nav>
            <footer>Privacy Terms</footer>
          </body>
        </html>
        """

        #expect(throws: ReadableWebTextExtractionError.noReadableText) {
            try ReadableWebTextExtractor.extract(fromHTML: html)
        }
    }
}
