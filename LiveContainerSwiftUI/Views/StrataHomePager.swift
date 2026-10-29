import SwiftUI
import UIKit

/// Progress goes only to the backdrop/dock, not through every app icon on each frame.
final class StrataHomePagerMotion: ObservableObject {
    @Published var position: CGFloat = 1
    var scrub: ((CGFloat, Bool) -> Void)?
}
struct StrataHomePager: UIViewControllerRepresentable {
    let pages: [AnyView]
    @Binding var selection: Int
    let motion: StrataHomePagerMotion
    var scrollingEnabled: Bool = true
    var reduceMotion: Bool
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ vc: Controller, context: Context) {
        vc.loadViewIfNeeded(); vc.scroll.isScrollEnabled = scrollingEnabled
        vc.selected = { selection = $0 }
        vc.motion = motion
        vc.update(pages, selected: selection, animate: !reduceMotion)
        motion.scrub = { [weak vc] fraction, finished in vc?.scrub(fraction, finished: finished) }
    }
    final class Controller: UIViewController, UIScrollViewDelegate {
        let scroll = UIScrollView()
        var childrenViews: [UIHostingController<AnyView>] = []
        var selected: ((Int) -> Void)?
        weak var motion: StrataHomePagerMotion?
        var target = 1
        var laidOutWidth: CGFloat = 0
        var scrubbing = false
        override func loadView() {
            view = UIView(); view.backgroundColor = .clear
            scroll.backgroundColor = .clear; scroll.isPagingEnabled = true; scroll.delegate = self
            scroll.contentInsetAdjustmentBehavior = .never; scroll.showsHorizontalScrollIndicator = false
            scroll.showsVerticalScrollIndicator = false; scroll.isDirectionalLockEnabled = true
            scroll.scrollsToTop = false; scroll.decelerationRate = .fast
            view.addSubview(scroll)
        }
        func update(_ pages: [AnyView], selected: Int, animate: Bool) {
            loadViewIfNeeded()
            while childrenViews.count > pages.count {
                let child = childrenViews.removeLast(); child.willMove(toParent: nil); child.view.removeFromSuperview(); child.removeFromParent()
            }
            for (index, page) in pages.enumerated() {
                if index < childrenViews.count { childrenViews[index].rootView = page }
                else {
                    let child = UIHostingController(rootView: page)
                    if #available(iOS 16.4, *) { child.safeAreaRegions = [] }
                    child.view.backgroundColor = .clear; addChild(child); scroll.addSubview(child.view); child.didMove(toParent: self)
                    childrenViews.append(child)
                }
            }
            let next = min(max(0, selected), max(0, pages.count - 1))
            if next != target && !scroll.isDragging && !scroll.isDecelerating && !scrubbing {
                target = next
                if scroll.bounds.width > 0 { scroll.setContentOffset(CGPoint(x: CGFloat(next) * scroll.bounds.width, y: 0), animated: animate) }
            }
            view.setNeedsLayout()
        }
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            scroll.frame = view.bounds
            let width = view.bounds.width
            scroll.contentSize = CGSize(width: width * CGFloat(childrenViews.count), height: view.bounds.height)
            for (index, child) in childrenViews.enumerated() { child.view.frame = CGRect(x: CGFloat(index) * width, y: 0, width: width, height: view.bounds.height) }
            if width != laidOutWidth { laidOutWidth = width; scroll.contentOffset = CGPoint(x: CGFloat(target) * width, y: 0) }
        }
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard scrollView.bounds.width > 0 else { return }
            let position = scrollView.contentOffset.x / scrollView.bounds.width
            if abs((motion?.position ?? -100) - position) > 0.0001 { motion?.position = position }
        }
        func settle() {
            guard scroll.bounds.width > 0 else { return }
            target = min(max(0, Int((scroll.contentOffset.x / scroll.bounds.width).rounded())), max(0, childrenViews.count - 1))
            selected?(target)
        }
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { settle() }
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) { if !decelerate { settle() } }
        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { settle() }
        func scrub(_ fraction: CGFloat, finished: Bool) {
            scrubbing = !finished
            let bounded = min(max(0, fraction), CGFloat(max(0, childrenViews.count - 1)))
            scroll.setContentOffset(CGPoint(x: bounded * scroll.bounds.width, y: 0), animated: false)
            if finished { target = Int(bounded.rounded()); selected?(target); scroll.setContentOffset(CGPoint(x: CGFloat(target) * scroll.bounds.width, y: 0), animated: true) }
        }
    }
}
struct StrataPagingBackdrop: View {
    @ObservedObject var motion: StrataHomePagerMotion
    let count: Int
    let sharp: AnyView
    let blurred: AnyView
    var body: some View { ZStack { sharp; blurred.blur(radius: 18).opacity(Double(min(1, max(0, motion.position - CGFloat(count))))) }.allowsHitTesting(false) }
}
struct StrataPagingDock: View {
    @ObservedObject var motion: StrataHomePagerMotion
    let count: Int
    let width: CGFloat
    let content: AnyView
    var body: some View {
        let right = min(1, max(0, motion.position - CGFloat(count)))
        let left = min(1, max(0, 1 - motion.position))
        content.offset(x: (left - right) * width)
            .opacity(Double(1 - max(left, right)))
            .allowsHitTesting(left < 0.01 && right < 0.01)
            .accessibilityHidden(left > 0.01 || right > 0.01)
    }
}

struct StrataHomePageDot: View {
    @ObservedObject var motion: StrataHomePagerMotion
    let page: Int
    var body: some View { Circle().fill(.white.opacity(Int(motion.position.rounded()) == page ? 1 : 0.35)).frame(width: 6, height: 6) }
}
