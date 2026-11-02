import SwiftUI
import UIKit

@MainActor enum LiveBoardOrientation {
    static var mask: UIInterfaceOrientationMask = preferredHostMask()
    static var owner: UUID?

    static func preferredHostMask() -> UIInterfaceOrientationMask {
        let mode = LCUtils.appGroupUserDefault.string(forKey: "LiveBoardMode") ?? "ios"
        return (mode == "cinematic" || mode == "bigPicture") ? .landscape : .portrait
    }

    static func apply(_ next: UIInterfaceOrientationMask, window: UIWindow?, force: Bool = false) {
        if #available(iOS 16.0, *), MultitaskDockManager.shared.immersiveGuestActive {
            return
        }
        let changed = mask != next
        mask = next
        let resolvedWindow = window ?? activeHostWindow()
        guard let scene = resolvedWindow?.windowScene else { return }
        let wrongOrientation = (next == .portrait && scene.interfaceOrientation != .portrait) || (next == .landscape && !scene.interfaceOrientation.isLandscape)
        guard force || changed || wrongOrientation else { return }
        if #available(iOS 16.0, *) {
            resolvedWindow?.rootViewController?.setNeedsStatusBarAppearanceUpdate()
            resolvedWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: next)) { _ in }
        } else {
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }

    static func setLandscape(_ enabled: Bool, window: UIWindow?) {
        owner = nil
        apply(enabled ? .landscape : preferredHostMask(), window: window, force: true)
    }

    static func restoreHostOrientation(window: UIWindow? = nil) {
        apply(preferredHostMask(), window: window, force: true)
    }

    private static func activeHostWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes where scene.activationState == .foregroundActive {
            if let key = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first {
                return key
            }
        }
        return scenes.first?.windows.first(where: { $0.isKeyWindow }) ?? scenes.first?.windows.first
    }
}

struct LiveBoardOrientationLock: UIViewRepresentable {
    let mask: UIInterfaceOrientationMask
    final class WindowObserver: UIView {
        let token = UUID()
        var requestedMask: UIInterfaceOrientationMask = LiveBoardOrientation.preferredHostMask()
        var applied = false
        private var resumeObserver: NSObjectProtocol?

        override init(frame: CGRect) {
            super.init(frame: frame)
            resumeObserver = NotificationCenter.default.addObserver(forName: Notification.Name("LiveBoardResumeController"), object: nil, queue: .main) { [weak self] _ in
                self?.apply(force: true)
            }
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            if let resumeObserver {
                NotificationCenter.default.removeObserver(resumeObserver)
            }
        }

        func apply(force: Bool = false) {
            guard window != nil else { return }
            applied = true
            LiveBoardOrientation.owner = token
            LiveBoardOrientation.apply(requestedMask, window: window, force: force)
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            applied = false
            apply()
        }
    }
    func makeUIView(context: Context) -> WindowObserver {
        let view = WindowObserver(frame: .zero)
        view.requestedMask = mask
        return view
    }
    func updateUIView(_ view: WindowObserver, context: Context) {
        if view.requestedMask != mask { view.applied = false }
        view.requestedMask = mask
        if !view.applied { DispatchQueue.main.async { [weak view] in view?.apply() } }
    }
    static func dismantleUIView(_ view: WindowObserver, coordinator: ()) {
        guard LiveBoardOrientation.owner == view.token else { return }
        LiveBoardOrientation.owner = nil
        LiveBoardOrientation.apply(LiveBoardOrientation.preferredHostMask(), window: view.window, force: true)
    }
}
struct LiveBoardLandscapeLock: View {
    let enabled: Bool
    var body: some View { LiveBoardOrientationLock(mask: enabled ? .landscape : .allButUpsideDown) }
}
