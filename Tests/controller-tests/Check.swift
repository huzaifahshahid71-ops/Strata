import Foundation
import GameController
@main struct Check {
    @MainActor static func main() async {
        let pad = GCController.withExtendedGamepad()
        let first = LiveBoardControllerInput()
        var firstEvents = 0
        first.onCommand = { _ in firstEvents += 1 }
        first.start(); first.attach(pad)
        precondition(first.connected)
        let second = LiveBoardControllerInput()
        var secondEvents = 0
        second.onCommand = { _ in secondEvents += 1 }
        second.start(); second.attach(pad)
        precondition(second.connected && !first.connected)
        first.stop()
        let profile = pad.extendedGamepad!
        profile.buttonA.setValue(1)
        profile.valueChangedHandler?(profile, profile.buttonA)
        try? await Task.sleep(nanoseconds: 50_000_000)
        precondition(secondEvents > 0 && firstEvents == 0, "Old owner stole input")
        second.stop()
        precondition(!second.connected)
        second.onCommand = { _ in secondEvents += 1 }
        second.start(); second.attach(pad)
        precondition(second.connected)
        second.stop()
        print("PASS: initial attach, ownership transfer, old-view stop, button delivery, restart")
    }
}
