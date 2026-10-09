import AppKit
import SwiftUI
import LayoutCore

private let rememberAccent = Color(red: 0.12, green: 0.65, blue: 0.56)

struct DashboardView: View {
    @ObservedObject var engine: LayoutEngine
    @State private var selectedProfile: String?
    @State private var renameTarget: LayoutProfile?

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !engine.hasPermission { permissionCard }
                    currentSetupCard
                    if let issue = engine.issue { issueCard(issue) }
                    rememberedSetups
                    settingsCard
                }
                .padding(22)
                .padding(.top, 2)
            }
            footer
        }
        .frame(minWidth: 440, idealWidth: 460, maxWidth: .infinity, minHeight: 600, idealHeight: 710)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(rememberAccent)
        .sheet(item: $renameTarget) { profile in
            RenameProfileView(profile: profile) { name in engine.renameProfile(id: profile.id, name: name) }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(LinearGradient(colors: [rememberAccent, Color(red: 0.13, green: 0.36, blue: 0.42)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 3) {
                Text("Remember").font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("Your windows. Right where you left them.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("Show layout file in Finder", action: engine.revealData)
                Divider()
                Button("Quit Remember") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            } label: { Image(systemName: "ellipsis").font(.system(size: 17)) }
                .menuStyle(.borderlessButton)
                .frame(width: 25)
                .help("More options")
                .accessibilityLabel("More options")
        }
        .padding(22)
        .padding(.bottom, 0)
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("Let Remember move your windows", systemImage: "hand.raised")
                .font(.system(size: 13, weight: .semibold))
            Text("Enable Remember in System Settings → Privacy & Security → Accessibility. It will start watching your layout as soon as access is enabled.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Enable Accessibility", action: engine.enableAccessibility)
                .buttonStyle(.borderedProminent).controlSize(.regular)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rememberAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(rememberAccent.opacity(0.16)))
    }

    private var currentSetupCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("CURRENT SETUP").font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(rememberAccent).frame(width: 5, height: 5)
                    Text("Connected").font(.system(size: 10, weight: .medium)).foregroundStyle(rememberAccent)
                }
            }
            HStack(spacing: 8) {
                Text(engine.currentProfile?.name ?? engine.setup.suggestedName)
                    .font(.system(size: 17, weight: .semibold)).lineLimit(2)
                if let profile = engine.currentProfile {
                    Button { renameTarget = profile } label: { Image(systemName: "pencil").font(.system(size: 11)) }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Rename this setup")
                }
                Spacer()
            }
            LayoutPreview(displays: engine.setup.displays,
                          windows: engine.liveWindows.isEmpty ? (engine.currentProfile?.windows ?? []) : engine.liveWindows)
                .frame(height: 130)
                .padding(.horizontal, 6)
                .background(Color(red: 0.055, green: 0.12, blue: 0.15), in: RoundedRectangle(cornerRadius: 12))
            HStack(spacing: 6) {
                Image(systemName: engine.isLaptopMaximized ? "arrow.up.left.and.arrow.down.right" : "rectangle.3.group")
                Text(engine.isLaptopMaximized ? "Windows fill the built-in screen" : "\(engine.setup.displays.count) displays · \(engine.liveWindowCount) open windows")
            }.font(.system(size: 11)).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button(action: engine.restoreNow) {
                    Label("Restore layout", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).disabled(!engine.canRestore)
                Button(action: engine.saveNow) {
                    Label("Save now", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(.bordered).disabled(!engine.canSave)
            }.controlSize(.large).font(.system(size: 12, weight: .medium))
        }
        .padding(17)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.06)))
    }

    @ViewBuilder
    private var rememberedSetups: some View {
        if engine.state.profiles.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text("Set it up once. Settle in anywhere.").font(.system(size: 13, weight: .medium))
                Text("Arrange your apps side by side on your work monitor. Remember saves the layout, then brings it back when you reconnect.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(.horizontal, 2)
        } else {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("REMEMBERED SETUPS").font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(engine.state.profiles.count)").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                }
                ForEach(engine.state.profiles.sorted { $0.updatedAt > $1.updatedAt }) { profile in
                    VStack(spacing: 0) {
                        Button {
                            selectedProfile = selectedProfile == profile.id ? nil : profile.id
                        } label: {
                            HStack(spacing: 11) {
                                Image(systemName: profile.displays.allSatisfy(\.isBuiltIn) ? "laptopcomputer" : "display.2")
                                    .font(.system(size: 17)).foregroundStyle(profile.id == engine.setup.signature ? rememberAccent : .secondary)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(profile.name).font(.system(size: 12, weight: .medium)).foregroundStyle(.primary).lineLimit(1)
                                    Text("\(profile.windows.count) remembered windows · \(profile.updatedAt.formatted(.relative(presentation: .named)))")
                                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                if profile.id == engine.setup.signature {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(rememberAccent).font(.system(size: 12))
                                }
                                Image(systemName: selectedProfile == profile.id ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                            }.padding(12).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        if selectedProfile == profile.id {
                            LayoutPreview(displays: profile.displays, windows: profile.windows)
                                .frame(height: 112).background(Color(red: 0.055, green: 0.12, blue: 0.15), in: RoundedRectangle(cornerRadius: 9))
                                .padding(.horizontal, 12).padding(.bottom, 12)
                        }
                    }
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                    .contextMenu {
                        Button("Rename setup") { renameTarget = profile }
                        Button("Forget layout", role: .destructive) { engine.forgetProfile(id: profile.id) }
                    }
                }
            }
        }
    }

    private var settingsCard: some View {
        VStack(spacing: 13) {
            Toggle(isOn: Binding(get: { engine.state.settings.automaticLayouts }, set: engine.setAutomatic)) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Automatic layouts").font(.system(size: 12, weight: .medium))
                    Text("Remember changes and restore on reconnect.").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Divider()
            Toggle(isOn: Binding(get: { engine.state.settings.maximizeLaptop }, set: engine.setMaximizeLaptop)) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Maximize on MacBook").font(.system(size: 12, weight: .medium))
                    Text("Fill the usable screen when working on the laptop.").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Divider()
            Toggle(isOn: Binding(get: { engine.launchAtLogin }, set: engine.setLaunchAtLogin)) {
                Text("Launch at login").font(.system(size: 12, weight: .medium))
            }
            if engine.loginNeedsApproval {
                Text("Allow Remember in System Settings → General → Login Items.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch).controlSize(.mini)
        .padding(15)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }

    private func issueCard(_ issue: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
            Text(issue).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: engine.dismissIssue) { Image(systemName: "xmark").font(.system(size: 9)) }
                .buttonStyle(.plain).help("Dismiss message")
        }.padding(12).background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack(spacing: 7) {
                if engine.isWorking { ProgressView().controlSize(.mini).scaleEffect(0.7).frame(width: 12, height: 12) }
                else { Circle().fill(engine.hasPermission && engine.state.settings.automaticLayouts ? rememberAccent : .orange).frame(width: 6, height: 6) }
                Text(engine.status).font(.system(size: 11, weight: .medium))
                Spacer()
                Image(systemName: "lock").font(.system(size: 9)).foregroundStyle(.tertiary).help("Layouts stay on this Mac")
            }
            Text(engine.detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
        }.padding(.horizontal, 22).padding(.bottom, 16).padding(.top, 0)
    }
}

struct LayoutPreview: View {
    let displays: [DisplayInfo]
    let windows: [SavedWindow]
    private let colors: [Color] = [Color(red: 0.29, green: 0.73, blue: 0.66), Color(red: 0.49, green: 0.60, blue: 0.91),
                                  Color(red: 0.84, green: 0.64, blue: 0.41), Color(red: 0.68, green: 0.53, blue: 0.82)]

    var body: some View {
        Canvas { context, size in
            guard !displays.isEmpty else { return }
            let minX = displays.map { $0.frame.x }.min()!, minY = displays.map { $0.frame.y }.min()!
            let maxX = displays.map { $0.frame.x + $0.frame.width }.max()!, maxY = displays.map { $0.frame.y + $0.frame.height }.max()!
            let totalWidth = maxX - minX, totalHeight = maxY - minY
            let scale = min((size.width - 32) / totalWidth, (size.height - 40) / totalHeight)
            let offsetX = (size.width - totalWidth * scale) / 2, offsetY = (size.height - 24 - totalHeight * scale) / 2
            for display in displays {
                let rect = CGRect(x: offsetX + (display.frame.x - minX) * scale,
                                  y: offsetY + (display.frame.y - minY) * scale,
                                  width: display.frame.width * scale, height: display.frame.height * scale)
                context.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(.white.opacity(0.06)))
                context.stroke(Path(roundedRect: rect, cornerRadius: 5), with: .color(.white.opacity(0.26)), lineWidth: 1)
                let interior = rect.insetBy(dx: 4, dy: 4)
                var inner = context
                inner.clip(to: Path(roundedRect: interior, cornerRadius: 3))
                let screenWindows = windows.filter { $0.displayID == display.id }
                for window in screenWindows.prefix(12).reversed() {
                    let frame = window.normalizedFrame
                    let windowRect = CGRect(x: interior.minX + CGFloat(frame.x) * interior.width + 1,
                                            y: interior.minY + CGFloat(frame.y) * interior.height + 1,
                                            width: max(1, CGFloat(frame.width) * interior.width - 2),
                                            height: max(1, CGFloat(frame.height) * interior.height - 2))
                    let colorIndex = window.bundleID.utf8.reduce(0) { ($0 + Int($1)) % colors.count }
                    let color = colors[colorIndex]
                    inner.fill(Path(roundedRect: windowRect, cornerRadius: 3), with: .color(color.opacity(0.70)))
                    inner.stroke(Path(roundedRect: windowRect, cornerRadius: 3), with: .color(color.opacity(0.9)), lineWidth: 0.5)
                    if windowRect.width > 35 && windowRect.height > 18 {
                        inner.draw(Text(String(window.appName.prefix(16))).font(.system(size: 8, weight: .medium)).foregroundColor(.white.opacity(0.95)),
                                   at: CGPoint(x: windowRect.midX, y: windowRect.midY))
                    }
                }
                if screenWindows.isEmpty {
                    inner.draw(Text("Ready to remember").font(.system(size: 9)).foregroundColor(.white.opacity(0.35)),
                               at: CGPoint(x: interior.midX, y: interior.midY))
                }
                context.draw(Text(display.isBuiltIn ? "MacBook" : String(display.name.prefix(24)))
                    .font(.system(size: 9)).foregroundColor(.white.opacity(0.65)), at: CGPoint(x: rect.midX, y: rect.maxY + 12))
            }
        }
        .accessibilityLabel("Layout preview, \(displays.count) displays and \(windows.count) remembered windows")
    }
}

private struct RenameProfileView: View {
    let profile: LayoutProfile
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Name this setup").font(.headline)
            TextField("Work monitor", text: $name).textFieldStyle(.roundedBorder).onSubmit(save)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save", action: save).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 320).onAppear { name = profile.name }
    }

    private func save() { onSave(name); dismiss() }
}
