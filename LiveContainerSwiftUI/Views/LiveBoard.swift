import SwiftUI

private enum LiveBoardMode: String, CaseIterable, Identifiable {
    case ios, cinematic, bigPicture
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ios: return "iOS Home"
        case .cinematic: return "Cinematic"
        case .bigPicture: return "Big Picture"
        }
    }
    var symbol: String {
        switch self {
        case .ios: return "square.grid.3x3.fill"
        case .cinematic: return "rectangle.stack.fill"
        case .bigPicture: return "gamecontroller.fill"
        }
    }
    var detail: String {
        switch self {
        case .ios: return "A familiar, compact app grid."
        case .cinematic: return "A cinematic carousel with controller navigation."
        case .bigPicture: return "A cover library with controller navigation."
        }
    }
}

// The existing list stays mounted to retain install, deep-link and JIT delegates.
struct LiveBoardRootView: View {
    @EnvironmentObject private var sharedModel: SharedModel
    @AppStorage("LiveBoardMode", store: LCUtils.appGroupUserDefault) private var mode = "ios"
    @State private var interfacePresented = false
    @State private var destinationPresented = false

    var body: some View {
        LCAppListView(openInterface: { interfacePresented = true })
        .preferredColorScheme(.dark)
        .sheet(isPresented: $interfacePresented, onDismiss: { NotificationCenter.default.post(name: LiveBoardControllerInput.resumeNotification, object: nil) }) {
            NavigationView {
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(LiveBoardMode.allCases) { option in
                            Button { mode = option.rawValue } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: option.symbol).font(.title).frame(width: 48)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(option.title).font(.headline)
                                        Text(option.detail).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: mode == option.rawValue ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(.blue)
                                }.padding(20)
                                    .background(Color.white.opacity(mode == option.rawValue ? 0.12 : 0.05))
                                    .clipShape(RoundedRectangle(cornerRadius: 24))
                            }.buttonStyle(.plain)
                                .accessibilityAddTraits(mode == option.rawValue ? .isSelected : [])
                        }
                        StrataCreditsButton(location: "interface.about").padding(18).liveBoardGlass(radius: 20)
                    }.padding()
                }
                .navigationTitle("Interface")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { interfacePresented = false } } }
            }.navigationViewStyle(.stack)
        }
        .sheet(isPresented: $destinationPresented, onDismiss: { sharedModel.selectedTab = .apps; NotificationCenter.default.post(name: LiveBoardControllerInput.resumeNotification, object: nil) }) {
            VStack(spacing: 0) {
                HStack { Spacer(); Button("Done") { destinationPresented = false }.padding() }
                switch sharedModel.selectedTab {
                case .sources: LCSourcesView()
                case .tweaks: LCTweaksView()
                case .settings: LCSettingsView()
                case .apps: EmptyView()
                }
            }
        }
        .onChange(of: sharedModel.selectedTab) { tab in
            if tab != .apps { NotificationCenter.default.post(name: LiveBoardControllerInput.pauseNotification, object: nil) }
            if tab == .apps {
                destinationPresented = false
            } else {
                destinationPresented = true
            }
        }
    }

}
