import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

func liveBoardAppKey(_ app: LCAppModel) -> String {
    if app.appInfo is BuiltInSideStoreAppInfo { return "builtin:sidestore" }
    return "\(app.uiIsShared ? "shared" : "local"):\(app.appInfo.relativeBundlePath ?? app.bundleIdentifier)"
}

struct LiveBoardHomeScreen: View {
    let apps: [LCAppModel]
    let launch: (LCAppModel) -> Void
    let manage: (LCAppModel) -> Void
    let openInterface: () -> Void
    let openManagement: () -> Void
    let openTab: (LCTabIdentifier) -> Void
    let secondaryInstance: Bool
    var launchWithJIT: ((LCAppModel) -> Void)? = nil
    var launchInGameMode: ((LCAppModel) -> Void)? = nil
    var launchWithMetalHUD: ((LCAppModel) -> Void)? = nil
    var launchMultitask: ((LCAppModel) -> Void)? = nil
    @ObservedObject private var appCustomization = LiveBoardAppCustomization.shared
    @State private var appearanceApp: LiveBoardAppearanceSelection?
    @State private var jitSetup = false
    @AppStorage("LiveBoardHomeCategories", store: LCUtils.appGroupUserDefault) private var homeCategories = "[\"Games\",\"Ports\",\"Tools\"]"
    @State private var addingCategory = false
    @State private var categoryName = ""
    @State private var categoryApp: String?

    @AppStorage("LiveBoardHomeLayout", store: LCUtils.appGroupUserDefault) private var savedLayout = ""
    @AppStorage("LiveBoardFavorites", store: LCUtils.appGroupUserDefault) private var favorites = "[]"
    @AppStorage("LiveBoardCategories", store: LCUtils.appGroupUserDefault) private var categories = "{}"
    @AppStorage("LiveBoardLargeIcons", store: LCUtils.appGroupUserDefault) private var largeIcons = false
    @AppStorage("darkModeIcon", store: LCUtils.appGroupUserDefault) private var darkIcons = false
    @AppStorage("LiveBoardWallpaperStyle", store: LCUtils.appGroupUserDefault) private var wallpaperStyle = "red"
    @AppStorage("LiveBoardWallpaperFit", store: LCUtils.appGroupUserDefault) private var wallpaperFit = false
    @AppStorage("LiveBoardWallpaperDim", store: LCUtils.appGroupUserDefault) private var wallpaperDim = 0.1
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @AppStorage("LiveBoardReduceMotion", store: LCUtils.appGroupUserDefault) private var customReduceMotion = false
    private var reduceMotion: Bool { systemReduceMotion || customReduceMotion }
    @State private var layout = LiveBoardHomeLayout()
    @State private var page = 1
    @State private var pagerMotion = StrataHomePagerMotion()
    @ObservedObject private var widgetPhotos = LiveBoardWidgetPhotos.shared
    @State private var managingPages = false
    @State private var removingPage: Int?
    @State private var showingRemovePage = false
    @State private var addingWidget = false
    @State private var configuringWidget: LiveBoardHomeLayout.Widget?
    @State private var widgetAppearance: LiveBoardHomeLayout.Widget.Appearance = .gradient
    @State private var widgetSize: LiveBoardHomeLayout.Widget.Size = .small
    @State private var choosingWidgetPhoto = false
    @State private var widgetPhotoID: String?
    @State private var pendingWidgetPhoto = false
    @State private var pendingHomeSheet: String?
    @State private var editing = false
    @State private var searching = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var customizing = false
    @ObservedObject private var wallpapers = StrataWallpapers.shared
    @AppStorage("StrataSelectedWallpaper", store: LCUtils.appGroupUserDefault) private var selectedWallpaper = ""
    @Environment(\.scenePhase) private var scenePhase
    @State private var importingWallpaper = false
    @State private var wallpaperImportBusy = false
    @State private var expandedCategory: String?
    @State private var choosingWallpaper = false
    @State private var wallpaper: UIImage?
    @State private var openFolder: String?
    @State private var folderPage = 0
    @State private var renameKey: String?
    @State private var renameValue = ""
    @State private var newFolderApp: String?
    @State private var folderName = ""
    @State private var wallpaperError: String?

