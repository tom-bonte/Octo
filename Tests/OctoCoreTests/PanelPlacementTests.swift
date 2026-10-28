import CoreGraphics
import Testing
import OctoCore

@Suite("Where the menu bar panel opens")
struct PanelPlacementTests {
    // A 1470×956 MacBook screen with a 37 pt menu bar (notch), and an external screen to its right.
    let laptop = PanelPlacement.Screen(frame: CGRect(x: 0, y: 0, width: 1470, height: 956), menuBarHeight: 37)
    let external = PanelPlacement.Screen(frame: CGRect(x: 1470, y: 0, width: 2560, height: 1440), menuBarHeight: 24)
    var screens: [PanelPlacement.Screen] { [laptop, external] }
    let icon = CGRect(x: 1180, y: 919, width: 30, height: 37)

    @Test func clickOnTheIconOpensUnderIt() {
        let anchor = PanelPlacement.anchor(icon: icon, mouse: CGPoint(x: 1195, y: 940), clickedWithMouse: true, screens: screens)
        #expect(anchor == icon)
    }

    @Test func clickAtTheVeryTopOfTheScreenCountsAsTheIcon() {
        let anchor = PanelPlacement.anchor(icon: icon, mouse: CGPoint(x: 1181, y: 956), clickedWithMouse: true, screens: screens)
        #expect(anchor == icon)
    }

    @Test func keyboardOrVoiceOverUsesTheIconWherever() {
        let anchor = PanelPlacement.anchor(icon: icon, mouse: CGPoint(x: 300, y: 200), clickedWithMouse: false, screens: screens)
        #expect(anchor == icon)
    }

    /// A menu bar that hides itself reports the icon above the screen: open where the click was,
    /// just under the menu bar, not at the left edge.
    @Test func iconOffScreenOpensAtThePointerUnderTheMenuBar() {
        let hidden = icon.offsetBy(dx: 0, dy: 40)
        let anchor = PanelPlacement.anchor(icon: hidden, mouse: CGPoint(x: 1195, y: 945), clickedWithMouse: true, screens: screens)
        #expect(anchor.midX == 1195)
        #expect(anchor.minY == 919) // the bottom of the 37 pt menu bar
    }

    /// Behind the notch, or clicked through a menu bar organiser: the pointer isn't on the icon.
    @Test func clickAwayFromTheIconOpensAtThePointer() {
        let anchor = PanelPlacement.anchor(icon: icon, mouse: CGPoint(x: 900, y: 880), clickedWithMouse: true, screens: screens)
        #expect(anchor.midX == 900)
        #expect(anchor.minY == 880) // below the menu bar (an organiser's own bar): right at the pointer
    }

    @Test func noIconAtAllOpensAtThePointer() {
        let anchor = PanelPlacement.anchor(icon: nil, mouse: CGPoint(x: 2000, y: 1430), clickedWithMouse: false, screens: screens)
        #expect(anchor.midX == 2000)
        #expect(anchor.minY == 1416) // the bottom of the 24 pt menu bar
    }

    @Test func iconOnTheExternalScreenOpensThere() {
        let there = CGRect(x: 3700, y: 1416, width: 30, height: 24)
        let anchor = PanelPlacement.anchor(icon: there, mouse: CGPoint(x: 3712, y: 1425), clickedWithMouse: true, screens: screens)
        #expect(anchor == there)
    }
}
