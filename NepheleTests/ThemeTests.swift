import Testing
import SwiftUI
@testable import Nephele

@Suite struct ThemeTests {
    @Test func inkIsDarkOnOrangeAndWhiteOnNavy() {
        #expect(NepheleTheme.prefersDarkInk(onHex: "#F6821F") == true)
        #expect(NepheleTheme.prefersDarkInk(onHex: "#FBAD41") == true)
        #expect(NepheleTheme.prefersDarkInk(onHex: "#1F2A5C") == false)
        #expect(NepheleTheme.prefersDarkInk(onHex: "#7A5AF8") == false)
    }

    @Test func compactDensityHasSmallerPaddingThanComfortable() {
        var compact = AppSettings(); compact.density = .compact
        var comfy = AppSettings(); comfy.density = .comfortable
        #expect(NepheleTheme(compact).pad < NepheleTheme(comfy).pad)
        #expect(NepheleTheme(compact).rowPad < NepheleTheme(comfy).rowPad)
    }

    @Test func themeFollowsRadiusFontAndIconWeight() {
        var s = AppSettings(); s.radius = 14; s.fontDesign = .serif; s.iconWeight = 1.4
        let t = NepheleTheme(s)
        #expect(t.radius == 14)
        #expect(t.fontDesign == .serif)
        #expect(t.iconWeight == .light)
        s.iconWeight = 2.3
        #expect(NepheleTheme(s).iconWeight == .semibold)
    }

    @Test func routeTitlesAreSentenceCase() {
        #expect(Route.overview.title == "Overview")
        #expect(Route.settings.title == "Settings")
        #expect(Route.allCases.allSatisfy { !$0.symbol.isEmpty })
    }

    @Test func visibleRoutesFollowNavOrderAndVisibility() {
        var s = AppSettings()
        s.nav = [NavEntry(id: .usage, visible: true), NavEntry(id: .domains, visible: false), NavEntry(id: .overview, visible: true), NavEntry(id: .alerts, visible: true), NavEntry(id: .appearance, visible: true), NavEntry(id: .settings, visible: true)]
        #expect(s.visibleRoutes == [.usage, .overview, .alerts, .appearance, .settings])
    }

    @Test func hexColourRoundTrips() {
        #expect(Color(hex: "#2F7DE1").hexString == "#2F7DE1")
        #expect(Color(hex: "#F6821F").hexString == "#F6821F")
    }
}
