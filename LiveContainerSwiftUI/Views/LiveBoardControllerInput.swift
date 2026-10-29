import Foundation
import GameController

/// Input is owned only while the launcher is visible. No guest controller configuration is changed.
@MainActor
final class LiveBoardControllerInput: ObservableObject {
    static let pauseNotification = Notification.Name("LiveBoardPauseController")
    static let resumeNotification = Notification.Name("LiveBoardResumeController")
    enum Command: Equatable { case left, right, up, down, confirm, back, details, favorite, previousSection, nextSection }
    @Published private(set) var connected = false
    @Published private(set) var confirmSymbol = "a.circle"
    @Published private(set) var detailsSymbol = "x.circle"
    var onCommand: ((Command) -> Void)?
    private static let owners = NSMapTable<GCExtendedGamepad, LiveBoardControllerInput>.weakToWeakObjects()
    private var active = false
    private var observers: [NSObjectProtocol] = []
    private var profiles: [(GCExtendedGamepad, GCExtendedGamepadValueChangedHandler?)] = []
    private var repeatTask: Task<Void, Never>?
    private var heldDirection: Command?

    func start() {
        guard !active else {
            for controller in GCController.controllers() { attach(controller) }
            return
        }
        active = true
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] notification in
                guard let controller = notification.object as? GCController else { return }
                Task { @MainActor [weak self] in self?.attach(controller) }
            },
            center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] notification in
                guard let controller = notification.object as? GCController else { return }
                Task { @MainActor [weak self] in self?.detach(controller) }
            }
        ]
        // Observe before enumeration so a controller arriving during startup cannot be missed.
        for controller in GCController.controllers() { attach(controller) }
        connected = !profiles.isEmpty
    }
    func stop() {
        onCommand = nil
        guard active else { return }
        active = false
        repeatTask?.cancel(); repeatTask = nil; heldDirection = nil
        for (profile, previous) in profiles where Self.owners.object(forKey: profile) === self {
            profile.valueChangedHandler = previous
            Self.owners.removeObject(forKey: profile)
        }
        profiles.removeAll()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll(); connected = false
    }
    // Internal for tests with GameController's supported synthetic extended-gamepad profile.
    func attach(_ controller: GCController) {
        guard active, let profile = controller.extendedGamepad,
              !profiles.contains(where: { $0.0 === profile }) else { return }
        // SwiftUI can mount the new mode before unmounting the old one. Transfer
        // ownership first so the old view cannot restore over the new handler.
        if let previousOwner = Self.owners.object(forKey: profile), previousOwner !== self {
            previousOwner.detach(controller)
        }
        Self.owners.setObject(self, forKey: profile)
        profiles.append((profile, profile.valueChangedHandler))
        profile.valueChangedHandler = { [weak self] gamepad, element in
            Task { @MainActor [weak self] in self?.handle(gamepad, element: element) }
        }
        confirmSymbol = profile.buttonA.sfSymbolsName ?? "a.circle"
        detailsSymbol = profile.buttonX.sfSymbolsName ?? "x.circle"
        connected = true
    }
    private func detach(_ controller: GCController) {
        guard let profile = controller.extendedGamepad else { return }
        if let index = profiles.firstIndex(where: { $0.0 === profile }) {
            let previous = profiles.remove(at: index)
            if Self.owners.object(forKey: profile) === self {
                profile.valueChangedHandler = previous.1
                Self.owners.removeObject(forKey: profile)
            }
        }
        repeatTask?.cancel(); heldDirection = nil
        connected = !profiles.isEmpty
    }
    private func handle(_ profile: GCExtendedGamepad, element: GCControllerElement) {
        guard active else { return }
        if element === profile.dpad || element === profile.leftThumbstick {
            let pad = element === profile.dpad ? profile.dpad : profile.leftThumbstick
            updateDirection(x: pad.xAxis.value, y: pad.yAxis.value)
        } else if element === profile.buttonA, profile.buttonA.isPressed { onCommand?(.confirm) }
        else if element === profile.buttonB, profile.buttonB.isPressed { onCommand?(.back) }
        else if element === profile.buttonX, profile.buttonX.isPressed { onCommand?(.details) }
        else if element === profile.buttonY, profile.buttonY.isPressed { onCommand?(.favorite) }
        else if element === profile.leftShoulder, profile.leftShoulder.isPressed { onCommand?(.previousSection) }
        else if element === profile.rightShoulder, profile.rightShoulder.isPressed { onCommand?(.nextSection) }
        else if element === profile.buttonMenu, profile.buttonMenu.isPressed { onCommand?(.details) }
    }
    private func updateDirection(x: Float, y: Float) {
        let direction: Command?
        if max(abs(x), abs(y)) < 0.55 { direction = nil }
        else if abs(x) >= abs(y) { direction = x > 0 ? .right : .left }
        else { direction = y > 0 ? .up : .down }
        guard heldDirection != direction else { return }
        repeatTask?.cancel(); heldDirection = direction
        guard let direction else { return }
        onCommand?(direction)
        repeatTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            while !Task.isCancelled {
                guard let self, self.active else { return }
                self.onCommand?(direction)
                try? await Task.sleep(nanoseconds: 140_000_000)
            }
        }
    }
}

struct LiveBoardConsoleNavigation: Equatable {
    enum Focus: Equatable { case header, rail, launch, details }
    var selectedIndex = 0
    var headerIndex = 0
    var focus: Focus = .rail
    mutating func move(_ command: LiveBoardControllerInput.Command, count: Int) {
        switch command {
        case .left:
            if focus == .header { headerIndex = max(0, headerIndex - 1) }
            else if focus == .details { focus = .launch }
            else if focus == .rail { selectedIndex = max(0, selectedIndex - 1) }
        case .right:
            if focus == .header { headerIndex = min(3, headerIndex + 1) }
            else if focus == .launch { focus = .details }
            else if focus == .rail { selectedIndex = min(max(0, count - 1), selectedIndex + 1) }
        case .up: focus = focus == .rail ? .header : .rail
        case .down: focus = focus == .header ? .rail : .launch
        case .back: focus = .rail
        default: break
        }
    }
}
