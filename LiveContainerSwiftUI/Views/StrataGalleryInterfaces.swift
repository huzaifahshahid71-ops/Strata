import SwiftUI

/// Additional controller-first launcher interfaces. They share one engine (selection, controller, sounds,
/// universal categories, shared order, launch options, artwork) and differ only in layout.
/// Artwork is reused from the existing interfaces: backgrounds from Cinematic/Big Picture, posters from
/// Big Picture, square covers from Switchboard.
enum StrataGalleryStyle: String, CaseIterable {
    case shelf, arcade
    var isGrid: Bool { true }
}

struct StrataGalleryScreen: View {
    let style: StrataGalleryStyle
    let apps: [LCAppModel]
    let launch: (LCAppModel) -> Void
    let manage: (LCAppModel) -> Void
    let openInterface: () -> Void
    let openManagement: () -> Void
    var launchWithJIT: ((LCAppModel) -> Void)? = nil
    var launchMultitask: ((LCAppModel) -> Void)? = nil
    var launchInGameMode: ((LCAppModel) -> Void)? = nil
    var launchWithMetalHUD: ((LCAppModel) -> Void)? = nil

    @StateObject private var controller = LiveBoardControllerInput()
    @StateObject private var artwork = LiveBoardArtworkStore()
    @StateObject private var audio = LiveBoardNavigationAudio()
    @ObservedObject private var customization = LiveBoardAppCustomization.shared
    @AppStorage("LiveBoardModeLibraries", store: LCUtils.appGroupUserDefault) private var savedLibrary = "{}"
    @AppStorage(LiveBoardSharedCategories.enabledKey, store: LCUtils.appGroupUserDefault) private var universalCategories = true
    @AppStorage("LiveBoardConsoleSounds", store: LCUtils.appGroupUserDefault) private var sounds = true
    @AppStorage("LiveBoardFavorites", store: LCUtils.appGroupUserDefault) private var favorites = "[]"
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedKey = ""
    @State private var category: String?
    @State private var gridColumns = 1
    @State private var editingLibrary = false
    @State private var newCategory = ""
    @State private var visible = false
    @State private var busy = false
    @State private var details = false
    @State private var detailsIndex = 0
    @State private var picking: ArtRequest?
    @State private var artworkError: String?
    @State private var shownBackground: Background?
    @State private var lastGradient: [Color] = [Color(white: 0.16), Color(white: 0.06)]

    private struct ArtRequest: Identifiable { let key: String; let kind: LiveBoardArtworkStore.Kind; let mode: String; var id: String { key + kind.rawValue + mode } }
    private struct Background: Equatable { let id: String; let image: UIImage; static func == (l: Self, r: Self) -> Bool { l.id == r.id } }
    private struct Action { let title: String; let symbol: String; let run: () -> Void }

    private var libraries: [String: LiveBoardModeLibrary] { LiveBoardLibraryCache.decode(savedLibrary) }
    private var library: LiveBoardModeLibrary { _ = universalCategories; return LiveBoardSharedCategories.library(libraries, mode: style.rawValue) }
    private func update(_ change: (inout LiveBoardModeLibrary) -> Void) {
        var all = libraries; var state = library; change(&state); LiveBoardSharedCategories.store(state, mode: style.rawValue, into: &all)
        if let data = try? JSONEncoder().encode(all), let value = String(data: data, encoding: .utf8) { savedLibrary = value }
    }
    private var filtered: [LCAppModel] {
        let state = library
        return apps.filter { !state.hidden.contains(liveBoardAppKey($0)) && (category == nil || state.assignments[liveBoardAppKey($0)] == category) }
    }
    private var selected: LCAppModel? { filtered.first { liveBoardAppKey($0) == selectedKey } ?? filtered.first }
    private var selectedIndex: Int { filtered.firstIndex { liveBoardAppKey($0) == selectedKey } ?? 0 }
    private func categoryName(_ app: LCAppModel) -> String { library.assignments[liveBoardAppKey(app)] ?? "App" }
    private var favoriteKeys: [String] { (try? JSONDecoder().decode([String].self, from: Data(favorites.utf8))) ?? [] }

