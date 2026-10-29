import SwiftUI
import UIKit
import ImageIO

/// Widget photos are owned copies, not links into the user's Photos library.
@MainActor final class LiveBoardWidgetPhotos: ObservableObject {
    static let shared = LiveBoardWidgetPhotos()
    private let cache = NSCache<NSString, UIImage>()
    init() { cache.countLimit = 12; cache.totalCostLimit = 32 * 1024 * 1024 }
    var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Strata/Widgets", isDirectory: true)
    }
    private func url(_ name: String) -> URL? {
        guard name.hasSuffix(".jpg"), UUID(uuidString: String(name.dropLast(4))) != nil else { return nil }
        return directory.appendingPathComponent(name)
    }
    func image(_ name: String?) -> UIImage? {
        guard let name, let file = url(name) else { return nil }
        if let image = cache.object(forKey: name as NSString) { return image }
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1024] as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cg)
        cache.setObject(image, forKey: name as NSString, cost: cg.bytesPerRow * cg.height)
        return image
    }
    func save(_ image: UIImage) throws -> String {
        guard image.size.width > 0, image.size.height > 0 else { throw CocoaError(.fileReadCorruptFile) }
        let factor = min(1, 2000 / max(image.size.width, image.size.height))
        let size = CGSize(width: max(1, image.size.width * factor), height: max(1, image.size.height * factor))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let copy = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let data = copy.jpegData(compressionQuality: 0.9) else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = UUID().uuidString + ".jpg"
        try data.write(to: directory.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        // Decode only a display-sized thumbnail when this photo first appears.
        cache.removeObject(forKey: name as NSString)
        return name
    }
    func remove(_ name: String?) {
        guard let name, let file = url(name) else { return }
        try? FileManager.default.removeItem(at: file); cache.removeObject(forKey: name as NSString)
    }
}

extension LiveBoardHomeLayout.Widget.Kind {
    var title: String {
        switch self { case .photo: return "Photos"; case .clock: return "Clock"; case .calendar: return "Calendar"; case .battery: return "Batteries" }
    }
    var symbol: String {
        switch self { case .photo: return "photo.on.rectangle"; case .clock: return "clock"; case .calendar: return "calendar"; case .battery: return "battery.100percent" }
    }
}

struct LiveBoardHomeWidgetCard: View {
    let widget: LiveBoardHomeLayout.Widget
    var photo: UIImage?
    @State private var batteryLevel: Float = -1
    @State private var batteryCharging = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            GeometryReader { geometry in
                Group {
                    if widget.kind == .photo {
                        if let photo {
                            Image(uiImage: photo).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped()
                        } else {
                            VStack(spacing: 12) { Image(systemName: "photo").font(.largeTitle); Text("Choose Photo").font(.caption) }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else if widget.kind == .clock {
                        HStack(spacing: 14) {
                            analogClock(timeline.date).frame(width: min(geometry.size.height - 28, geometry.size.width - 28), height: min(geometry.size.height - 28, geometry.size.width - 28))
                            if widget.size == .medium {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(timeline.date, style: .time).font(.system(size: 30, weight: .light, design: .rounded)).minimumScaleFactor(0.7)
                                    Text(timeline.date, format: .dateTime.weekday(.wide)).font(.subheadline).foregroundStyle(.white.opacity(0.7))
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.padding(14)
                    } else if widget.kind == .calendar {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(timeline.date, format: .dateTime.weekday(.wide)).textCase(.uppercase).font(.system(size: 12, weight: .semibold)).foregroundStyle(.red)
                                Text(timeline.date, format: .dateTime.day()).font(.system(size: 58, weight: .light, design: .rounded))
                                Text(timeline.date, format: .dateTime.month(.wide)).font(.system(size: 14, weight: .medium))
                            }
                            if widget.size == .medium {
                                Spacer(minLength: 16)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(timeline.date, format: .dateTime.year()).font(.headline)
                                    Text(timeline.date, format: .dateTime.month(.wide).day()).font(.subheadline)
                                    Text("Today").font(.caption).foregroundStyle(.white.opacity(0.65))
                                }
                            }
                            Spacer(minLength: 0)
                        }.padding(18)
                    } else {
                        battery
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .modifier(LiveBoardWidgetBackground(appearance: widget.appearance))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onAppear {
            if widget.kind == .battery { UIDevice.current.isBatteryMonitoringEnabled = true; refreshBattery() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in refreshBattery() }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in refreshBattery() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(widget.kind.title + " widget")
    }
    private func analogClock(_ date: Date) -> some View {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minute = Double(components.minute ?? 0), hour = Double((components.hour ?? 0) % 12)
        return GeometryReader { g in
            let radius = g.size.width / 2
            ZStack {
                Circle().fill(.white)
                ForEach(1...12, id: \.self) { n in
                    Text("\(n)").font(.system(size: max(9, radius * 0.23), weight: .medium, design: .rounded)).foregroundStyle(.black)
                        .position(x: radius + sin(Double(n) * .pi / 6) * radius * 0.78,
                                  y: radius - cos(Double(n) * .pi / 6) * radius * 0.78)
                }
                Capsule().fill(.black).frame(width: 4, height: radius * 0.46).offset(y: -radius * 0.23).rotationEffect(.degrees(hour * 30 + minute * 0.5))
                Capsule().fill(.black).frame(width: 3, height: radius * 0.66).offset(y: -radius * 0.33).rotationEffect(.degrees(minute * 6))
                Circle().fill(.black).frame(width: 7, height: 7)
            }
        }
    }
    private func refreshBattery() {
        guard widget.kind == .battery else { return }
        batteryLevel = UIDevice.current.batteryLevel
        batteryCharging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
    }
    private var battery: some View {
        let level = batteryLevel
        let charging = batteryCharging
        return VStack(alignment: .leading, spacing: 10) {
            HStack { Image(systemName: "iphone").font(.system(size: 24)); Spacer(); if charging { Image(systemName: "bolt.fill").foregroundStyle(.green) } }
            Spacer(minLength: 0)
            Text(level < 0 ? "—" : "\(Int((level * 100).rounded()))%")
                .font(.system(size: 36, weight: .medium, design: .rounded))
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule().fill(level >= 0 && level < 0.2 ? Color.red : Color.green).frame(width: geometry.size.width * CGFloat(max(0, level)))
                }
            }.frame(height: 6)
        }.padding(18)
    }
}

private struct LiveBoardWidgetBackground: ViewModifier {
    let appearance: LiveBoardHomeLayout.Widget.Appearance
    func body(content: Content) -> some View {
        if appearance == .glass {
            content.liveBoardGlass(radius: 26)
        } else {
            content.background(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.035)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        }
    }
}
