import AppKit
import ServiceManagement
import SwiftUI
import TrayCore

struct FlaredShelf: Shape {
    var progress: CGFloat
    var originX: CGFloat
    var joinHeight: CGFloat

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    nonisolated func path(in rect: CGRect) -> Path {
        Path(ShelfSurface.liquidPath(in: rect, progress: progress, originX: originX, joinHeight: joinHeight))
    }
}

private struct ItemFramesKey: PreferenceKey {
    nonisolated static var defaultValue: [UInt32: CGRect] { [:] }
    nonisolated static func reduce(value: inout [UInt32: CGRect], nextValue: () -> [UInt32: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

struct ShelfView: View {
    @ObservedObject var controller: TrayController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reveal: CGFloat = 0

    var body: some View {
        Group {
            if controller.items.isEmpty && controller.isRefreshing {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if controller.items.isEmpty {
                Button { controller.arrange() } label: {
                    Text("Choose menu bar icons…").font(.system(size: 11))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(controller.items) { item in
                            Button { controller.activate(item) } label: {
                                Group {
                                    if let image = item.image {
                                        Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                                    } else {
                                        Image(systemName: "ellipsis").font(.system(size: 12))
                                    }
                                }
                                .frame(width: item.isLiveImage ? item.frame.width : 18, height: item.isLiveImage ? controller.rowHeight : 18)
                                .frame(width: ShelfSurface.cellWidth(itemWidth: item.frame.width), height: controller.rowHeight)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(TrayButtonStyle())
                            .opacity(controller.shelfDraggedItemID == item.id || controller.movingItemID == item.id ? 0.25 : 1)
                            .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.12), value: controller.movingItemID)
                            .transition(.opacity)
                            .overlay(CommandDragSource(item: item, controller: controller))
                            .background {
                                GeometryReader { geometry in
                                    Color.clear.preference(key: ItemFramesKey.self,
                                        value: [item.id: geometry.frame(in: .named("Shelf"))])
                                }
                            }
                            .help(item.name + (item.isLiveImage ? "" : " (waiting for the native menu bar icon)"))
                            .accessibilityLabel(item.name)
                            .accessibilityIdentifier("menu-item-\(item.id)")
                            .contextMenu {
                                Button("Open menu") { controller.activate(item) }
                                Button("Move to Menu Bar") { controller.moveToMenuBar(item) }
                                    .disabled(controller.movingItemID != nil)
                                Divider()
                                Button("Arrange icons…") { controller.arrange() }
                            }
                        }
                    }
                    .animation(reduceMotion ? nil : .timingCurve(0.23, 1, 0.32, 1, duration: 0.18),
                               value: controller.items.map(\.id))
                }
                .frame(height: controller.rowHeight)
            }
        }
        .frame(height: controller.rowHeight)
        .padding(.horizontal, ShelfSurface.flare)
        .padding(.top, controller.shelfJoinHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(Double(min(1, max(0, reveal))))
        .background {
            WallpaperSurface(snapshot: controller.wallpaper, joinHeight: controller.shelfJoinHeight)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .topLeading) {
            if let x = controller.shelfDropIndicatorX {
                RoundedRectangle(cornerRadius: 1)
                    .fill(.primary.opacity(0.8))
                    .frame(width: 2, height: max(1, controller.rowHeight - 10))
                    .offset(x: x - 1, y: controller.shelfJoinHeight + 5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .clipShape(FlaredShelf(progress: reduceMotion ? 1 : reveal, originX: controller.shelfOriginX, joinHeight: controller.shelfJoinHeight))
        .contentShape(FlaredShelf(progress: reduceMotion ? 1 : reveal, originX: controller.shelfOriginX, joinHeight: controller.shelfJoinHeight))
        .opacity(reduceMotion ? Double(min(1, max(0, reveal))) : 1)
        .allowsHitTesting(controller.shelfPresented)
        .coordinateSpace(name: "Shelf")
        .onPreferenceChange(ItemFramesKey.self) { controller.itemFrames = $0 }
        .onChange(of: controller.shelfPresentationRevision, initial: true) { _, revision in
            let shown = controller.shelfPresented
            let animation: Animation? = controller.animatesShelf
                ? (reduceMotion
                   ? .timingCurve(0.23, 1, 0.32, 1, duration: 0.12)
                   : shown ? .spring(duration: 0.25, bounce: 0.2)
                   : .timingCurve(0.23, 1, 0.32, 1, duration: 0.16))
                : nil
            withAnimation(animation, completionCriteria: .removed) {
                reveal = shown ? 1 : 0
            } completion: {
                controller.finishShelfTransition(revision: revision)
            }
        }
    }
}

struct TrayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.primary.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7))
    }
}

struct SetupView: View {
    @ObservedObject var controller: TrayController

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(nsImage: NSImage(named: "MenuBarBar") ?? NSImage())
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 56, height: 56)
                    .accessibilityLabel("Menu Bar Bar")
                VStack(alignment: .leading, spacing: 4) {
                    Text("A little room for your menu bar.").font(.system(size: 19, weight: .semibold))
                    Text("Keep your utilities together, one click away.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Choose what goes inside").font(.headline)
                Text("Hold ⌘ Command and drop a menu bar icon onto Menu Bar Bar’s chevron to bundle it. Command-drag within the bundle to reorder, or drag out to return an icon to the menu bar. Use Arrange for manual placement.")
                    .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Image(systemName: "command").foregroundStyle(.secondary)
                    Text("Icons to bundle").font(.system(size: 12))
                    Image(systemName: "arrow.left").foregroundStyle(.secondary)
                    Image(systemName: "line.diagonal").foregroundStyle(.blue)
                    Image(systemName: "chevron.down")
                    Text("Keep visible").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                HStack {
                    Text(controller.items.isEmpty ? "No icons to the left of the divider yet." : "\(controller.items.count) menu bar item\(controller.items.count == 1 ? "" : "s") ready to bundle.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    if !controller.isArranging {
                        Menu("Add an icon…") {
                            ForEach(controller.availableToBundle) { available in
                                Button(available.name) { controller.bundleStatusItem(available.window) }
                            }
                        }
                        .fixedSize()
                        .disabled(controller.availableToBundle.isEmpty || controller.movingItemID != nil)
                        Button("Arrange…") { controller.arrange() }
                    }
                }
            }

            VStack(spacing: 13) {
                permissionRow("Screen Recording", detail: "Show real menu bar icons and the wallpaper behind the shelf. Captures stay on this Mac.", granted: controller.screenAccess) {
                    MenuItems.requestScreenAccess()
                }
                Divider()
                permissionRow("Accessibility", detail: "Open each app’s original menu when you click its tray icon.", granted: controller.accessibilityAccess) {
                    controller.requestAccessibility()
                }
            }
            .padding(14)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))

            if !controller.message.isEmpty {
                Text(controller.message).font(.system(size: 12)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Toggle("Open at login", isOn: Binding(get: { SMAppService.mainApp.status == .enabled }, set: { controller.setLaunchAtLogin($0) }))
                    .toggleStyle(.checkbox).font(.system(size: 12))
                Spacer()
                Button(controller.isArranging && !controller.items.isEmpty ? "Open bundle" : "Preview") { controller.previewShelf() }
                Button(controller.isArranging ? "Collapse into Menu Bar Bar" : "Done") { controller.finishSetup() }
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.isArranging && controller.items.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
            Text("Click the chevron to open Menu Bar Bar. Escape or a click outside closes it. Right-click the chevron for options. Quit Menu Bar Bar to restore every icon.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(26)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func permissionRow(_ title: String, detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(granted ? "Enabled" : "Enable…", action: action).disabled(granted)
        }
    }
}
