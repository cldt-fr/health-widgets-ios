import SwiftUI

extension View {
    /// DEBUG: `-scrollTo <id>` scrolls to the view tagged with that id on launch, to
    /// capture any part of a screen from the command line (and for App Store shots).
    func debugScrollTarget(_ proxy: ScrollViewProxy) -> some View {
        #if DEBUG
        onAppear {
            guard let target = UserDefaults.standard.string(forKey: "scrollTo") else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                proxy.scrollTo(target, anchor: .top)
            }
        }
        #else
        self
        #endif
    }
}

#if DEBUG
import WidgetKit

/// DEBUG: `-exportWidgets` renders a few widgets with the demo data at 8× (dark and light)
/// into Documents/widgets-export, as building blocks for App Store artwork.
enum WidgetArtworkExporter {
    static func runIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-exportWidgets") else { return }
        var snapshot = DemoData.snapshot()
        snapshot.source.deviceName = nil  // no third-party product names in store artwork
        let folder = URL.documentsDirectory.appending(path: "widgets-export")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let small = CGSize(width: 170, height: 170)
        let medium = CGSize(width: 364, height: 170)

        func entry(_ kind: MetricKind) -> HealthEntry {
            HealthEntry(date: DemoData.clock, snapshot: snapshot, metric: kind)
        }

        func save<V: View>(_ name: String, _ size: CGSize, _ view: V) {
            for scheme in [ColorScheme.dark, .light] {
                let renderer = ImageRenderer(
                    content: view
                        .frame(width: size.width, height: size.height)
                        .environment(\.colorScheme, scheme)
                )
                renderer.scale = 8
                let file = folder.appending(path: "\(name)-\(scheme == .dark ? "dark" : "light").png")
                if let data = renderer.uiImage?.pngData() { try? data.write(to: file) }
            }
        }

        save("overview", medium, WidgetPreviewFrame(family: .systemMedium, kind: .readiness) {
            OverviewWidgetView(entry: entry(.readiness), family: .systemMedium)
        })
        save("sleep", medium, WidgetPreviewFrame(family: .systemMedium, kind: .sleep) {
            MetricWidgetView(entry: entry(.sleep), family: .systemMedium)
        })
        save("steps", small, WidgetPreviewFrame(family: .systemSmall, kind: .steps) {
            MetricWidgetView(entry: entry(.steps), family: .systemSmall)
        })
        save("battery", small, WidgetPreviewFrame(family: .systemSmall, kind: .bodyBattery) {
            MetricWidgetView(entry: entry(.bodyBattery), family: .systemSmall)
        })
        for kind in [TrainingKind.recovery, .load, .predictions, .plan] {
            save(kind.rawValue, small, WidgetPreviewFrame(family: .systemSmall, colors: kind.colors) {
                TrainingWidgetView(kind: kind, entry: entry(.readiness), family: .systemSmall)
            })
        }
        save("week-medium", medium, WidgetPreviewFrame(family: .systemMedium, colors: TrainingKind.week.colors) {
            TrainingWidgetView(kind: .week, entry: entry(.readiness), family: .systemMedium)
        })
        // Home Screen mock-up at 3x: the size of an iPhone 17 Pro screenshot (1206 x 2622).
        let wallpaper = URL.documentsDirectory.appending(path: "wallpaper.jpg")
        if let image = UIImage(contentsOfFile: wallpaper.path()) {
            let renderer = ImageRenderer(
                content: HomeScreenMock(wallpaper: image, snapshot: snapshot)
                    .environment(\.colorScheme, .dark)
            )
            renderer.scale = 3
            if let data = renderer.uiImage?.pngData() {
                try? data.write(to: folder.appending(path: "home-screen.png"))
            }
        }
        print("[exportWidgets] \(folder.path)")
    }
}

/// Widgets laid out like on an iPhone 17 Pro Home Screen (402 x 874 pt), for store artwork.
private struct HomeScreenMock: View {
    var wallpaper: UIImage
    var snapshot: DashboardSnapshot

    private func entry(_ kind: MetricKind) -> HealthEntry {
        HealthEntry(date: DemoData.clock, snapshot: snapshot, metric: kind)
    }

    var body: some View {
        VStack(spacing: 24) {
            WidgetPreviewFrame(family: .systemMedium, kind: .readiness) {
                OverviewWidgetView(entry: entry(.readiness), family: .systemMedium)
            }
            .frame(width: 364)
            HStack(spacing: 24) {
                WidgetPreviewFrame(family: .systemSmall, kind: .steps) {
                    MetricWidgetView(entry: entry(.steps), family: .systemSmall)
                }
                WidgetPreviewFrame(family: .systemSmall, colors: TrainingKind.recovery.colors) {
                    TrainingWidgetView(kind: .recovery, entry: entry(.readiness), family: .systemSmall)
                }
            }
            WidgetPreviewFrame(family: .systemMedium, kind: .sleep) {
                MetricWidgetView(entry: entry(.sleep), family: .systemMedium)
            }
            .frame(width: 364)
            HStack(spacing: 24) {
                WidgetPreviewFrame(family: .systemSmall, colors: TrainingKind.load.colors) {
                    TrainingWidgetView(kind: .load, entry: entry(.readiness), family: .systemSmall)
                }
                WidgetPreviewFrame(family: .systemSmall, colors: TrainingKind.predictions.colors) {
                    TrainingWidgetView(kind: .predictions, entry: entry(.readiness), family: .systemSmall)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 70)
        .frame(width: 402, height: 874)
        .background {
            Image(uiImage: wallpaper)
                .resizable()
                .scaledToFill()
                .frame(width: 402, height: 874)
                .clipped()
        }
        .overlay(alignment: .top) {
            HStack {
                Text(DemoData.clock, format: .dateTime.hour().minute())
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 134)
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "cellularbars")
                    Image(systemName: "wifi")
                    Image(systemName: "battery.100percent")
                }
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 134)
            }
            .foregroundStyle(.white)
            .frame(height: 50)
        }
    }
}
#endif