    // MARK: Artwork reuse
    private func art(_ app: LCAppModel, _ kind: LiveBoardArtworkStore.Kind, square: Bool = false) -> UIImage? {
        let key = liveBoardAppKey(app)
        // Square tiles only take square (Switchboard) covers; wide covers would be cropped to their middle.
        let modes: [String] = kind == .background ? ["cinematic", "bigPicture"] : kind == .portrait ? ["bigPicture"] : square ? ["switchboard"] : ["bigPicture", "cinematic", "switchboard"]
        for mode in modes { if let image = artwork.image(for: key, kind: kind, mode: mode) { return image } }
        return nil
    }
    /// nil while assigned artwork is still decoding, so the previous background stays on screen.
    private func resolveBackground() -> Background? {
        guard let app = selected else { return nil }
        let key = liveBoardAppKey(app)
        for (kind, modes) in [(LiveBoardArtworkStore.Kind.background, ["cinematic", "bigPicture"]), (.cover, ["bigPicture", "cinematic"])] {
            for mode in modes { if let image = artwork.image(for: key, kind: kind, mode: mode) { return Background(id: "art:\(key):\(ObjectIdentifier(image).hashValue)", image: image) } }
            if modes.contains(where: { artwork.hasArtwork(for: key, kind: kind, mode: $0) }) { return nil }
        }
        if let image = LiveBoardIconStore.background(app, dark: false) { return Background(id: "icon:\(key)", image: image) }
        return nil
    }
    private func prefetch() {
        let items = filtered; guard !items.isEmpty else { return }
        let index = selectedIndex, radius = style.isGrid ? gridColumns : 3
        let keys = (max(0, index - radius)...min(items.count - 1, index + radius)).map { liveBoardAppKey(items[$0]) }
        artwork.prefetch(keys, kinds: [.portrait, .cover], mode: "bigPicture")
        let near = (max(0, index - 1)...min(items.count - 1, index + 1)).map { liveBoardAppKey(items[$0]) }
        artwork.prefetch(near, kinds: [.background], mode: "cinematic")
        artwork.prefetch(keys, kinds: [.cover], mode: "switchboard")
    }

