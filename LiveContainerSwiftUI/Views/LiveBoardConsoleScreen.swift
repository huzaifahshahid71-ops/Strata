import SwiftUI

struct LiveBoardConsoleScreen: View {
    let apps: [LCAppModel]
    let mode: String
    let launch: (LCAppModel) async -> Void
    let manage: (LCAppModel) -> Void
    let openInterface: () -> Void
    let openManagement: () -> Void
    var launchWithJIT: ((LCAppModel) async -> Void)? = nil
    var launchInGameMode: ((LCAppModel) async -> Void)? = nil
    var launchWithMetalHUD: ((LCAppModel) async -> Void)? = nil
    var launchMultitask: ((LCAppModel) async -> Void)? = nil
    @ObservedObject private var appCustomization = LiveBoardAppCustomization.shared
    @State private var appearanceApp: LiveBoardAppearanceSelection?
    @AppStorage("StrataConsoleLayouts", store: LCUtils.appGroupUserDefault) private var savedConsoleLayouts = "{}"
    @State private var layoutSettings = false
    @State private var movingLaunchButton = false
    @State private var dragOrigin: CGPoint?
    private var consoleLayout: LiveBoardConsoleLayout { LiveBoardConsoleLayout.decode(savedConsoleLayouts, mode: mode) }
    private func updateConsoleLayout(_ action: (inout LiveBoardConsoleLayout) -> Void) {
        var layout = consoleLayout; action(&layout)
        savedConsoleLayouts = LiveBoardConsoleLayout.save(layout, mode: mode, in: savedConsoleLayouts)
    }
    @State private var jitSetup = false
    @AppStorage("LiveBoardFavorites", store: LCUtils.appGroupUserDefault) private var favorites = "[]"
    @AppStorage("LiveBoardCategories", store: LCUtils.appGroupUserDefault) private var categories = "{}"
    @AppStorage("darkModeIcon", store: LCUtils.appGroupUserDefault) private var darkIcons = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var consoleVisible = false
    @StateObject private var controller = LiveBoardControllerInput()
    @StateObject private var artwork = LiveBoardArtworkStore()
    @AppStorage("LiveBoardModeLibraries", store: LCUtils.appGroupUserDefault) private var modeLibraries = "{}"
    @AppStorage("LiveBoardConsoleSounds", store: LCUtils.appGroupUserDefault) private var sounds = true
    @State private var activeCategory: String?
    @State private var managingCategories = false
    @State private var newCategory = ""
    @StateObject private var audio = LiveBoardNavigationAudio()
    private var libraries: [String: LiveBoardModeLibrary] { (try? JSONDecoder().decode([String: LiveBoardModeLibrary].self, from: Data(modeLibraries.utf8))) ?? [:] }
    private var library: LiveBoardModeLibrary { libraries[mode] ?? LiveBoardModeLibrary() }
    private func updateLibrary(_ action: (inout LiveBoardModeLibrary) -> Void) {
        var all = libraries; var state = library; action(&state); all[mode] = state
        if let data = try? JSONEncoder().encode(all), let text = String(data: data, encoding: .utf8) { modeLibraries = text }
    }
    @State private var navigation = LiveBoardConsoleNavigation()
    @State private var favoritesOnly = false
    @State private var details = false
    @State private var detailsIndex = 0
    @State private var searching = false
    @State private var query = ""
    @State private var launching = false
    @State private var launchReturned = false
    @State private var picker: ArtworkRequest?
    @State private var artworkError: String?

