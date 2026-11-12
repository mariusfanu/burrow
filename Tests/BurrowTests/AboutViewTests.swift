import Foundation
import Testing
@testable import Burrow

@MainActor
struct AboutViewTests {
    @Test func aboutURLsPointToExpectedDestinations() {
        #expect(AboutView.personalWebsiteURL.absoluteString == "https://mariusfanu.com")
        #expect(AboutView.burrowWebsiteURL.absoluteString == "https://burrow.mariusfanu.com")
        #expect(AboutView.moleRepoURL.absoluteString == "https://github.com/tw93/Mole")
    }

    @Test func settingsPaneIncludesAbout() {
        #expect(SettingsPane.about.rawValue == "about")
        #expect(SettingsPane(rawValue: "about") == .about)
    }
}
