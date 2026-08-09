import Testing
@testable import Ilumionate

struct HomeDoorTests {

    @Test
    func thereAreExactlyFourDoorsInFixedOrder() {
        #expect(HomeDoor.allCases == [.listen, .read, .visuals, .pulse])
    }

    @Test
    func eachDoorRoutesToItsSurface() {
        #expect(HomeDoor.listen.route == .audioLibrary)
        #expect(HomeDoor.read.route == .reader)
        #expect(HomeDoor.visuals.route == .create(.visualField))
        #expect(HomeDoor.pulse.route == .create(.flash))
    }

    @Test
    func lightPathDoorsRouteToCreateRatherThanStraightIntoAPlayer() {
        // Landing on Create preserves CreateSessionKind.requiresSafetyWarning.
        // A door that started a flash directly would bypass it.
        for door in [HomeDoor.visuals, .pulse] {
            guard case .create = door.route else {
                Issue.record("\(door) must route to Create, not a player")
                return
            }
        }
    }

    @Test
    func everyDoorCarriesADistinctAnalyticsCase() {
        let actions = HomeDoor.allCases.map(\.analyticsAction)
        #expect(Set(actions.map(\.rawValue)).count == HomeDoor.allCases.count)
    }

    @Test
    func everyDoorHasCopy() {
        for door in HomeDoor.allCases {
            #expect(!door.title.isEmpty)
            #expect(!door.subtitle.isEmpty)
            #expect(!door.systemImage.isEmpty)
        }
    }
}