    // MARK: Body
    var body: some View {
        GeometryReader { geo in
            ZStack {
                switch style {
                case .shelf: shelf(geo)
                case .arcade: arcade(geo)
                }
                if details, let app = selected { detailsPanel(app, height: geo.size.height) }
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .background(LiveBoardOrientationLock(mask: .landscape))
        .onAppear { visible = true; if !filtered.contains(where: { liveBoardAppKey($0) == selectedKey }) { selectedKey = filtered.first.map(liveBoardAppKey) ?? "" }; prefetch(); bind() }
        .onDisappear { visible = false; controller.stop(); audio.stop() }
        .onChange(of: selectedKey) { _ in if sounds && phase == .active { audio.play() }; prefetch() }
        .onChange(of: filtered.map(liveBoardAppKey)) { keys in if !keys.contains(selectedKey) { selectedKey = keys.first ?? "" } }
        .onChange(of: phase) { value in if value == .active { busy = false; bind() } else { controller.stop() } }
        .onReceive(NotificationCenter.default.publisher(for: LiveBoardControllerInput.pauseNotification)) { _ in controller.stop() }
        .onReceive(NotificationCenter.default.publisher(for: LiveBoardControllerInput.resumeNotification)) { _ in busy = false; bind() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in artwork.reloadFromDisk() }
        .sheet(item: $picking, onDismiss: bind) { request in
            LiveBoardWallpaperPicker { image in
                if let image { do { try artwork.save(image, for: request.key, kind: request.kind, mode: request.mode) } catch { artworkError = error.localizedDescription } }
                picking = nil
            }
        }
        .sheet(isPresented: $editingLibrary, onDismiss: bind) { librarySheet }
        .alert("Artwork", isPresented: Binding(get: { artworkError != nil }, set: { if !$0 { artworkError = nil } })) { Button("OK") { artworkError = nil } } message: { Text(artworkError ?? "") }
    }

    // MARK: Shared pieces
    private func backdrop(_ background: Background?, size: CGSize) -> some View {
        LiveBoardCrossfadeImage(image: background?.image, id: background?.id ?? "", animated: !reduceMotion)
            .frame(width: size.width, height: size.height).clipped().ignoresSafeArea()
    }
    private func tileImage(_ app: LCAppModel, kind: LiveBoardArtworkStore.Kind, width: CGFloat, height: CGFloat, radius: CGFloat, iconFill: Bool = false) -> some View {
        ZStack {
            Color(white: 0.16)
            if let image = art(app, kind, square: abs(width - height) < 1) { Image(uiImage: image).resizable().scaledToFill() }
            else if iconFill { LiveBoardIconImage(app: app, dark: false).scaledToFill() }
            else { LiveBoardIconImage(app: app, dark: false).scaledToFit().padding(min(width, height) * 0.14) }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
    private func tileButton<Label: View>(_ app: LCAppModel, @ViewBuilder label: () -> Label) -> some View {
        let key = liveBoardAppKey(app)
        return Button { if selectedKey == key { activate(app) } else { selectedKey = key } } label: { label() }
            .buttonStyle(.plain).id(key)
            .accessibilityLabel(customization.name(app))
            .accessibilityIdentifier("gallery.tile." + key)
            .accessibilityAddTraits(key == selectedKey ? .isSelected : [])
            .strataReorderable(key, all: apps)
            .contextMenu {
                ForEach(Array(actions(app, arrange: false).enumerated()), id: \.offset) { _, action in Button(action.title, systemImage: action.symbol, action: action.run) }
                StrataArrangeMenus(app: app, visible: filtered, all: apps, categories: library.categories, current: library.assignments[key]) { value in update { $0.assignments[key] = value } }
            }
    }
    private func clock(_ font: Font = .headline) -> some View {
        HStack(spacing: 10) {
            Text(Date(), style: .time).monospacedDigit()
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
        }.font(font)
    }
    private func categoryTabs(selectedStyle: Bool = false) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: selectedStyle ? 8 : 20) {
                ForEach([nil] + library.visibleCategories(apps).map { Optional($0) }, id: \.self) { value in
                    let active = category == value
                    Button { category = value } label: {
                        Text(value ?? "All").font(.subheadline.weight(.semibold))
                            .padding(.horizontal, selectedStyle ? 14 : 0).padding(.vertical, selectedStyle ? 6 : 4)
                            .background { if selectedStyle && active { Capsule().fill(.white) } }
                            .foregroundStyle(selectedStyle && active ? Color.black : .white.opacity(active ? 1 : 0.6))
                            .overlay(alignment: .bottom) { if !selectedStyle && active { Capsule().fill(.white).frame(height: 2).offset(y: 4) } }
                    }.buttonStyle(.plain)
                }
            }.padding(.vertical, 4)
        }
    }
    private var toolbarButtons: some View {
        HStack(spacing: 16) {
            Button { controller.stop(); editingLibrary = true } label: { Image(systemName: "tag") }.accessibilityLabel("Categories and hidden apps")
            Button { controller.stop(); openManagement() } label: { Image(systemName: "square.grid.2x2") }.accessibilityLabel("Manage apps")
            Button { controller.stop(); openInterface() } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Interface")
        }.buttonStyle(.plain).font(.headline)
    }
    private var hints: some View {
        HStack(spacing: 18) {
            if controller.connected {
                Label("Play", systemImage: controller.confirmSymbol)
                Label("Options", systemImage: controller.detailsSymbol)
                Label("Interface", systemImage: "b.circle")
            } else { Text("Tap to select · tap again to play") }
        }.font(.footnote).foregroundStyle(.white.opacity(0.75))
    }
    private func playButtons(_ app: LCAppModel, compact: Bool = false) -> some View {
        HStack(spacing: 10) {
            Button { activate(app) } label: {
                Label(categoryName(app) == "Games" || categoryName(app) == "Ports" ? "Play" : "Open", systemImage: "play.fill")
                    .font(.system(size: compact ? 15 : 17, weight: .semibold)).padding(.horizontal, compact ? 16 : 22).frame(height: compact ? 38 : 46)
                    .background(Capsule().fill(Color.white)).foregroundStyle(.black)
            }.disabled(busy).accessibilityIdentifier("gallery.play")
            Button { showDetails() } label: {
                Image(systemName: "ellipsis").font(.system(size: 18, weight: .bold)).frame(width: compact ? 38 : 46, height: compact ? 38 : 46)
                    .background(Circle().fill(Color.white.opacity(0.18)))
            }.accessibilityLabel("Options").accessibilityIdentifier("gallery.options")
        }.buttonStyle(.plain)
    }
    private func titleBlock(_ app: LCAppModel, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(categoryName(app).uppercased()).font(.system(size: 10, weight: .bold)).tracking(1.5)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
                if favoriteKeys.contains(liveBoardAppKey(app)) { Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow) }
            }
            Text(customization.name(app)).font(.system(size: size, weight: .bold)).lineLimit(2).minimumScaleFactor(0.5)
                .shadow(color: .black.opacity(0.5), radius: 10)
                .accessibilityIdentifier("gallery.selected.title")
        }
    }

    // MARK: Background that follows the selected game's colours
    private var gradientColors: [Color]? { selected.flatMap { StrataGameColors.gradient(artwork, app: $0) } }
    private func gameGradient() -> some View {
        let colors = gradientColors ?? lastGradient
        return ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: colors.description)
        .onChange(of: gradientColors?.description) { _ in if let next = gradientColors { lastGradient = next } }
        .onAppear { if let next = gradientColors { lastGradient = next } }
    }
    private func header(_ geo: GeometryProxy, tabs: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if let app = selected {
                VStack(alignment: .leading, spacing: 2) {
                    Text(customization.name(app)).font(.title3.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7).accessibilityIdentifier("gallery.selected.title")
                    Text(categoryName(app) + " · \(selectedIndex + 1) of \(filtered.count)").font(.caption).foregroundStyle(.white.opacity(0.7))
                }
            }
            if tabs { categoryTabs(selectedStyle: true).frame(maxWidth: geo.size.width * 0.4) }
            Spacer(minLength: 8)
            if let app = selected { playButtons(app, compact: true) }
            toolbarButtons.padding(.leading, 6)
            clock(.subheadline).padding(.leading, 6)
        }
    }
    /// Eight columns across the whole screen width, including the landscape safe-area margins.
    private static let gridColumnCount = 8
    private func cellWidth(_ geo: GeometryProxy, spacing: CGFloat) -> CGFloat {
        let fullWidth = geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing
        return max(40, (fullWidth - 32 - spacing * CGFloat(Self.gridColumnCount - 1)) / CGFloat(Self.gridColumnCount))
    }
    private func fullGrid<Cell: View>(_ geo: GeometryProxy, spacing: CGFloat, @ViewBuilder cell: @escaping (LCAppModel, Bool) -> Cell) -> some View {
        let fullWidth = geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing
        let width = cellWidth(geo, spacing: spacing)
        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(width), spacing: spacing), count: Self.gridColumnCount), alignment: .center, spacing: spacing + 4) {
                    ForEach(filtered, id: \.self) { app in
                        tileButton(app) { cell(app, liveBoardAppKey(app) == liveBoardAppKey(selected ?? app)) }
                    }
                }
                .padding(.vertical, 16)
                .frame(width: fullWidth)
            }
            .frame(width: fullWidth)
            .ignoresSafeArea(.container, edges: .horizontal)
            .onChange(of: selectedKey) { key in withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { proxy.scrollTo(key, anchor: .center) } }
            .onAppear { gridColumns = Self.gridColumnCount }
        }
    }

    // MARK: Shelf — full-screen poster grid, no categories
    private func shelf(_ geo: GeometryProxy) -> some View {
        let posterWidth = cellWidth(geo, spacing: 12)
        let posterHeight = posterWidth / 0.68
        return ZStack(alignment: .topLeading) {
            gameGradient()
            VStack(alignment: .leading, spacing: 6) {
                header(geo, tabs: false).padding(.top, 8)
                fullGrid(geo, spacing: 12) { app, isSelected in
                    // One fixed, soft shadow for every poster (animating its radius looked jittery);
                    // the selected poster is marked by its frame and scale only.
                    tileImage(app, kind: .portrait, width: posterWidth, height: posterHeight, radius: 6)
                        .compositingGroup()
                        .shadow(color: .black.opacity(0.35), radius: 5, x: 0, y: 3)
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white, lineWidth: isSelected ? 3 : 0).padding(-3))
                        .scaleEffect(isSelected ? 1.05 : 1)
                        .zIndex(isSelected ? 1 : 0)
                        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.85), value: isSelected)
                }
                if controller.connected { hints.padding(.bottom, 4) }
            }
        }
    }

    // MARK: Arcade — full-screen grid of rounded square tiles
    private func arcade(_ geo: GeometryProxy) -> some View {
        let cell = cellWidth(geo, spacing: 14)
        return ZStack(alignment: .topLeading) {
            gameGradient()
            VStack(alignment: .leading, spacing: 6) {
                header(geo, tabs: true).padding(.top, 8)
                fullGrid(geo, spacing: 14) { app, isSelected in
                    tileImage(app, kind: .cover, width: cell, height: cell, radius: cell * 0.22, iconFill: true)
                        .overlay(RoundedRectangle(cornerRadius: cell * 0.22 + 4, style: .continuous).strokeBorder(.white, lineWidth: isSelected ? 3 : 0).padding(-5))
                        .scaleEffect(isSelected ? 1.08 : 1)
                        .shadow(color: .black.opacity(0.35), radius: isSelected ? 10 : 4, y: 3)
                        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
                }
                if controller.connected { hints.padding(.bottom, 4) }
            }
        }
    }

    // MARK: Options panel (shared)
    private func actions(_ app: LCAppModel, arrange: Bool = true) -> [Action] {
        let key = liveBoardAppKey(app)
        var list = [Action(title: "Play", symbol: "play.fill") { details = false; activate(app) }]
        if !(app.appInfo is StrataPhoneAppInfo) && !(app.appInfo is BuiltInSideStoreAppInfo) {
            if let launchWithJIT { list.append(Action(title: "Launch with JIT", symbol: "bolt.fill") { details = false; controller.stop(); launchWithJIT(app) }) }
            if let launchInGameMode { list.append(Action(title: "Request Game Mode", symbol: "gamecontroller.fill") { details = false; controller.stop(); launchInGameMode(app) }) }
            if let launchMultitask { list.append(Action(title: "Multitask", symbol: "rectangle.on.rectangle") { details = false; controller.stop(); launchMultitask(app) }) }
            if let launchWithMetalHUD { list.append(Action(title: "Launch with Metal HUD", symbol: "gauge.with.dots.needle.67percent") { details = false; controller.stop(); launchWithMetalHUD(app) }) }
        }
        list.append(Action(title: favoriteKeys.contains(key) ? "Remove favorite" : "Add favorite", symbol: "star") { toggleFavorite(key) })
        list.append(Action(title: "App settings", symbol: "gearshape") { details = false; controller.stop(); manage(app) })
        list.append(Action(title: "Choose background", symbol: "photo") { details = false; controller.stop(); picking = ArtRequest(key: key, kind: .background, mode: "cinematic") })
        list.append(Action(title: style == .shelf ? "Choose poster" : "Choose cover", symbol: "rectangle.portrait") { details = false; controller.stop(); picking = style == .shelf ? ArtRequest(key: key, kind: .portrait, mode: "bigPicture") : ArtRequest(key: key, kind: .cover, mode: "switchboard") })
        if arrange {
        list.append(Action(title: "Move Left", symbol: "arrow.left") { StrataLauncherOrder.move(app, by: -1, visible: filtered, all: apps) })
        list.append(Action(title: "Move Right", symbol: "arrow.right") { StrataLauncherOrder.move(app, by: 1, visible: filtered, all: apps) })
        list.append(Action(title: "Move to Start", symbol: "arrow.left.to.line") { StrataLauncherOrder.move(app, by: Int.min, visible: filtered, all: apps) })
        for value in library.categories where library.assignments[key] != value {
            list.append(Action(title: "Move to \(value)", symbol: "tag") { update { $0.assignments[key] = value } })
        }
        }
        list.append(Action(title: "Hide", symbol: "eye.slash") { details = false; update { _ = $0.hidden.insert(key) } })
        return list
    }
    private func detailsPanel(_ app: LCAppModel, height: CGFloat) -> some View {
        let list = actions(app)
        return ZStack(alignment: .trailing) {
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { details = false }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    LiveBoardIconImage(app: app, dark: false).frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading) {
                        Text(customization.name(app)).font(.headline).lineLimit(1)
                        Text(categoryName(app) + (app.appInfo.version().map { " · " + $0 } ?? "")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(Array(list.enumerated()), id: \.offset) { index, action in
                                Button(action: action.run) {
                                    HStack(spacing: 10) { Image(systemName: action.symbol).frame(width: 24); Text(action.title); Spacer(minLength: 0) }
                                        .padding(10).frame(minHeight: 40)
                                        .background(detailsIndex == index ? .white.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 10))
                                }.buttonStyle(.plain).id(index)
                            }
                        }
                    }.onChange(of: detailsIndex) { proxy.scrollTo($0) }
                }
                Button("Close") { details = false }.frame(maxWidth: .infinity, minHeight: 36)
            }
            .padding(16).frame(width: 330).frame(maxHeight: max(160, height - 24))
            .liveBoardGlass(radius: 24, interactive: false).padding(.trailing, 16)
        }.accessibilityAddTraits(.isModal)
    }
    private var librarySheet: some View {
        NavigationView {
            Form {
                Section("Categories") {
                    HStack { TextField("New category", text: $newCategory); Button("Add") { update { _ = $0.addCategory(newCategory) }; newCategory = "" }.disabled(newCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                    ForEach(library.categories, id: \.self) { value in HStack { Text(value); Spacer(); Button("Remove") { update { $0.removeCategory(value) }; if category == value { category = nil } } } }
                }
                Section {
                    Toggle("Same categories in every interface", isOn: Binding(get: { universalCategories }, set: { LiveBoardSharedCategories.setEnabled($0); universalCategories = $0 }))
                    Toggle("Navigation sounds", isOn: $sounds)
                }
                Section("Hidden apps") {
                    ForEach(apps.filter { library.hidden.contains(liveBoardAppKey($0)) }, id: \.self) { app in
                        Button("Show \(customization.name(app))") { update { _ = $0.hidden.remove(liveBoardAppKey(app)) } }
                    }
                }
            }.navigationTitle("Library")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { editingLibrary = false } } }
        }.navigationViewStyle(.stack)
    }

    // MARK: Behaviour
    private func toggleFavorite(_ key: String) {
        var keys = favoriteKeys
        if keys.contains(key) { keys.removeAll { $0 == key } } else { keys.append(key) }
        if let data = try? JSONEncoder().encode(keys), let text = String(data: data, encoding: .utf8) { favorites = text }
    }
    private func showDetails() { guard selected != nil else { return }; detailsIndex = 0; details = true }
    private func activate(_ app: LCAppModel) {
        guard !busy else { return }; busy = true; controller.stop(); audio.stop(); launch(app)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { busy = false }
    }
    private func select(_ index: Int) {
        let items = filtered
        guard items.indices.contains(index) else { return }
        selectedKey = liveBoardAppKey(items[index])
    }
    private func changeCategory(_ delta: Int) {
        guard style != .shelf else { return }
        let all: [String?] = [nil] + library.visibleCategories(apps).map { Optional($0) }
        let current = all.firstIndex(of: category) ?? 0
        category = all[(current + delta + all.count) % all.count]
    }
    private func bind() {
        guard visible, !editingLibrary, picking == nil, !busy else { return }
        controller.onCommand = { command in
            if details {
                let count = selected.map { actions($0).count } ?? 0
                switch command {
                case .up: detailsIndex = max(0, detailsIndex - 1)
                case .down: detailsIndex = min(max(0, count - 1), detailsIndex + 1)
                case .confirm: if let app = selected { let list = actions(app); if list.indices.contains(detailsIndex) { list[detailsIndex].run() } }
                case .back, .details: details = false
                default: break
                }
                return
            }
            let index = selectedIndex
            let step = style.isGrid ? max(1, gridColumns) : 1
            switch command {
            case .left: select(index - 1)
            case .right: select(index + 1)
            case .up: if style.isGrid { select(index - step) }
            case .down: if style.isGrid { select(min(filtered.count - 1, index + step)) }
            case .confirm: if let app = selected { activate(app) }
            case .details: showDetails()
            case .favorite: if let app = selected { toggleFavorite(liveBoardAppKey(app)) }
            case .previousSection: changeCategory(-1)
            case .nextSection: changeCategory(1)
            case .back: controller.stop(); openInterface()
            }
        }
        controller.start()
    }
}
