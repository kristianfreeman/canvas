import CanvasCore
import Testing

@Suite struct WarmPolicyTests {
    private func policy(_ text: String) -> WarmPolicy {
        WarmPolicy(Config(parsing: text))
    }

    @Test func defaultLoadsNoPageUntilNeededAndLingersTwoMinutes() {
        let policy = WarmPolicy(Config())
        #expect(!policy.prefills)
        #expect(policy.keepsPage)
        #expect(policy.trimDelay(visiblePanels: 0) == 120)
        #expect(policy.trimDelay(visiblePanels: 1) == nil)
    }

    @Test func lingerSecondsIsConfigurable() {
        #expect(policy("linger_seconds = 30").trimDelay(visiblePanels: 0) == 30)
        #expect(policy("linger_seconds = 0").trimDelay(visiblePanels: 0) == 0)
        #expect(policy("linger_seconds = -5").trimDelay(visiblePanels: 0) == 120)
    }

    @Test func idleTrimsAfterTenMinutesByDefault() {
        let idle = policy(#"warm = "idle""#)
        #expect(idle.prefills)
        #expect(idle.trimDelay(visiblePanels: 0) == 600)
    }

    @Test func idleKeepsThePageWhilePanelsAreOpen() {
        let idle = policy("warm = \"idle\"\nidle_minutes = 3")
        #expect(idle.trimDelay(visiblePanels: 1) == nil)
        #expect(idle.trimDelay(visiblePanels: 0) == 180)
    }

    @Test func alwaysPrefillsAndNeverTrims() {
        let always = policy(#"warm = "always""#)
        #expect(always.prefills)
        #expect(always.keepsPage)
        #expect(always.trimDelay(visiblePanels: 0) == nil)
    }

    @Test func neverKeepsNoPage() {
        let never = policy(#"warm = "never""#)
        #expect(!never.prefills)
        #expect(!never.keepsPage)
        #expect(never.trimDelay(visiblePanels: 0) == nil)
    }
}