    private struct ArtworkRequest: Identifiable {
        let key: String
        let kind: LiveBoardArtworkStore.Kind
        var id: String { key + kind.rawValue }
    }
    private var favoriteKeys: [String] { (try? JSONDecoder().decode([String].self, from: Data(favorites.utf8))) ?? [] }
    private var visibleApps: [LCAppModel] {
        apps.filter { app in
            let key = liveBoardAppKey(app)
            return !library.hidden.contains(key) && (!favoritesOnly || favoriteKeys.contains(key)) && (activeCategory == nil || library.assignments[key] == activeCategory)
        }
    }
    private var selected: LCAppModel? { visibleApps.indices.contains(navigation.selectedIndex) ? visibleApps[navigation.selectedIndex] : visibleApps.first }
    private var keys: [String] { visibleApps.map(liveBoardAppKey) }
    private var bigPicture: Bool { mode == "bigPicture" }

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            let iconScale = min(CGFloat(consoleLayout.iconScale), max(0.65, (geometry.size.height - 180) / 126))
            ZStack {
                if let app = selected, artwork.image(for: liveBoardAppKey(app), kind: .background, mode: mode) == nil {
                    LiveBoardIconImage(app: app, dark: darkIcons)
                        .frame(width: landscape ? 190 : 148, height: landscape ? 190 : 148)
                        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                        .shadow(color: .black.opacity(0.5), radius: 40)
                        .opacity(0.75)
                        .position(x: geometry.size.width * 0.78, y: geometry.size.height * 0.5)
                        .allowsHitTesting(false)
                }
                VStack(alignment: .leading, spacing: 0) {
                    header(landscape: landscape).padding(.top, 4)
                    categoryTabs.padding(.bottom, 4)
                    if !bigPicture { carousel(landscape: landscape, scale: iconScale).padding(.leading, -24 - geometry.safeAreaInsets.leading).padding(.trailing, -24 - geometry.safeAreaInsets.trailing).padding(.top, 4) }
                    hero(landscape: landscape).frame(maxHeight: .infinity, alignment: .bottomLeading)
                    if bigPicture { carousel(landscape: landscape, scale: iconScale).padding(.leading, -24 - geometry.safeAreaInsets.leading).padding(.trailing, -24 - geometry.safeAreaInsets.trailing).padding(.top, 8) }
                    footer.padding(.top, landscape ? 8 : 22).padding(.bottom, 8)
                }
                .frame(width: max(0, geometry.size.width - 48), height: geometry.size.height)
                .padding(.horizontal, 24)
                .blur(radius: details ? 12 : 0)
                .allowsHitTesting(!details)
                .opacity(landscape ? 1 : 0)
                .accessibilityHidden(details || !landscape)
                if !landscape {
                    VStack(spacing: 16) {
                        Image(systemName: "iphone.gen3.radiowaves.left.and.right").font(.largeTitle)
                        Text("Turn your iPhone sideways").font(.headline)
                        Button("Interface") { controller.stop(); openInterface() }.buttonStyle(.bordered)
                    }
                }
                if landscape, let app = selected {
                    let scale = min(CGFloat(consoleLayout.launchScale), geometry.size.width / 240, geometry.size.height / 54)
                    let width = 240 * scale
                    let height = 54 * scale
                    let travelX = max(1, geometry.size.width - width)
                    let travelY = max(1, geometry.size.height - height)
                    launchControls(app)
                        .frame(width: 240, height: 54)
                        .scaleEffect(scale)
                        .frame(width: width, height: height)
                        .contentShape(Rectangle())
                        .highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("console.canvas"))
                            .onChanged { value in
                                if dragOrigin == nil { dragOrigin = CGPoint(x: consoleLayout.launchX, y: consoleLayout.launchY) }
                                if let origin = dragOrigin { updateConsoleLayout { $0.launchX = origin.x + value.translation.width / travelX; $0.launchY = origin.y + value.translation.height / travelY } }
                            }.onEnded { _ in dragOrigin = nil }, including: movingLaunchButton ? .all : .none)
                        .position(x: width / 2 + travelX * consoleLayout.launchX, y: height / 2 + travelY * consoleLayout.launchY)
                        .allowsHitTesting(!details)
                    if movingLaunchButton {
                        VStack { HStack { Spacer(); Button { movingLaunchButton = false; bindController() } label: { Image(systemName: "checkmark").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44) }.buttonStyle(.plain).liveBoardGlass(radius: 22).accessibilityLabel("Done moving").accessibilityIdentifier("console.layout.done").padding(8) }; Spacer() }
                    }
                }
                if details, let app = selected { detailsOverlay(app, height: geometry.size.height) }
            }
            .coordinateSpace(name: "console.canvas")
            .foregroundColor(.white)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background {
            GeometryReader { fullScreen in backdrop(size: fullScreen.size) }
                .ignoresSafeArea()
                .accessibilityIdentifier("console.backdrop")
        }
        .background(LiveBoardLandscapeLock(enabled: !launching && !launchReturned))
        .preferredColorScheme(.dark)
        .sheet(isPresented: $layoutSettings, onDismiss: bindController) { consoleLayoutSettings }
        .sheet(item: $appearanceApp, onDismiss: bindController) { app in LiveBoardAppAppearance(app: app.app) }
        .sheet(isPresented: $jitSetup, onDismiss: bindController) { LiveBoardJITSetup() }
        .sheet(isPresented: $managingCategories, onDismiss: bindController) { categoryManager }
        .sheet(isPresented: $searching, onDismiss: bindController) { searchSheet }
        .sheet(item: $picker, onDismiss: bindController) { request in
            LiveBoardWallpaperPicker { image in
                if let image {
                    do { try artwork.save(image, for: request.key, kind: request.kind, mode: mode) }
                    catch { artworkError = error.localizedDescription }
                }
                picker = nil
            }
        }
        .alert("Artwork", isPresented: Binding(get: { artworkError != nil }, set: { if !$0 { artworkError = nil; bindController() } })) {
            Button("OK") { artworkError = nil; bindController() }
        } message: { Text(artworkError ?? "") }
        .onReceive(NotificationCenter.default.publisher(for: LiveBoardControllerInput.pauseNotification)) { _ in controller.stop() }
        .onReceive(NotificationCenter.default.publisher(for: LiveBoardControllerInput.resumeNotification)) { _ in bindController() }
        .onAppear { consoleVisible = true; launchReturned = false; migrateLibrariesIfNeeded(); bindController() }
        .task { await Task.yield(); bindController() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in artwork.reloadFromDisk(); bindController() }
        .onChange(of: navigation.selectedIndex) { _ in if sounds && scenePhase == .active { audio.play() } }
        .onDisappear { consoleVisible = false; controller.stop(); audio.stop() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { bindController() } else { controller.stop() }
        }
        .onChange(of: mode) { _ in activeCategory = nil; favoritesOnly = false; navigation = LiveBoardConsoleNavigation(); bindController() }
        .onChange(of: keys) { _ in navigation.selectedIndex = min(navigation.selectedIndex, max(0, visibleApps.count - 1)) }
    }

    private func backdrop(size: CGSize) -> some View {
        ZStack {
            Color(red: 0.025, green: 0.035, blue: 0.065)
            if let app = selected {
                if let image = artwork.image(for: liveBoardAppKey(app), kind: .background, mode: mode) {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: size.width, height: size.height).clipped()
                } else {
                    if let image = LiveBoardIconStore.background(app, dark: darkIcons) {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: size.width, height: size.height).clipped()
                    }
                }
            }
            LinearGradient(colors: [.black.opacity(0.25), .black.opacity(0.15), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [.black.opacity(0.68), .clear], startPoint: .leading, endPoint: .trailing)
        }.id(selected.map(liveBoardAppKey)).transition(.opacity).frame(width: size.width, height: size.height).clipped()
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: selected.map(liveBoardAppKey))
    }
    private func header(landscape: Bool) -> some View {
        HStack(spacing: landscape ? 18 : 8) {
            ForEach(0..<2, id: \.self) { index in
                Button {
                    favoritesOnly = index == 1
                    activeCategory = nil
                    navigation.selectedIndex = 0
                } label: {
                    Text(index == 0 ? "Library" : "Favorites")
                        .font(.system(size: landscape ? 20 : 18, weight: (activeCategory == nil && favoritesOnly == (index == 1)) ? .semibold : .regular))
                        .foregroundStyle(.white.opacity((activeCategory == nil && favoritesOnly == (index == 1)) ? 1 : 0.5))
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) {
                            if navigation.focus == .header && navigation.headerIndex == index { Capsule().fill(.white).frame(height: 2) }
                        }
                }.accessibilityIdentifier(index == 0 ? "console.library" : "console.favorites")
            }
            Spacer(minLength: 0)
            Button { openSearch() } label: { Image(systemName: "magnifyingglass").frame(width: 36, height: 36) }.accessibilityLabel("Search").accessibilityIdentifier("console.search")
            Button { controller.stop(); openManagement() } label: {
                Image(systemName: "square.grid.2x2").frame(width: 36, height: 36)
                    .overlay(Circle().stroke(navigation.focus == .header && navigation.headerIndex == 2 ? .white : .clear, lineWidth: 2))
            }.accessibilityLabel("Manage apps").accessibilityIdentifier("console.manage")
            Button { controller.stop(); openInterface() } label: {
                Image(systemName: "gearshape").frame(width: 36, height: 36)
                    .overlay(Circle().stroke(navigation.focus == .header && navigation.headerIndex == 3 ? .white : .clear, lineWidth: 2))
            }.accessibilityLabel("Interface").accessibilityIdentifier("console.interface")
        }.buttonStyle(.plain).frame(maxWidth: .infinity).frame(height: 40)
    }
    private func migrateLibrariesIfNeeded() {
        var all = libraries
        let previous = (try? JSONDecoder().decode([String: String].self, from: Data(categories.utf8))) ?? [:]
        var changed = false
        for name in ["cinematic", "bigPicture"] where all[name] == nil {
            var state = LiveBoardModeLibrary(); state.assignments = previous
            for category in previous.values.sorted() where !state.categories.contains(category) { state.categories.append(category) }
            all[name] = state; changed = true
        }
        if changed, let data = try? JSONEncoder().encode(all), let value = String(data: data, encoding: .utf8) { modeLibraries = value }
    }
    private var categoryTabs: some View {
        HStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(library.categories, id: \.self) { name in
                        Button { activeCategory = activeCategory == name ? nil : name; favoritesOnly = false; navigation.selectedIndex = 0 } label: {
                            Text(name).font(.system(size: 13, weight: activeCategory == name ? .bold : .regular)).foregroundStyle(.white.opacity(activeCategory == name ? 1 : 0.55)).padding(.vertical, 6)
                        }.accessibilityIdentifier("console.category." + name)
                    }
                }
            }
            Button { controller.stop(); layoutSettings = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 32, height: 32) }.accessibilityLabel("Customize layout").accessibilityIdentifier("console.layout")
            Button { controller.stop(); jitSetup = true } label: { Image(systemName: "bolt.fill").frame(width: 32, height: 32) }.accessibilityLabel("JIT setup")
            Button { controller.stop(); managingCategories = true } label: { Image(systemName: "tag").overlay(alignment: .bottomTrailing) { Image(systemName: "plus.circle.fill").font(.system(size: 10)).offset(x: 5, y: 5) }.frame(width: 32, height: 32) }.accessibilityLabel("Categories and hidden apps").accessibilityIdentifier("console.categories.manage")
        }.buttonStyle(.plain).frame(height: 28)
    }
    private var categoryManager: some View {
        NavigationView {
            Form {
                Section("Categories for this mode") {
                    HStack { TextField("New category", text: $newCategory).accessibilityIdentifier("console.category.name"); Button("Add") { updateLibrary { _ = $0.addCategory(newCategory) }; newCategory = "" }.accessibilityIdentifier("console.category.add").disabled(newCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                    ForEach(library.categories, id: \.self) { name in
                        HStack { Text(name); Spacer(); Button(role: .destructive) { updateLibrary { $0.removeCategory(name) }; if activeCategory == name { activeCategory = nil } } label: { Image(systemName: "trash") } }
                    }
                }
                Section("Apps in this mode") {
                    ForEach(apps, id: \.self) { app in
                        VStack(alignment: .leading) {
                            Toggle(appCustomization.name(app), isOn: Binding(get: { !library.hidden.contains(liveBoardAppKey(app)) }, set: { show in updateLibrary { if show { $0.hidden.remove(liveBoardAppKey(app)) } else { $0.hidden.insert(liveBoardAppKey(app)) } } }))
                            Picker("Category", selection: Binding(get: { library.assignments[liveBoardAppKey(app)] ?? "" }, set: { name in updateLibrary { $0.assignments[liveBoardAppKey(app)] = name.isEmpty ? nil : name } })) {
                                Text("Uncategorized").tag("")
                                ForEach(library.categories, id: \.self) { Text($0).tag($0) }
                            }
                        }
                    }
                }
                Section { Toggle("Navigation sounds", isOn: $sounds) }
            }.navigationTitle("Categories & visibility")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { managingCategories = false } } }
        }.navigationViewStyle(.stack)
    }
    private func changeSection(_ delta: Int) {
        let sections = ["Library", "Favorites"] + library.categories
        let current = activeCategory.flatMap { sections.firstIndex(of: $0) } ?? (favoritesOnly ? 1 : 0)
        let index = (current + delta + sections.count) % sections.count
        favoritesOnly = index == 1; activeCategory = index >= 2 ? sections[index] : nil; navigation.selectedIndex = 0
    }
    private func carousel(landscape: Bool, scale: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: bigPicture ? 14 : 12) {
                    ForEach(Array(visibleApps.enumerated()), id: \.element) { index, app in
                        let focused = selected == app
                        Button {
                            navigation.selectedIndex = index; navigation.focus = .rail
                        } label: {
                            cover(app, selected: focused, landscape: landscape, scale: scale)
                        }
                        .buttonStyle(.plain)
                        .id(liveBoardAppKey(app))
                        .contextMenu {
                            Button("Request Game Mode", systemImage: "gamecontroller.fill") { navigation.selectedIndex = index; activate(app, gameMode: true) }
                            Button("Launch with JIT", systemImage: "bolt.fill") { navigation.selectedIndex = index; activate(app, forceJIT: true) }
                            if let launchMultitask { Button("Multitask", systemImage: "rectangle.on.rectangle") { Task { await launchMultitask(app) } } }
                            if let launchWithMetalHUD { Button("Launch with Metal HUD", systemImage: "gauge.with.dots.needle.67percent") { Task { await launchWithMetalHUD(app) } } }
                            Button(app.strataSwitcherPinned ? "Unpin from app switcher" : "Pin to app switcher", systemImage: "pin") { app.strataSwitcherPinned.toggle() }
                            Button("App options", systemImage: "ellipsis") { navigation.selectedIndex = index; showDetails() }
                        }
                        .accessibilityLabel(appCustomization.name(app))
                        .accessibilityValue(focused ? "Selected" : "")
                        .accessibilityIdentifier("console.tile.\(liveBoardAppKey(app))")
                        .accessibilityAddTraits(focused ? .isSelected : [])
                    }
                }.padding(5)
            }
            .frame(height: (bigPicture ? (landscape ? 126 : 196) : (landscape ? 116 : 142)) * scale)
            .task(id: selected.map(liveBoardAppKey)) {
                guard let app = selected else { return }
                // Let the newly selected cover's width settle before calculating its scroll position.
                try? await Task.sleep(nanoseconds: 20_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.88)) { proxy.scrollTo(liveBoardAppKey(app), anchor: .center) }
            }
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.018), .init(color: .black, location: 0.982), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
            .accessibilityIdentifier("console.rail")
        }
    }
    private func cover(_ app: LCAppModel, selected: Bool, landscape: Bool, scale: CGFloat) -> some View {
        let h: CGFloat = (bigPicture ? (landscape ? 112 : 180) : (selected ? (landscape ? 106 : 128) : (landscape ? 78 : 88))) * scale
        let w: CGFloat = bigPicture ? (selected ? h * 1.7 : h * 0.68) : h
        return ZStack {
            Color(white: 0.08)
            if let image = artwork.image(for: liveBoardAppKey(app), kind: bigPicture && !selected ? .portrait : .cover, mode: mode) {
                Image(uiImage: image).resizable().scaledToFill().frame(width: w, height: h).clipped()
            } else {
                LiveBoardIconImage(app: app, dark: darkIcons).frame(width: bigPicture ? h * 0.65 : h, height: bigPicture ? h * 0.65 : h)
            }
        }
        .frame(width: w, height: h)
        .clipShape(RoundedRectangle(cornerRadius: bigPicture ? 5 : 18, style: .continuous))
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.86), value: selected)
        .overlay(RoundedRectangle(cornerRadius: bigPicture ? 5 : 18, style: .continuous).strokeBorder(.white.opacity(selected ? 0.9 : 0), lineWidth: selected ? 2 : 0))

    }
    @ViewBuilder private func hero(landscape: Bool) -> some View {
        if let app = selected {
            VStack(alignment: .leading, spacing: landscape ? 4 : 14) {
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    Text(category(app).uppercased()).font(.system(size: 10, weight: .bold)).tracking(1.5)
                        .padding(.horizontal, 8).padding(.vertical, 4).background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                    if favoriteKeys.contains(liveBoardAppKey(app)) { Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow) }
                }
                Text(appCustomization.name(app)).font(.system(size: landscape ? 28 : 38, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
                    .shadow(color: .black.opacity(0.35), radius: 8)
                    .accessibilityIdentifier("console.selected.title")
                if launchReturned {
                    Button("Resume controller navigation") { launchReturned = false; bindController() }.font(.caption).foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: landscape ? 4 : 28)
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Spacer()
                Text(favoritesOnly ? "Your favorites" : "Your library").font(.largeTitle.bold())
                Text(favoritesOnly ? "Add favorites from an app’s options." : "Install your first app to get started.").foregroundStyle(.white.opacity(0.6))
                Button(favoritesOnly ? "All apps" : "Manage apps") {
                    if favoritesOnly { favoritesOnly = false } else { controller.stop(); openManagement() }
                }.buttonStyle(.bordered)
                Spacer()
            }
        }
    }
    private func launchControls(_ app: LCAppModel) -> some View {
        HStack(spacing: 12) {
                    Button { if !movingLaunchButton { activate(app) } } label: {
                        HStack(spacing: 9) {
                            if launching { ProgressView().tint(.white) } else { Image(systemName: "play.fill").font(.system(size: 14)) }
                            Text(category(app) == "Games" ? "Play Game" : "Launch App").font(.system(size: 17, weight: .semibold))
                        }.frame(minWidth: 140, minHeight: 46)
                    }
                    .liveBoardGlass(radius: 23)
                    .overlay(Capsule().stroke(navigation.focus == .launch ? .white : .clear, lineWidth: 2))
                    .disabled(launching || app.isAppRunning || app.isSigningInProgress)
                    .accessibilityIdentifier("console.launch")
                    Button { showDetails() } label: { Image(systemName: "ellipsis").font(.system(size: 22, weight: .semibold)).frame(width: 46, height: 46) }
                        .liveBoardGlass(radius: 23)
                        .overlay(Circle().stroke(navigation.focus == .details ? .white : .clear, lineWidth: 2))
                        .accessibilityLabel("App options").accessibilityIdentifier("console.options")
                }.buttonStyle(.plain).padding(.top, 2)
    }
    private var consoleLayoutSettings: some View {
        NavigationView {
            Form {
                Section("Cover size") {
                    Slider(value: Binding(get: { consoleLayout.iconScale }, set: { value in updateConsoleLayout { $0.iconScale = value } }), in: 0.65...2.5)
                        .accessibilityIdentifier("console.layout.scale")
                    Text("\(Int(consoleLayout.iconScale * 100))% · Size is limited to the available screen height.").font(.footnote)
                }
                Section("Play button size") {
                    Slider(value: Binding(get: { consoleLayout.launchScale }, set: { value in updateConsoleLayout { $0.launchScale = value } }), in: 0.75...2)
                        .accessibilityIdentifier("console.layout.buttonScale")
                    Text("\(Int(consoleLayout.launchScale * 100))%").font(.footnote)
                }
                Section("Launch button position") {
                    Text("Horizontal")
                    Slider(value: Binding(get: { consoleLayout.launchX }, set: { value in updateConsoleLayout { $0.launchX = value } }), in: 0...1)
                    Text("Vertical")
                    Slider(value: Binding(get: { consoleLayout.launchY }, set: { value in updateConsoleLayout { $0.launchY = value } }), in: 0...1)
                    Button("Drag button on screen") { layoutSettings = false; movingLaunchButton = true }
                }
                Section {
                    Button("Reset this mode’s layout") { savedConsoleLayouts = LiveBoardConsoleLayout.save(LiveBoardConsoleLayout(), mode: mode, in: savedConsoleLayouts) }
                    Text("Cinematic and Big Picture keep separate layouts.").font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("Customize layout")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Move button") { layoutSettings = false; movingLaunchButton = true }.accessibilityIdentifier("console.layout.drag") }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { layoutSettings = false } }
                }
        }.navigationViewStyle(.stack)
    }
    private var footer: some View {
        HStack(spacing: 16) {
            Text(bigPicture ? "STRATA / BIG PICTURE" : "STRATA / CINEMATIC")
                .font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(.white.opacity(0.4))
            Spacer(minLength: 0)
            if controller.connected {
                Label("Launch", systemImage: controller.confirmSymbol)
                Label("Options", systemImage: controller.detailsSymbol)
            } else { Image(systemName: "gamecontroller").foregroundStyle(.white.opacity(0.4)).accessibilityLabel("Connect a controller to navigate") }
        }.font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
    }
    private func detailsOverlay(_ app: LCAppModel, height: CGFloat) -> some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { details = false }
            VStack(alignment: .leading, spacing: 10) {
                Text(appCustomization.name(app)).font(.headline).lineLimit(1)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach((0..<11).filter { bigPicture || $0 != 6 }, id: \.self) { index in
                                Button { detailAction(index, app: app) } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: ["play.fill", "gearshape", "photo", "rectangle", "star", "arrow.counterclockwise", "rectangle.portrait", "eye.slash", "bolt.fill", "pencil", "gamecontroller.fill"][index]).frame(width: 24)
                                        Text(["Launch", "App settings", "Choose landscape cover", "Choose background", favoriteKeys.contains(liveBoardAppKey(app)) ? "Remove favorite" : "Add favorite", "Reset artwork", "Choose portrait cover", "Hide in this mode", "Launch with JIT", "Rename / change app icon", "Request Game Mode"][index]).font(.system(size: 15))
                                        Spacer(minLength: 0)
                                    }.padding(10).frame(minHeight: 40).background(detailsIndex == index ? .white.opacity(0.17) : .clear, in: RoundedRectangle(cornerRadius: 10))
                                }.buttonStyle(.plain).id(index).accessibilityIdentifier("console.option.\(index)")
                            }
                        }
                    }.accessibilityIdentifier("console.options.scroll").onChange(of: detailsIndex) { index in proxy.scrollTo(index) }
                }
                Button("Close") { details = false }.frame(maxWidth: .infinity, minHeight: 36).accessibilityIdentifier("console.options.close")
            }.padding(16).frame(width: 340).frame(maxHeight: max(160, height - 24))
                .liveBoardGlass(radius: 24, interactive: false).padding(.horizontal, 12)
        }.accessibilityAddTraits(.isModal)
    }
    private var searchSheet: some View {
        NavigationView {
            List {
                ForEach(apps.filter { query.isEmpty || appCustomization.name($0).localizedCaseInsensitiveContains(query) || $0.bundleIdentifier.localizedCaseInsensitiveContains(query) }, id: \.self) { app in
                    Button {
                        favoritesOnly = false; activeCategory = nil
                        updateLibrary { $0.hidden.remove(liveBoardAppKey(app)) }
                        navigation.selectedIndex = visibleApps.firstIndex(of: app) ?? 0
                        navigation.focus = .rail; searching = false
                    } label: {
                        HStack(spacing: 12) {
                            LiveBoardIconImage(app: app, dark: darkIcons).frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 11))
                            Text(appCustomization.name(app)).foregroundStyle(.primary)
                        }
                    }.buttonStyle(.plain)
                }
            }.searchable(text: $query, prompt: "Search library")
                .navigationTitle("Library").navigationBarHidden(false)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { searching = false } } }
        }.navigationViewStyle(.stack)
    }
    private func category(_ app: LCAppModel) -> String {
        return library.assignments[liveBoardAppKey(app)] ?? "App"
    }
    private func favorite(_ app: LCAppModel) {
        var keys = favoriteKeys; let key = liveBoardAppKey(app)
        if keys.contains(key) { keys.removeAll { $0 == key } } else { keys.append(key) }
        if let data = try? JSONEncoder().encode(keys), let string = String(data: data, encoding: .utf8) { favorites = string }
    }
    private func openSearch() { controller.stop(); searching = true }
    private func showDetails() { guard selected != nil else { return }; detailsIndex = 0; details = true }
    private func detailAction(_ index: Int, app: LCAppModel) {
        switch index {
        case 0: details = false; activate(app)
        case 1: details = false; controller.stop(); manage(app)
        case 2, 3, 6:
            details = false; controller.stop()
            picker = ArtworkRequest(key: liveBoardAppKey(app), kind: index == 2 ? .cover : (index == 6 ? .portrait : .background))
        case 8: details = false; activate(app, forceJIT: true)
        case 10: details = false; activate(app, gameMode: true)
        case 9: details = false; controller.stop(); appearanceApp = LiveBoardAppearanceSelection(app: app)
        case 4: favorite(app)
        case 7: updateLibrary { $0.hidden.insert(liveBoardAppKey(app)) }; details = false
        case 5:
            artwork.remove(for: liveBoardAppKey(app), kind: .cover, mode: mode)
            artwork.remove(for: liveBoardAppKey(app), kind: .background, mode: mode)
            artwork.remove(for: liveBoardAppKey(app), kind: .portrait, mode: mode)
        default: break
        }
    }
    private func activate(_ app: LCAppModel, forceJIT: Bool = false, gameMode: Bool = false) {
        guard !launching, !movingLaunchButton else { return }
        let launcherWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }.first { $0.isKeyWindow }
        LiveBoardOrientation.setLandscape(false, window: launcherWindow)
        controller.stop(); audio.stop(); launching = true
        Task { @MainActor in
            if gameMode, let launchInGameMode { await launchInGameMode(app) }
            else if forceJIT, let launchWithJIT { await launchWithJIT(app) } else { await launch(app) }
            launching = false
            // Do not reclaim the gamepad after a guest starts in-process.
            // Scene reactivation or an explicit touch resumes launcher input after a canceled launch.
            launchReturned = true
        }
    }
    private func bindController() {
        guard consoleVisible, (scenePhase == .active || UIApplication.shared.applicationState == .active), !searching, !managingCategories, !jitSetup, !layoutSettings, !movingLaunchButton, appearanceApp == nil, picker == nil, artworkError == nil, !launching else { return }
        controller.onCommand = { command in handle(command) }
        controller.start()
    }
    private func handle(_ command: LiveBoardControllerInput.Command) {
        guard !launching, !movingLaunchButton else { return }
        if details {
            switch command {
            case .up: detailsIndex = max(0, detailsIndex - 1); if !bigPicture && detailsIndex == 6 { detailsIndex = 5 }
            case .down: detailsIndex = min(10, detailsIndex + 1); if !bigPicture && detailsIndex == 6 { detailsIndex = 7 }
            case .confirm: if let app = selected { detailAction(detailsIndex, app: app) }
            case .back, .details: details = false
            default: break
            }
            return
        }
        switch command {
        case .confirm:
            if navigation.focus == .header {
                switch navigation.headerIndex {
                case 0: favoritesOnly = false
                case 1: favoritesOnly = true
                case 2: controller.stop(); openManagement()
                default: controller.stop(); openInterface()
                }
            } else if navigation.focus == .details { showDetails() }
            else if let app = selected { activate(app) }
        case .details: showDetails()
        case .favorite: if let app = selected { favorite(app) }
        case .previousSection: changeSection(-1)
        case .nextSection: changeSection(1)
        default: navigation.move(command, count: visibleApps.count)
        }
    }
}