    private var appKeys: [String] { apps.map(liveBoardAppKey) }
    @State private var appMap: [String: LCAppModel] = [:]
    private var favoriteKeys: [String] { (try? JSONDecoder().decode([String].self, from: Data(favorites.utf8))) ?? [] }
    private var wallpaperURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LiveBoard", isDirectory: true).appendingPathComponent("wallpaper.jpg")
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                StrataPagingBackdrop(motion: pagerMotion, count: layout.pages.count,
                    sharp: AnyView(background), blurred: AnyView(wallpaperSurface(animate: false)))
                ZStack(alignment: .bottom) {
                    StrataHomePager(pages: pagerPages(width: geometry.size.width, height: geometry.size.height), selection: $page, motion: pagerMotion, scrollingEnabled: openFolder == nil && expandedCategory == nil && !searching, reduceMotion: reduceMotion)
                        .blur(radius: openFolder == nil ? 0 : 18)
                    StrataPagingDock(motion: pagerMotion, count: layout.pages.count, width: geometry.size.width,
                        content: AnyView(VStack(spacing: 0) {
                            pageControl.padding(.bottom, 18)
                            dock(width: geometry.size.width).padding(.horizontal, 12).padding(.bottom, -22)
                        }.blur(radius: openFolder == nil ? 0 : 18)))
                }
                .blur(radius: searching ? 14 : 0)
                .allowsHitTesting(!searching && expandedCategory == nil && openFolder == nil)
                .accessibilityHidden(searching || expandedCategory != nil || openFolder != nil)
                if editing && !searching {
                    VStack {
                        HStack {
                            Menu {
                                Button("Customize", systemImage: "paintbrush") { customizing = true }
                                Button("Add widget", systemImage: "plus.square") { addingWidget = true }
                                Button("Manage pages", systemImage: "square.on.square") { managingPages = true }
                                Button("Add page", systemImage: "plus") { addPage() }
                                Button("App library", systemImage: "square.grid.2x2") { page = layout.pages.count + 1 }
                            } label: { Text("Edit").font(.system(size: 16, weight: .semibold)).padding(.horizontal, 18).padding(.vertical, 8) }
                            .liveBoardGlass(radius: 18)
                            Spacer()
                            Button("Done") { editing = false }.font(.system(size: 16, weight: .semibold))
                                .padding(.horizontal, 18).padding(.vertical, 8).liveBoardGlass(radius: 18)
                        }.padding(.horizontal, 22)
                        Spacer()
                    }.padding(.top, 0)
                }
                if let name = expandedCategory { expandedCategoryView(name).zIndex(5) }
                if searching { searchOverlay(height: geometry.size.height) }
                if let id = openFolder, let folder = layout.folders.first(where: { $0.id == id }) {
                    folderOverlay(folder, width: geometry.size.width)
                }
            }
            .foregroundColor(.white)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .simultaneousGesture(DragGesture(minimumDistance: 35).onEnded { value in
                if !searching && !editing && openFolder == nil && expandedCategory == nil && page > 0 &&
                    value.translation.height > 65 && abs(value.translation.height) > abs(value.translation.width) * 1.4 {
                    beginSearch()
                }
            })
            .onChange(of: appKeys) { _ in reconcile() }
            .onChange(of: layout) { savedLayout = $0.encoded; page = min(page, layout.pages.count + 1) }
            .onAppear {
                layout = LiveBoardHomeLayout.decode(savedLayout)
                reconcile()
                wallpaper = UIImage(contentsOfFile: wallpaperURL.path)
                wallpapers.reload()
            }
        }
        .onChange(of: scenePhase) { phase in if phase == .active { wallpapers.reload() } }
        .background(LiveBoardOrientationLock(mask: .portrait))
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .alert("New Home category", isPresented: $addingCategory) {
            TextField("Category name", text: $categoryName)
            Button("Add") {
                let value = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty, value.count <= 30 else { return }
                var names = (try? JSONDecoder().decode([String].self, from: Data(homeCategories.utf8))) ?? []
                if !names.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) { names.append(value) }
                if let data = try? JSONEncoder().encode(names), let text = String(data: data, encoding: .utf8) { homeCategories = text }
                if let key = categoryApp { setCategory(value, key: key) }
            }
            Button("Cancel", role: .cancel) { }
        }
        .sheet(isPresented: $jitSetup) { LiveBoardJITSetup() }
        .sheet(isPresented: $customizing, onDismiss: {
            if pendingHomeSheet == "widgets" { addingWidget = true }
            if pendingHomeSheet == "pages" { managingPages = true }
            pendingHomeSheet = nil
        }) { customizeSheet }
        .sheet(isPresented: $managingPages) { pagesSheet }
        .sheet(isPresented: $addingWidget, onDismiss: {
            if pendingWidgetPhoto { pendingWidgetPhoto = false; choosingWidgetPhoto = true }
        }) { widgetGallery }
        .sheet(item: $configuringWidget, onDismiss: {
            if pendingWidgetPhoto { pendingWidgetPhoto = false; choosingWidgetPhoto = true }
        }) { widget in widgetConfiguration(widget.id) }
        .sheet(isPresented: $choosingWidgetPhoto) {
            LiveBoardWallpaperPicker { image in
                choosingWidgetPhoto = false
                guard let image else { widgetPhotoID = nil; return }
                do {
                    let file = try widgetPhotos.save(image)
                    if let id = widgetPhotoID, let index = layout.widgets.firstIndex(where: { $0.id == id }) {
                        let old = layout.widgets[index].photo
                        layout.widgets[index].photo = file
                        widgetPhotos.remove(old)
                    } else {
                        addHomeWidget(.photo, photo: file)
                    }
                } catch { wallpaperError = error.localizedDescription }
                widgetPhotoID = nil
            }
        }
        .sheet(item: $appearanceApp) { app in LiveBoardAppAppearance(app: app.app) }
        .alert("Rename", isPresented: Binding(get: { renameKey != nil }, set: { if !$0 { renameKey = nil } })) {
            TextField("Name", text: $renameValue)
            Button("Cancel", role: .cancel) { renameKey = nil }
            Button("Save") {
                if let key = renameKey {
                    let name = renameValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let index = layout.folders.firstIndex(where: { $0.id == key }) {
                        if !name.isEmpty { layout.folders[index].name = name }
                    } else if let app = appMap[key] { appCustomization.rename(app, to: name); layout.aliases[key] = nil }
                }
                renameKey = nil
            }
        }
        .alert("New Folder", isPresented: Binding(get: { newFolderApp != nil }, set: { if !$0 { newFolderApp = nil } })) {
            TextField("Folder name", text: $folderName)
            Button("Cancel", role: .cancel) { newFolderApp = nil }
            Button("Create") {
                if let key = newFolderApp {
                    layout.createFolder(name: folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Apps" : folderName, app: key)
                    reconcile()
                }
                newFolderApp = nil
            }
        }
        .alert("Image", isPresented: Binding(get: { wallpaperError != nil }, set: { if !$0 { wallpaperError = nil } })) {
            Button("OK") { wallpaperError = nil }
        } message: { Text(wallpaperError ?? "") }
    }

    private var background: some View { wallpaperSurface(animate: true) }
    private func wallpaperSurface(animate: Bool) -> some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if let item = wallpapers.items.first(where: { $0.id == selectedWallpaper }), wallpaperStyle == "catalogue" || wallpaperStyle == "photo" {
                    if item.live && animate { StrataLiveWallpaper(url: wallpapers.url(item), playing: scenePhase == .active && !reduceMotion && !customizing && !searching && expandedCategory == nil, fit: wallpaperFit).allowsHitTesting(false) }
                    else if let image = wallpapers.image(item) { Image(uiImage: image).resizable().aspectRatio(contentMode: wallpaperFit ? .fit : .fill).frame(width: geometry.size.width, height: geometry.size.height).clipped() }
                } else if wallpaperStyle == "photo", let wallpaper {
                    Image(uiImage: wallpaper).resizable().aspectRatio(contentMode: wallpaperFit ? .fit : .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                } else if wallpaperStyle != "black" {
                    LiveBoardRibbonWallpaper(blue: wallpaperStyle == "blue").drawingGroup(opaque: true)
                }
                Color.black.opacity(wallpaperDim)
            }
        }.ignoresSafeArea()
    }

    private func homePage(_ index: Int, width: CGFloat, height: CGFloat) -> some View {
        let cellWidth = (width - 28) / 4
        let slots = layout.pages.indices.contains(index) ? layout.pages[index] : Array<String?>(repeating: nil, count: LiveBoardHomeLayout.capacity)
        let pitch = min(editing ? 88 : 93, max(72, (height - (editing ? 69 : 39)) / 6))
        return ZStack(alignment: .topLeading) {
            ForEach(0..<LiveBoardHomeLayout.capacity, id: \.self) { slot in
                let key = slots[slot]
                let widget = layout.widgets.first { $0.id == key }
                ZStack(alignment: .top) {
                    if let widget {
                        homeWidget(widget, cellWidth: cellWidth, pitch: pitch)
                    } else if let key {
                        homeItem(key, showLabel: !largeIcons)
                    } else {
                        Color.clear.frame(width: largeIcons ? 76 : 64, height: largeIcons ? 76 : 80).contentShape(Rectangle()).onLongPressGesture(minimumDuration: 0.6) { editing = true }
                    }
                }
                .frame(width: widget == nil ? cellWidth : cellWidth * CGFloat(widget!.size.columns),
                       height: widget == nil ? pitch : pitch * CGFloat(widget!.size.rows), alignment: .top)
                .contentShape(Rectangle())
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.6).onEnded { _ in if key == nil { editing = true } })
                .offset(x: CGFloat(slot % 4) * cellWidth * (layoutDirection == .rightToLeft ? -1 : 1), y: CGFloat(slot / 4) * pitch)
                .zIndex(widget == nil ? 0 : 1)
                .onDrop(of: [UTType.text], isTargeted: nil) { providers in
                    acceptDrop(providers) { source in
                        if let target = key, source != target, appMap[source] != nil {
                            if layout.folders.contains(where: { $0.id == target }) { layout.put(source, in: target) }
                            else if appMap[target] != nil, let id = layout.merge(source, onto: target) { editing = true; showHomeFolder(id) }
                            else { layout.place(source, on: index, slot: slot) }
                        } else { layout.place(source, on: index, slot: slot) }
                        reconcile()
                    }
                }
            }
        }
        .frame(width: width - 28, height: pitch * 6, alignment: .topLeading)
        .background(Color.clear.contentShape(Rectangle()).onLongPressGesture(minimumDuration: 0.6) { editing = true })
        .padding(.horizontal, 14)
        .padding(.top, editing ? 50 : 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func homeWidget(_ widget: LiveBoardHomeLayout.Widget, cellWidth: CGFloat, pitch: CGFloat) -> some View {
        Button { configuringWidget = widget } label: {
            LiveBoardHomeWidgetCard(widget: widget, photo: widgetPhotos.image(widget.photo))
                .frame(width: cellWidth * CGFloat(widget.size.columns) - 14, height: min(pitch * CGFloat(widget.size.rows) - 16, cellWidth * 2 - 14))
        }.buttonStyle(.plain)
            .modifier(LiveBoardEditWobble(active: editing && !reduceMotion))
            .contextMenu {
                Button("Edit Widget", systemImage: "slider.horizontal.3") { configuringWidget = widget }
                if widget.kind == .photo {
                    Button("Change Photo", systemImage: "photo") { widgetPhotoID = widget.id; choosingWidgetPhoto = true }
                }
                Menu("Widget size") {
                    Button("Small · 2 × 2") { layout.resizeWidget(widget.id, to: .small) }
                    Button("Medium · 4 × 2") { layout.resizeWidget(widget.id, to: .medium) }
                }
                Menu("Move to Page") {
                    ForEach(layout.pages.indices, id: \.self) { target in
                        Button("Page \(target + 1)") { layout.place(widget.id, on: target); page = target + 1 }
                    }
                }
                Button("Edit Home Screen", systemImage: "square.grid.3x3") { editing = true }
                Button("Remove Widget", systemImage: "trash", role: .destructive) { removeHomeWidget(widget.id) }
            }
            .accessibilityIdentifier("home.widget.\(widget.kind.rawValue)")
            .overlay(alignment: .topLeading) {
                if editing {
                    Button { removeHomeWidget(widget.id) } label: {
                        Image(systemName: "minus").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 24, height: 24).liveBoardGlass(radius: 12)
                    }.offset(x: -7, y: -7).accessibilityLabel("Remove \(widget.kind.title) widget").accessibilityIdentifier("home.widget.remove.\(widget.id)")
                }
            }
            .onDrag { NSItemProvider(object: widget.id as NSString) }
    }

    private func homeItem(_ key: String, showLabel: Bool) -> some View {
        Group {
            if let folder = layout.folders.first(where: { $0.id == key }) {
                folderIcon(folder, showLabel: showLabel)
            } else if let app = appMap[key] {
                LiveBoardHomeIcon(app: app, title: title(key), size: largeIcons ? 76 : 64,
                                  showLabel: showLabel, dark: darkIcons, editing: editing,
                                  reduceMotion: reduceMotion, action: {
                    if editing { return }
                    launch(app)
                })
                .contextMenu { appMenu(key, app: app) }
                .overlay(alignment: .topLeading) {
                    if editing {
                        Button { layout.hide(key); reconcile(); if let id = openFolder, !layout.folders.contains(where: { $0.id == id }) { closeHomeFolder() } } label: {
                            Image(systemName: "minus").font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white).frame(width: 24, height: 24)
                                .liveBoardGlass(radius: 12)
                        }.offset(x: -7, y: -7).accessibilityLabel("Remove \(title(key)) from Home Screen")
                    }
                }
            }
        }
        .onDrag { NSItemProvider(object: key as NSString) }
        .onDrop(of: [UTType.text], isTargeted: nil) { providers in
            guard appMap[key] != nil else { return false }
            return acceptDrop(providers) { source in
                guard source != key, appMap[source] != nil else { return }
                if let folder = openFolder { layout.put(source, in: folder) }
                else if let id = layout.merge(source, onto: key) { editing = true; showHomeFolder(id) }
                reconcile()
            }
        }
        .accessibilityIdentifier("home.icon.\(key)")
    }

    @ViewBuilder private func appMenu(_ key: String, app: LCAppModel) -> some View {
        Button(app.strataSwitcherPinned ? "Unpin from app switcher" : "Pin to app switcher", systemImage: "pin") { app.strataSwitcherPinned.toggle() }
        if let launchInGameMode { Button("Request Game Mode", systemImage: "gamecontroller.fill") { launchInGameMode(app) }.disabled(app.appInfo is BuiltInSideStoreAppInfo) }
        if let launchMultitask { Button("Multitask", systemImage: "rectangle.on.rectangle") { launchMultitask(app) }.disabled(app.appInfo is BuiltInSideStoreAppInfo) }
        if let launchWithMetalHUD { Button("Launch with Metal HUD", systemImage: "gauge.with.dots.needle.67percent") { launchWithMetalHUD(app) }.disabled(app.appInfo is BuiltInSideStoreAppInfo) }
        Button("Launch", systemImage: "play.fill") { launch(app) }.disabled(app.isAppRunning || app.isSigningInProgress)
        if let launchWithJIT { Button("Launch with JIT", systemImage: "bolt.fill") { launchWithJIT(app) }.disabled(app.appInfo is BuiltInSideStoreAppInfo) }
        Button("Edit Home Screen", systemImage: "square.grid.3x3") { editing = true }
        Button("Rename", systemImage: "pencil") { renameValue = title(key); renameKey = key }
        Button("Change app icon", systemImage: "photo") { appearanceApp = LiveBoardAppearanceSelection(app: app) }
        Button(favoriteKeys.contains(key) ? "Unfavorite" : "Favorite", systemImage: "star") {
            var values = favoriteKeys
            if values.contains(key) { values.removeAll { $0 == key } } else { values.append(key) }
            if let data = try? JSONEncoder().encode(values), let string = String(data: data, encoding: .utf8) { favorites = string }
        }
        if layout.dock.contains(key) {
            Button("Remove from Dock", systemImage: "rectangle.bottomthird.inset.filled") { layout.place(key, on: max(0, page - 1)); reconcile() }
        } else if layout.dock.count < 4 {
            Button("Add to Dock", systemImage: "rectangle.bottomthird.inset.filled") { layout.putInDock(key); reconcile() }
        }
        Menu("Move to Page", systemImage: "rectangle.on.rectangle") {
            ForEach(layout.pages.indices, id: \.self) { index in
                Button("Page \(index + 1)") { layout.place(key, on: index); reconcile() }
            }
            Button("New Page") { let target = layout.pages.count; layout.place(key, on: target); page = target + 1; reconcile() }
        }
        Menu("Folder", systemImage: "folder") {
            Button("New Folder") { newFolderApp = key; folderName = "Apps" }
            ForEach(layout.folders) { folder in
                Button(folder.name) { layout.put(key, in: folder.id); reconcile() }
            }
            if layout.folders.contains(where: { $0.apps.contains(key) }) {
                Button("Move out of Folder") { layout.place(key, on: max(0, page - 1)); reconcile() }
            }
        }
        Menu("Category", systemImage: "tag") {
            ForEach((try? JSONDecoder().decode([String].self, from: Data(homeCategories.utf8))) ?? ["Games", "Ports", "Tools"], id: \.self) { value in Button(value) { setCategory(value, key: key) } }
            Button("New Category…") { categoryApp = key; categoryName = ""; addingCategory = true }
            Button("Uncategorized") { setCategory(nil, key: key) }
        }
        Button("App Settings", systemImage: "gearshape") { searching = false; manage(app) }
        Button("Remove from Home Screen", systemImage: "minus.circle", role: .destructive) { layout.hide(key); reconcile() }
    }

    private func dock(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            if layout.dock.isEmpty { Spacer() }
            ForEach(layout.dock, id: \.self) { key in
                homeItem(key, showLabel: false).frame(width: (width - 32) / 4)
            }
            if layout.dock.isEmpty { Spacer() }
        }
        .frame(height: 110)
        .frame(maxWidth: .infinity)
        .liveBoardGlass(radius: 34, interactive: false)
        .onDrop(of: [UTType.text], isTargeted: nil) { providers in
            guard layout.dock.count < 4 else { return false }
            return acceptDrop(providers) { key in layout.putInDock(key); reconcile() }
        }
        .accessibilityIdentifier("home.dock")
    }

    private func pagerPages(width: CGFloat, height: CGFloat) -> [AnyView] {
        [AnyView(controls.padding(.top, 20).padding(.bottom, 126))] + layout.pages.indices.map { index in
            AnyView(homePage(index, width: width, height: max(400, height - 126)))
        } + [AnyView(appLibrary)]
    }
    private var pageControl: some View {
        HStack(spacing: 5) {
            Button { beginSearch() } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold)).frame(width: 28, height: 32)
            }.accessibilityLabel("Search")
            Rectangle().fill(.white.opacity(0.22)).frame(width: 0.5, height: 12).padding(.trailing, 3)
            HStack(spacing: 0) {
                ForEach(0..<layout.pages.count, id: \.self) { index in
                    Button { page = index + 1 } label: {
                        StrataHomePageDot(motion: pagerMotion, page: index + 1).frame(width: 22, height: 32)
                    }.accessibilityLabel("Page \(index + 1)").accessibilityValue(page == index + 1 ? "Selected" : "")
                        .onDrop(of: [UTType.text], isTargeted: nil) { providers in
                            acceptDrop(providers) { key in layout.place(key, on: index); openFolder = nil; page = index + 1; reconcile() }
                        }
                }
            }.contentShape(Rectangle())
                .highPriorityGesture(DragGesture(minimumDistance: 5).onChanged { value in
                    let fraction = min(CGFloat(max(0, layout.pages.count - 1)), max(0, value.location.x / 22 - 0.5)) + 1
                    pagerMotion.scrub?(fraction, false)
                }.onEnded { value in
                    let fraction = min(CGFloat(max(0, layout.pages.count - 1)), max(0, value.location.x / 22 - 0.5)) + 1
                    pagerMotion.scrub?(fraction.rounded(), true)
                })
            if editing {
                Button { addPage() } label: { Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).frame(width: 24, height: 32) }.accessibilityLabel("Add page")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .frame(height: 32)
        .liveBoardGlass(radius: 16)
        .blur(radius: openFolder == nil ? 0 : 18)
        .accessibilityIdentifier("home.pages")
    }

    private func showHomeFolder(_ id: String) { folderPage = 0; withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) { openFolder = id } }
    private func closeHomeFolder() { withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) { openFolder = nil } }
    private func folderIcon(_ folder: LiveBoardHomeLayout.Folder, showLabel: Bool) -> some View {
        let size: CGFloat = largeIcons ? 76 : 64
        return Button {
            showHomeFolder(folder.id)
        } label: {
            VStack(spacing: 5) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                    ForEach(0..<9, id: \.self) { slot in
                        Group {
                            if slot < folder.apps.count, let app = appMap[folder.apps[slot]] {
                                LiveBoardIconImage(app: app, dark: darkIcons)
                            } else { Color.clear }
                        }.aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(6).frame(width: size, height: size)
                .liveBoardGlass(radius: size * 0.23)
                if showLabel { Text(folder.name).font(.system(size: 12)).lineLimit(1).shadow(color: .black.opacity(0.8), radius: 2, y: 1).frame(width: 80) }
            }
        }.buttonStyle(.plain)
        .contextMenu {
            Button("Edit Home Screen", systemImage: "square.grid.3x3") { editing = true }
            Button("Rename", systemImage: "pencil") { renameKey = folder.id; renameValue = folder.name }
            Menu("Move to Page") {
                ForEach(layout.pages.indices, id: \.self) { index in Button("Page \(index + 1)") { layout.place(folder.id, on: index) } }
            }
            Button("Remove Folder", systemImage: "folder.badge.minus", role: .destructive) { layout.dissolveFolder(folder.id); reconcile() }
        }
        .onDrop(of: [UTType.text], isTargeted: nil) { providers in acceptDrop(providers) { key in layout.put(key, in: folder.id); reconcile() } }
        .accessibilityLabel("\(folder.name), folder, \(folder.apps.count) apps")
    }

    private func folderOverlay(_ folder: LiveBoardHomeLayout.Folder, width: CGFloat) -> some View {
        ZStack {
            Color.black.opacity(0.12).ignoresSafeArea().contentShape(Rectangle()).onTapGesture { closeHomeFolder() }
                .onDrop(of: [UTType.text], isTargeted: nil) { providers in
                    acceptDrop(providers) { key in
                        guard appMap[key] != nil else { return }
                        layout.place(key, on: min(max(0, page - 1), layout.pages.count - 1)); reconcile(); closeHomeFolder(); editing = true
                    }
                }
            VStack(spacing: 28) {
                Button { renameKey = folder.id; renameValue = folder.name } label: { Text(folder.name).font(.system(size: 30, weight: .semibold)) }.buttonStyle(.plain)
                TabView(selection: $folderPage) {
                    ForEach(0..<max(1, (folder.apps.count + 8) / 9), id: \.self) { p in
                        VStack(spacing: 0) {
                            ForEach(0..<3, id: \.self) { row in
                                HStack(alignment: .top, spacing: 0) {
                                    ForEach(0..<3, id: \.self) { col in
                                        let index = p * 9 + row * 3 + col
                                        Group {
                                            if index < folder.apps.count { homeItem(folder.apps[index], showLabel: !largeIcons) }
                                            else { Color.clear.frame(width: 60, height: 80) }
                                        }.frame(maxWidth: .infinity).frame(height: 96, alignment: .top)
                                    }
                                }
                            }
                        }.padding(.horizontal, 12).padding(.top, 28).tag(p)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: folder.apps.count > 9 ? .always : .never))
                .frame(width: min(width - 56, 340), height: 340)
                .liveBoardGlass(radius: 38, interactive: false)
                Button("Close") { closeHomeFolder() }.font(.subheadline).accessibilityIdentifier("home.folder.close")
            }.offset(y: -25)
        }
        .accessibilityAddTraits(.isModal)
        .transition(reduceMotion ? .opacity : .scale(scale: 0.95).combined(with: .opacity))
    }

    private var controls: some View {
        ScrollView {
            VStack(spacing: 16) {
                Button(action: openInterface) { controlCard("Interface", detail: "iOS Home Screen", symbol: "square.grid.3x3.fill", wide: true) }
                HStack(spacing: 16) {
                    Button { openTab(.sources) } label: {
                        controlCard("lc.tabView.sources".loc, detail: secondaryInstance ? "Manage in primary instance" : "Discover & install", symbol: "books.vertical", wide: false)
                    }.disabled(secondaryInstance).accessibilityIdentifier("home.controls.sources")
                    Button { openTab(.tweaks) } label: {
                        controlCard("lc.tabView.tweaks".loc, detail: secondaryInstance ? "Manage in primary instance" : "App extensions", symbol: "wrench.and.screwdriver", wide: false)
                    }.disabled(secondaryInstance).accessibilityIdentifier("home.controls.tweaks")
                }
                HStack(spacing: 16) {
                    Button { customizing = true } label: { controlCard("Wallpaper", detail: "Customize", symbol: "photo", wide: false) }.accessibilityIdentifier("home.controls.wallpaper")
                    Button(action: openManagement) { controlCard("Apps", detail: "Install & manage", symbol: "square.stack.3d.up", wide: false) }
                }
                HStack(spacing: 16) {
                    Button { openTab(.settings) } label: { controlCard("lc.tabView.settings".loc, detail: "LiveContainer", symbol: "gearshape.fill", wide: false) }.accessibilityIdentifier("home.controls.settings")
                    Button { jitSetup = true } label: { controlCard("JIT", detail: "Setup & providers", symbol: "bolt.fill", wide: false) }.accessibilityIdentifier("home.controls.jit")
                }
            }.buttonStyle(.plain).padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 20)
        }
    }
    private func controlCard(_ title: String, detail: String, symbol: String, wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).font(.system(size: 24)).foregroundStyle(.white.opacity(0.95))
            Spacer(minLength: 2)
            Text(title).font(.system(size: 17, weight: .semibold)).lineLimit(1)
            if !detail.isEmpty {
                Text(detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: wide ? 124 : 128)
        .liveBoardGlass(radius: 28)
    }

    private var searchResults: [LCAppModel] {
        apps.filter { query.isEmpty || title(liveBoardAppKey($0)).localizedCaseInsensitiveContains(query) || $0.bundleIdentifier.localizedCaseInsensitiveContains(query) }
    }
    private func beginSearch() { openFolder = nil; searching = true }
    private func closeSearch() { searchFocused = false; searching = false; query = "" }

    private func searchOverlay(height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.12).contentShape(Rectangle()).onTapGesture { closeSearch() }
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass").font(.system(size: 21)).foregroundStyle(.white.opacity(0.75))
                        TextField("Search Apps", text: $query)
                            .font(.system(size: 22, weight: .regular))
                            .textInputAutocapitalization(.never).disableAutocorrection(true)
                            .submitLabel(.search).focused($searchFocused)
                            .accessibilityIdentifier("home.search.field")
                            .onSubmit {
                                if !query.isEmpty, let app = searchResults.first { closeSearch(); launch(app) }
                            }
                        if !query.isEmpty {
                            Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.65)) }
                                .accessibilityLabel("Clear search")
                        }
                    }.padding(.horizontal, 18).frame(height: 58).liveBoardGlass(radius: 28)
                    Button { closeSearch() } label: {
                        Image(systemName: "xmark").font(.system(size: 18, weight: .medium)).frame(width: 48, height: 48)
                    }.liveBoardGlass(radius: 24).accessibilityLabel("Done").accessibilityIdentifier("home.search.done")
                }
                if query.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Suggestions").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.65))
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 18) {
                            ForEach(Array(searchResults.prefix(8)), id: \.self) { app in
                                searchIcon(app)
                            }
                        }
                    }.padding(18).liveBoardGlass(radius: 30, interactive: false)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(searchResults, id: \.self) { app in
                                let key = liveBoardAppKey(app)
                                Button { closeSearch(); launch(app) } label: {
                                    HStack(spacing: 14) {
                                        LiveBoardIconImage(app: app, dark: darkIcons).frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                                        Text(title(key)).font(.system(size: 17)).lineLimit(1)
                                        Spacer()
                                        if layout.hidden.contains(key) { Image(systemName: "plus.circle").foregroundStyle(.white.opacity(0.6)) }
                                    }.padding(.horizontal, 18).padding(.vertical, 11)
                                }.buttonStyle(.plain).contextMenu { searchMenu(key, app: app) }
                            }
                            if searchResults.isEmpty { Text("No Results").foregroundStyle(.white.opacity(0.65)).padding(24) }
                        }
                    }
                    .frame(height: min(380, height * 0.48, CGFloat(max(1, searchResults.count)) * 66))
                    .liveBoardGlass(radius: 30, interactive: false)
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 12).padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { DispatchQueue.main.async { searchFocused = true } }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { closeSearch() }
    }
    private func searchIcon(_ app: LCAppModel) -> some View {
        let key = liveBoardAppKey(app)
        return Button { closeSearch(); launch(app) } label: {
            VStack(spacing: 6) {
                LiveBoardIconImage(app: app, dark: darkIcons).frame(width: 60, height: 60).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(title(key)).font(.system(size: 12)).lineLimit(1)
            }
        }.buttonStyle(.plain).contextMenu { searchMenu(key, app: app) }
    }
    @ViewBuilder private func searchMenu(_ key: String, app: LCAppModel) -> some View {
        if layout.hidden.contains(key) {
            Button("Add to Home Screen", systemImage: "plus") { layout.place(key, on: max(0, page - 1)); reconcile() }
        }
        appMenu(key, app: app)
    }

    private func importWallpaperVideo(_ url: URL, removeTemporary: Bool) {
        wallpaperImportBusy = true
        Task {
            defer { wallpaperImportBusy = false; if removeTemporary { try? FileManager.default.removeItem(at: url) } }
            do { let item = try await wallpapers.add(video: url); selectedWallpaper = item.id; wallpaperStyle = "catalogue" } catch { wallpaperError = error.localizedDescription }
        }
    }
    private func wallpaperPreview(apps: Bool) -> some View {
        GeometryReader { geo in
            ZStack {
                wallpaperSurface(animate: false)
                if apps {
                    VStack(spacing: 8) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 10) {
                            ForEach(0..<24) { _ in RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.35)).aspectRatio(1, contentMode: .fit) }
                        }
                        Spacer(minLength: 2)
                        RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.2)).frame(height: 30)
                    }.padding(10).padding(.top, 16)
                }
            }.frame(width: geo.size.width, height: geo.size.height).clipped()
        }.aspectRatio(0.47, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 24))
    }
    private var wallpaperOverview: some View {
        VStack(spacing: 18) {
            Text("CURRENT").font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 12) { wallpaperPreview(apps: false); wallpaperPreview(apps: true) }
                .frame(maxHeight: 330)
            Text("Wallpaper                  Home Screen").font(.caption).foregroundStyle(.secondary)
            Menu {
                Button("Choose Photo or Video", systemImage: "photo.on.rectangle") { choosingWallpaper = true }
                Button("Import from Files", systemImage: "folder") { importingWallpaper = true }
            } label: { Label("Add New Wallpaper", systemImage: "plus").padding(.horizontal, 18).padding(.vertical, 10) }
                .buttonStyle(.borderedProminent).tint(.blue)
            if wallpaperImportBusy { ProgressView("Importing wallpaper…") }
        }.padding(18)
    }
    private var wallpaperCatalogue: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(["red", "blue", "black"], id: \.self) { style in
                Button { wallpaperStyle = style; selectedWallpaper = "" } label: {
                    VStack(spacing: 5) {
                        ZStack { Color.black; if style != "black" { LiveBoardRibbonWallpaper(blue: style == "blue") } }
                            .aspectRatio(0.65, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(alignment: .topTrailing) { if wallpaperStyle == style { Image(systemName: "checkmark.circle.fill").padding(6).foregroundStyle(.blue) } }
                        Text(style.capitalized).font(.caption); Text("STATIC").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    }
                }.buttonStyle(.plain)
            }
            ForEach(wallpapers.items) { item in
                Button { selectedWallpaper = item.id; wallpaperStyle = "catalogue" } label: {
                    VStack(spacing: 5) {
                        Group { if let image = wallpapers.image(item) { Image(uiImage: image).resizable().scaledToFill() } else { Color.gray } }
                            .frame(height: 135).frame(maxWidth: .infinity).clipped().clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(alignment: .topTrailing) { if selectedWallpaper == item.id && (wallpaperStyle == "catalogue" || wallpaperStyle == "photo") { Image(systemName: "checkmark.circle.fill").padding(6).foregroundStyle(.blue) } }
                        Text(item.name).font(.caption).lineLimit(1)
                        Label(item.live ? "LIVE" : "STATIC", systemImage: item.live ? "play.circle" : "photo").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    }
                }.buttonStyle(.plain).accessibilityLabel("Apply \(item.name), \(item.live ? "live" : "static") wallpaper")
            }
        }.padding(.vertical, 8)
    }
    private var customizeSheet: some View {
        NavigationView {
            Form {
                Section { wallpaperOverview.listRowInsets(EdgeInsets()) }
                Section("Wallpapers") { wallpaperCatalogue }
                Section("Wallpaper options") {
                    Toggle("Fit entire image", isOn: $wallpaperFit)
                    VStack(alignment: .leading) { Text("Dim wallpaper"); Slider(value: $wallpaperDim, in: 0...0.7) }
                    Text("Imported photos and videos are saved in Files → On My iPhone → Strata → Artwork → Wallpapers. Live wallpapers loop silently; Reduce Motion pauses playback.").font(.caption).foregroundStyle(.secondary)
                }
                Section("App Switcher") { NavigationLink("Running and pinned apps") { StrataSwitcherSettings(apps: apps) } }
                Section("Appearance") {
                    Toggle("Large icons", isOn: $largeIcons)
                    Toggle("Reduce motion", isOn: $customReduceMotion)
                    Toggle("Dark app icons", isOn: $darkIcons)
                }
                Section("Home Screen") {
                    Button("Edit Home Screen") { customizing = false; editing = true }
                    Button("Add Widget") { pendingHomeSheet = "widgets"; customizing = false }
                    Button("Manage Pages") { pendingHomeSheet = "pages"; customizing = false }
                    Button("Add Page") { addPage(); customizing = false; editing = true }
                    Button("App Library") { customizing = false; page = layout.pages.count + 1 }
                    Button("App Management") { customizing = false; openManagement() }
                    Button("Interface Options") { customizing = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { openInterface() } }
                }
                Section { StrataCreditsButton(location: "wallpaper.about") }
            }
            .navigationTitle("Wallpaper").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { customizing = false } } }
        }.navigationViewStyle(.stack)
        .sheet(isPresented: $choosingWallpaper) {
            StrataWallpaperMediaPicker { image, video, error in
                choosingWallpaper = false
                if let error { wallpaperError = error; return }
                if let image { do { let item = try wallpapers.add(image: image); selectedWallpaper = item.id; wallpaperStyle = "catalogue" } catch { wallpaperError = error.localizedDescription } }
                if let video { importWallpaperVideo(video, removeTemporary: true) }
            }
        }
        .fileImporter(isPresented: $importingWallpaper, allowedContentTypes: [.image, .movie]) { result in
            do {
                let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                if UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) == true {
                    wallpaperImportBusy = true
                    Task { defer { if access { url.stopAccessingSecurityScopedResource() }; wallpaperImportBusy = false }
                        do { let item = try await wallpapers.add(video: url); selectedWallpaper = item.id; wallpaperStyle = "catalogue" } catch { wallpaperError = error.localizedDescription }
                    }
                } else {
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    guard let image = UIImage(contentsOfFile: url.path) else { throw CocoaError(.fileReadCorruptFile) }
                    let item = try wallpapers.add(image: image, name: url.deletingPathExtension().lastPathComponent); selectedWallpaper = item.id; wallpaperStyle = "catalogue"
                }
            } catch { wallpaperError = error.localizedDescription }
        }
        .alert("Wallpaper", isPresented: Binding(get: { wallpaperError != nil }, set: { if !$0 { wallpaperError = nil } })) {
            Button("OK") { wallpaperError = nil }
        } message: { Text(wallpaperError ?? "") }
    }
    private var libraryGroups: [(String, [LCAppModel])] {
        let assignments = (try? JSONDecoder().decode([String: String].self, from: Data(categories.utf8))) ?? [:]
        let grouped = Dictionary(grouping: apps) { assignments[liveBoardAppKey($0)] ?? "Other" }
        return grouped.keys.sorted().map { ($0, grouped[$0] ?? []) }
    }
    private func openCategory(_ name: String) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.88)) { expandedCategory = name }
    }
    private func dismissCategory() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.88)) { expandedCategory = nil }
    }
    private var appLibrary: some View {
        GeometryReader { geometry in
            let side = max(120, (geometry.size.width - 48 - 18) / 2)
            VStack(spacing: 16) {
                Button { beginSearch() } label: {
                    Label("App Library", systemImage: "magnifyingglass").font(.system(size: 20))
                        .frame(maxWidth: .infinity).frame(height: 50).liveBoardGlass(radius: 25)
                }.buttonStyle(.plain).padding(.horizontal, 20)
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.fixed(side), spacing: 18), GridItem(.fixed(side))], alignment: .center, spacing: 20) {
                        ForEach(libraryGroups, id: \.0) { name, members in
                            libraryCategory(name, members: members, side: side)
                        }
                    }.padding(.horizontal, 24).padding(.bottom, 30)
                }
            }.padding(.top, 12)
        }.accessibilityIdentifier("home.appLibrary")
    }
    private func libraryCategory(_ name: String, members: [LCAppModel], side: CGFloat) -> some View {
        let icon = (side - 34) / 2
        return VStack(spacing: 7) {
            ZStack {
                Button { openCategory(name) } label: { Color.clear.frame(width: side, height: side).contentShape(Rectangle()) }
                    .buttonStyle(.plain).accessibilityLabel("Open " + name).accessibilityIdentifier("home.category." + name)
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        libraryLargeIcon(members.first, size: icon)
                        libraryLargeIcon(members.count > 1 ? members[1] : nil, size: icon)
                    }
                    HStack(spacing: 10) {
                        libraryLargeIcon(members.count > 2 ? members[2] : nil, size: icon)
                        Button { openCategory(name) } label: {
                            VStack(spacing: 4) {
                                ForEach(0..<2, id: \.self) { row in
                                    HStack(spacing: 4) {
                                        ForEach(0..<2, id: \.self) { column in
                                            let index = 3 + row * 2 + column
                                            Group {
                                                if members.indices.contains(index) {
                                                    LiveBoardIconImage(app: members[index], dark: darkIcons).clipShape(RoundedRectangle(cornerRadius: 6))
                                                } else { Color.clear }
                                            }.frame(width: (icon - 4) / 2, height: (icon - 4) / 2)
                                        }
                                    }
                                }
                            }.frame(width: icon, height: icon).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("Show all " + name).accessibilityIdentifier("home.category.expand." + name)
                    }
                }.padding(12).allowsHitTesting(true)
            }.frame(width: side, height: side).liveBoardGlass(radius: 28, interactive: false)
            Button { openCategory(name) } label: { Text(name).font(.system(size: 13)).lineLimit(2).multilineTextAlignment(.center).frame(width: side, height: 32, alignment: .top) }
                .buttonStyle(.plain).accessibilityLabel("Expand " + name)
        }.frame(width: side, height: side + 39)
    }
    @ViewBuilder private func libraryLargeIcon(_ app: LCAppModel?, size: CGFloat) -> some View {
        if let app {
            Button { launch(app) } label: {
                LiveBoardIconImage(app: app, dark: darkIcons).frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.23))
            }.buttonStyle(.plain).accessibilityLabel(appCustomization.name(app)).contextMenu { appMenu(liveBoardAppKey(app), app: app) }
        } else { Color.clear.frame(width: size, height: size).allowsHitTesting(false) }
    }
    private func expandedCategoryView(_ name: String) -> some View {
        GeometryReader { geometry in
            let members = libraryGroups.first(where: { $0.0 == name })?.1 ?? []
            let icon = min(78, (geometry.size.width - 40 - 48) / 4)
            let rows = CGFloat((members.count + 3) / 4)
            let height = rows * (icon + 18) + 60
            let top = max(70, (geometry.size.height - height) / 2 - 12)
            ZStack {
                wallpaperSurface(animate: false).blur(radius: 26)
                Color.black.opacity(0.12)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        Color.clear.frame(height: max(0, top - 22)).contentShape(Rectangle()).onTapGesture { dismissCategory() }
                        Text(name).font(.system(size: 30, weight: .bold)).accessibilityIdentifier("home.category.title")
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).onTapGesture { dismissCategory() }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 18) {
                            ForEach(members, id: \.self) { app in
                                Button { launch(app) } label: {
                                    LiveBoardIconImage(app: app, dark: darkIcons).frame(width: icon, height: icon)
                                        .clipShape(RoundedRectangle(cornerRadius: icon * 0.23))
                                }.buttonStyle(.plain).accessibilityLabel(appCustomization.name(app))
                                    .contextMenu { appMenu(liveBoardAppKey(app), app: app) }
                            }
                        }
                        Color.clear.frame(height: max(90, geometry.size.height - top - height)).contentShape(Rectangle()).onTapGesture { dismissCategory() }
                    }.padding(.horizontal, 20)
                        .frame(minHeight: geometry.size.height, alignment: .top)
                }
            }
            .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { value in
                if value.translation.height > 80 && abs(value.translation.width) < 70 { dismissCategory() }
            })
        }
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.expandedCategory").accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { dismissCategory() }
        .accessibilityAction(named: Text("Close category")) { dismissCategory() }
    }
    private var pagesSheet: some View {
        NavigationView {
            List {
                Section {
                    ForEach(layout.pages.indices, id: \.self) { index in
                        HStack {
                            Image(systemName: "square.grid.3x3").font(.title2).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Page \(index + 1)").font(.headline)
                                Text("\(layout.pages[index].compactMap { $0 }.count) items").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { page = index + 1; managingPages = false } label: { Image(systemName: page == index + 1 ? "checkmark.circle.fill" : "circle") }
                                .accessibilityLabel("Show page \(index + 1)")
                            Button(role: .destructive) { removingPage = index; showingRemovePage = true } label: { Image(systemName: "minus.circle.fill").padding(6) }
                                .disabled(layout.pages.count <= 1)
                                .accessibilityLabel("Remove page \(index + 1)").accessibilityIdentifier("home.removePage.\(index)")
                        }.buttonStyle(.borderless)
                    }
                } footer: { Text("Keep at least one Home page. Removing a page sends its apps to the App Library and removes its widgets.") }
                Button("Add Page", systemImage: "plus") { addPage() }.accessibilityIdentifier("home.addPage")
            }
            .navigationTitle("Home Pages").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { managingPages = false } } }
            .confirmationDialog("Remove Page \((removingPage ?? 0) + 1)?", isPresented: $showingRemovePage, titleVisibility: .visible, presenting: removingPage) { index in
                Button("Remove Page", role: .destructive) {
                    var updated = layout
                    let removed = updated.removePage(at: index)
                    layout = updated
                    for widget in removed { widgetPhotos.remove(widget.photo) }
                    page = min(max(1, page), layout.pages.count)
                    removingPage = nil
                }
                Button("Cancel", role: .cancel) { removingPage = nil }
            } message: { _ in Text("Apps stay installed and can be added back from the App Library. Widgets on this page will be removed. Other interfaces are unchanged.") }
        }.navigationViewStyle(.stack)
    }
    private func widgetConfiguration(_ id: String) -> some View {
        NavigationView {
            Form {
                if let widget = layout.widgets.first(where: { $0.id == id }) {
                    Section {
                        Picker("Widget size", selection: Binding(get: { layout.widgets.first { $0.id == id }?.size ?? .small }, set: { layout.resizeWidget(id, to: $0) })) {
                            Text("Small · 2 × 2").tag(LiveBoardHomeLayout.Widget.Size.small)
                            Text("Medium · 4 × 2").tag(LiveBoardHomeLayout.Widget.Size.medium)
                        }.pickerStyle(.segmented).accessibilityIdentifier("home.widget.size")
                        Picker("Background", selection: Binding(get: { layout.widgets.first { $0.id == id }?.appearance ?? .gradient }, set: { value in
                            if let index = layout.widgets.firstIndex(where: { $0.id == id }) { layout.widgets[index].appearance = value }
                        })) {
                            Text("Dark Gradient").tag(LiveBoardHomeLayout.Widget.Appearance.gradient)
                            Text("Liquid Glass").tag(LiveBoardHomeLayout.Widget.Appearance.glass)
                        }.pickerStyle(.segmented).accessibilityIdentifier("home.widget.background")
                        Picker("Page", selection: Binding(get: { layout.pages.firstIndex { $0.contains(id) } ?? 0 }, set: { layout.place(id, on: $0); page = $0 + 1 })) {
                            ForEach(layout.pages.indices, id: \.self) { index in Text("Page \(index + 1)").tag(index) }
                        }
                        if widget.kind == .photo {
                            Button("Change Photo", systemImage: "photo") {
                                widgetPhotoID = id; pendingWidgetPhoto = true; configuringWidget = nil
                            }
                        }
                    }
                    Button("Remove Widget", role: .destructive) { removeHomeWidget(id); configuringWidget = nil }
                }
            }
            .navigationTitle("Edit Widget").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { configuringWidget = nil } } }
        }.navigationViewStyle(.stack)
    }
    private var widgetGallery: some View {
        NavigationView {
            List {
                Section("Size") {
                    Picker("Widget size", selection: $widgetSize) {
                        Text("Small · 2 × 2").tag(LiveBoardHomeLayout.Widget.Size.small)
                        Text("Medium · 4 × 2").tag(LiveBoardHomeLayout.Widget.Size.medium)
                    }.pickerStyle(.segmented)
                }
                Section("Background") {
                    Picker("Background", selection: $widgetAppearance) {
                        Text("Dark Gradient").tag(LiveBoardHomeLayout.Widget.Appearance.gradient)
                        Text("Liquid Glass").tag(LiveBoardHomeLayout.Widget.Appearance.glass)
                    }.pickerStyle(.segmented)
                }
                Section {
                    ForEach(LiveBoardHomeLayout.Widget.Kind.allCases, id: \.self) { kind in
                        Button {
                            if kind == .photo {
                                widgetPhotoID = nil; pendingWidgetPhoto = true
                            } else { addHomeWidget(kind) }
                            addingWidget = false
                        } label: {
                            Label(kind.title, systemImage: kind.symbol).font(.headline).padding(.vertical, 12)
                        }.accessibilityIdentifier("home.addWidget.\(kind.rawValue)")
                    }
                } footer: { Text("Photo widgets keep a copy inside Strata. Clock, Calendar and Batteries show information from this device.") }
            }
            .navigationTitle("Add Widget").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { addingWidget = false } } }
        }.navigationViewStyle(.stack)
    }
    private func addHomeWidget(_ kind: LiveBoardHomeLayout.Widget.Kind, photo: String? = nil) {
        let widget = LiveBoardHomeLayout.Widget(kind: kind, size: widgetSize, photo: photo, appearance: widgetAppearance)
        let target = max(0, page - 1)
        layout.addWidget(widget, on: target)
        page = (layout.pages.firstIndex { $0.contains(widget.id) } ?? target) + 1
        editing = true
    }
    private func removeHomeWidget(_ id: String) {
        let file = layout.widgets.first { $0.id == id }?.photo
        layout.removeWidget(id); widgetPhotos.remove(file)
    }
    private func reconcile() { appMap = Dictionary(apps.map { (liveBoardAppKey($0), $0) }, uniquingKeysWith: { first, _ in first }); layout.reconcile(appKeys, favorites: favoriteKeys) }
    private func title(_ key: String) -> String { appMap[key].map { appCustomization.name($0) } ?? "App" }
    private func addPage() { layout.pages.append(Array(repeating: nil, count: LiveBoardHomeLayout.capacity)); page = layout.pages.count }
    private func setCategory(_ value: String?, key: String) {
        var map = (try? JSONDecoder().decode([String: String].self, from: Data(categories.utf8))) ?? [:]
        map[key] = value
        if let data = try? JSONEncoder().encode(map), let string = String(data: data, encoding: .utf8) { categories = string }
    }
    private func acceptDrop(_ providers: [NSItemProvider], apply: @escaping (String) -> Void) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
        provider.loadObject(ofClass: NSString.self) { value, _ in
            guard let key = value as? String else { return }
            DispatchQueue.main.async {
                guard appMap[key] != nil || layout.folders.contains(where: { $0.id == key }) || layout.widgets.contains(where: { $0.id == key }) else { return }
                apply(key)
            }
        }
        return true
    }
}

