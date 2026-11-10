import SwiftUI
import UniformTypeIdentifiers

/// Tools share the same two-column footprint as Home Screen widgets. Preferences
/// belong to the tools page, so changing these never moves Home Screen widgets.
struct StrataToolsPage: View {
    struct Tool: Identifiable {
        let id: String
        let title: String
        let detail: String
        let symbol: String
        var disabled = false
        let action: () -> Void
    }
    let tools: [Tool]
    @AppStorage("StrataToolWidths", store: LCUtils.appGroupUserDefault) private var widths = "{}"
    @AppStorage("StrataToolStyles", store: LCUtils.appGroupUserDefault) private var styles = "{}"

    @AppStorage("StrataToolsLayout", store: LCUtils.appGroupUserDefault) private var savedLayout = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editing = false
    @State private var adding = false
    @State private var dragged: String?
    private var layout: StrataToolsLayout { StrataToolsLayout(saved: savedLayout) }
    private var available: [String] { tools.map(\.id) }
    private var visibleTools: [Tool] {
        let map = Dictionary(uniqueKeysWithValues: tools.map { ($0.id, $0) })
        return layout.visible(available: available).compactMap { map[$0] }
    }
    private var wide: [String: Bool] { (try? JSONDecoder().decode([String: Bool].self, from: Data(widths.utf8))) ?? [:] }
    private var glass: [String: Bool] { (try? JSONDecoder().decode([String: Bool].self, from: Data(styles.utf8))) ?? [:] }
    private var rows: [[Tool]] {
        var result: [[Tool]] = []
        for tool in visibleTools {
            if wide[tool.id] == true { result.append([tool]) }
            else if let last = result.last, last.count == 1, wide[last[0].id] != true { result[result.count - 1].append(tool) }
            else { result.append([tool]) }
        }
        return result
    }
    var body: some View {
        GeometryReader { geometry in
            let side = max(1, (geometry.size.width - 60) / 2)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    if editing {
                    HStack {
                        Button { adding = true } label: { Image(systemName: "plus").frame(width: 42, height: 36) }.liveBoardGlass(radius: 18)
                            .accessibilityLabel("Add tools widgets").accessibilityIdentifier("tools.add")
                        Spacer()
                        Button { editing.toggle(); dragged = nil } label: {
                            Image(systemName: editing ? "checkmark" : "slider.horizontal.3").frame(width: 42, height: 36)
                        }.liveBoardGlass(radius: 18).accessibilityLabel(editing ? "Done editing tools" : "Edit tools")
                            .accessibilityIdentifier("tools.edit")
                    }
                    }
                    if visibleTools.isEmpty { Text("Touch and hold to add widgets").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 180).contentShape(Rectangle()).onLongPressGesture { editing = true } }
                    ForEach(rows.indices, id: \.self) { index in
                        HStack(spacing: 16) {
                            ForEach(rows[index]) { tool in
                                card(tool, width: wide[tool.id] == true ? side * 2 + 16 : side, height: side)
                            }
                            if rows[index].count == 1 && wide[rows[index][0].id] != true { Spacer(minLength: 0) }
                        }
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: savedLayout)
                .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 36)
            }
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.018), .init(color: .black, location: 0.97), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            .accessibilityIdentifier("home.controls.scroll")
        }
        .sheet(isPresented: $adding) { catalogue }
    }
    private var catalogue: some View {
        NavigationView {
            List {
                ForEach(tools) { tool in
                    let shown = !layout.hidden.contains(tool.id)
                    Button {
                        var value = layout; value.add(tool.id, available: available); savedLayout = value.encoded
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: tool.symbol).font(.title2).frame(width: 36)
                            VStack(alignment: .leading, spacing: 4) { Text(tool.title); Text(tool.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                            Spacer()
                            Image(systemName: shown ? "checkmark.circle.fill" : "plus.circle.fill")
                        }.padding(.vertical, 8).contentShape(Rectangle())
                    }.disabled(shown).accessibilityIdentifier("tools.catalogue.\(tool.id)")
                }
            }
            .navigationTitle("Add Widgets").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { adding = false } } }
        }
    }
    private func card(_ tool: Tool, width: CGFloat, height: CGFloat) -> some View {
        Button { if !editing && !tool.disabled { tool.action() } } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: tool.symbol).font(.system(size: 26)).foregroundStyle(.white.opacity(0.95))
                Spacer(minLength: 0)
                Text(tool.title).font(.system(size: 17, weight: .semibold)).lineLimit(2)
                Text(tool.detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7)).lineLimit(3)
            }
            .padding(18)
            .frame(width: width, height: height, alignment: .leading)
            .modifier(StrataToolSurface(glass: glass[tool.id] ?? true))
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(tool.disabled ? 0.5 : 1)
        .accessibilityIdentifier("home.controls.\(tool.id)")
        .contextMenu {
            Button("Edit Widgets") { editing = true }
            Button("Remove Widget", role: .destructive) { remove(tool.id) }
            Section("Widget size") {
                Button { setWidth(tool.id, false) } label: { Label("2 × 2", systemImage: wide[tool.id] == true ? "square" : "checkmark") }
                Button { setWidth(tool.id, true) } label: { Label("4 × 2", systemImage: wide[tool.id] == true ? "checkmark" : "rectangle") }
            }
            Section("Appearance") {
                Button("Glass") { setStyle(tool.id, true) }
                Button("Dark gradient") { setStyle(tool.id, false) }
            }
        }
        .overlay(alignment: .topLeading) {
            if editing {
                Button { remove(tool.id) } label: { Image(systemName: "minus").font(.system(size: 13, weight: .bold)).frame(width: 28, height: 28).liveBoardGlass(radius: 14) }
                    .buttonStyle(.plain).offset(x: -5, y: -5).accessibilityLabel("Remove \(tool.title) widget").accessibilityIdentifier("tools.remove.\(tool.id)")
            }
        }
        .onDrag {
            dragged = tool.id
            return NSItemProvider(object: ("strata-tool:" + tool.id) as NSString)
        }
        .onDrop(of: [UTType.text], delegate: StrataToolDrop(dragged: $dragged, target: tool.id) { source, target in
            var value = layout; value.move(source, to: target, available: available); savedLayout = value.encoded
        })
        .accessibilityAction(named: "Move earlier") { move(tool.id, offset: -1) }
        .accessibilityAction(named: "Move later") { move(tool.id, offset: 1) }
    }
    private func remove(_ id: String) { var value = layout; value.remove(id); savedLayout = value.encoded }
    private func move(_ id: String, offset: Int) {
        let ids = layout.visible(available: available)
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return }
        var value = layout; value.move(id, to: ids[index + offset], available: available); savedLayout = value.encoded
    }
    private func setWidth(_ key: String, _ value: Bool) {
        var updated = wide; updated[key] = value
        if let data = try? JSONEncoder().encode(updated), let string = String(data: data, encoding: .utf8) { widths = string }
    }
    private func setStyle(_ key: String, _ value: Bool) {
        var updated = glass; updated[key] = value
        if let data = try? JSONEncoder().encode(updated), let string = String(data: data, encoding: .utf8) { styles = string }
    }
}
private struct StrataToolSurface: ViewModifier {
    let glass: Bool
    func body(content: Content) -> some View {
        if glass { content.liveBoardGlass(radius: 28) }
        else {
            content.background(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.035)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.13), lineWidth: 0.8))
        }
    }
}

private struct StrataToolDrop: DropDelegate {
    @Binding var dragged: String?
    let target: String
    let move: (String, String) -> Void
    func validateDrop(info: DropInfo) -> Bool { dragged != nil }
    func dropEntered(info: DropInfo) {
        guard let source = dragged, source != target else { return }
        move(source, target)
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { dragged = nil; return true }
}