private struct LiveBoardHomeIcon: View {
    @ObservedObject var app: LCAppModel
    let title: String
    let size: CGFloat
    let showLabel: Bool
    let dark: Bool
    let editing: Bool
    let reduceMotion: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                LiveBoardIconImage(app: app, dark: dark)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
                    .overlay { if app.isSigningInProgress { ProgressView(value: app.signProgress).padding(8).background(.ultraThinMaterial) } }
                    .modifier(LiveBoardEditWobble(active: editing && !reduceMotion))
                if showLabel {
                    Text(title).font(.system(size: 12, weight: .regular)).lineLimit(1)
                        .foregroundColor(.white).shadow(color: .black.opacity(0.85), radius: 2, x: 0, y: 1).frame(width: 82)
                }
            }.contentShape(Rectangle())
        }
        .buttonStyle(LiveBoardHomePressStyle(reduceMotion: reduceMotion))
        .disabled(!editing && (app.isAppRunning || app.isSigningInProgress))
        .accessibilityLabel(title)
        .accessibilityHint(editing ? "Drag to rearrange" : "Launch app. Touch and hold for more actions.")

    }
}
private struct LiveBoardEditWobble: ViewModifier {
    let active: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if active {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { time in
                content.rotationEffect(.degrees(sin(time.date.timeIntervalSinceReferenceDate * 22) * 1.4))
            }
        } else {
            content.rotationEffect(.zero).transaction { $0.animation = nil; $0.disablesAnimations = true }
        }
    }
}
private struct LiveBoardHomePressStyle: ButtonStyle {
    let reduceMotion: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
struct LiveBoardIconImage: View {
    @ObservedObject var app: LCAppModel
    @ObservedObject private var customization = LiveBoardAppCustomization.shared
    let dark: Bool
    var body: some View {
        Group {
            if let image = LiveBoardIconStore.image(app, dark: dark) { Image(uiImage: image).resizable().scaledToFill() }
            else {
                ZStack { Color(white: 0.2); Image(systemName: "app.dashed").resizable().scaledToFit().padding(14).foregroundColor(.white.opacity(0.6)) }
            }
        }.aspectRatio(1, contentMode: .fit)
    }
}

/// Original procedural wallpaper; user photos are rendered separately, without app-bundle changes.
struct LiveBoardRibbonWallpaper: View {
    let blue: Bool
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                Ellipse().fill(RadialGradient(colors: [accent.opacity(0.45), accent.opacity(0.08), .black], center: .center, startRadius: 0, endRadius: geometry.size.height * 0.48))
                    .frame(width: geometry.size.width * 1.5, height: geometry.size.height * 0.9).rotationEffect(.degrees(-20)).offset(x: -40, y: -70)
                ForEach(0..<3) { index in
                    Ellipse().stroke(LinearGradient(colors: [.black, accent.opacity(0.6), .black, accent.opacity(0.9), .black], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 3 + CGFloat(index) * 1.5)
                        .background(Ellipse().fill(LinearGradient(colors: [.black.opacity(0.9), accent.opacity(0.22), .black], startPoint: .topLeading, endPoint: .bottomTrailing)))
                        .frame(width: geometry.size.width * (0.7 + Double(index) * 0.13), height: geometry.size.height * (0.65 - Double(index) * 0.1))
                        .rotationEffect(.degrees(Double(index) * 38 - 34)).offset(x: CGFloat(index - 1) * 32, y: CGFloat(index - 1) * 35)
                }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
    }
    private var accent: Color { blue ? Color(red: 0.04, green: 0.25, blue: 0.85) : Color(red: 0.7, green: 0.035, blue: 0.01) }
}

struct LiveBoardWallpaperPicker: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion) }
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(); config.filter = .images; config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config); picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let completion: (UIImage?) -> Void
        init(_ completion: @escaping (UIImage?) -> Void) { self.completion = completion }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let item = results.first?.itemProvider, item.canLoadObject(ofClass: UIImage.self) else { completion(nil); return }
            item.loadObject(ofClass: UIImage.self) { image, _ in DispatchQueue.main.async { self.completion(image as? UIImage) } }
        }
    }
}

private struct LiveBoardGlassSurface: ViewModifier {
    let radius: CGFloat
    let interactive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if reduceTransparency {
            content.background(Color(white: 0.16), in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.clear.interactive(interactive), in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.04), .white.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.6))
        }
    }
}
extension View {
    func liveBoardGlass(radius: CGFloat, interactive: Bool = true) -> some View {
        modifier(LiveBoardGlassSurface(radius: radius, interactive: interactive))
    }
}
