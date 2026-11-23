import SwiftUI

/// Notch silhouette: concave flares at the top corners, rounded bottom corners.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let t = topRadius, b = bottomRadius
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t), control: CGPoint(x: rect.minX + t, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY), control: CGPoint(x: rect.minX + t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b), control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - t, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

struct NotchRootView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var focus: FocusController
    @AppStorage(Prefs.width) private var width = 700.0
    @AppStorage(Prefs.height) private var height = 380.0
    @AppStorage(Prefs.fakeNotch) private var fakeNotch = true
    @AppStorage(Prefs.appearance) private var appearance = "dark"
    @AppStorage(Prefs.textScale) private var textScale = 1.0

    private var light: Bool { appearance == "light" }
    private var showsPill: Bool { focus.clock.isActive && !model.isOpen }

    private var size: CGSize {
        if model.isOpen { return model.openSize }
        let extra = showsPill ? NotchWindowController.sidePill : 0
        let hover: CGFloat = model.hoveringClosedNotch ? 10 : 0
        return CGSize(width: model.notchSize.width + 2 * extra + hover * 2, height: model.notchSize.height + hover / 3)
    }

    /// The drawn notch steps aside on plain displays when turned off or when a full-screen app hides the menu bar.
    private var hidden: Bool {
        guard !model.isOpen, !model.screenHasHardwareNotch else { return false }
        return !fakeNotch || model.menuBarHidden
    }

    var body: some View {
        let open = model.isOpen
        let compact = model.isCompact
        let top: CGFloat = open ? 12 : 6
        // Light look tints the open surface; the closed notch is always black like the hardware.
        let fill = open && !compact ? NotchBackground.color(light: light) : .black
        ZStack(alignment: .top) {
            NotchShape(topRadius: top, bottomRadius: open ? (compact ? 28 : 26) : 10)
                .fill(fill)
                .shadow(color: .black.opacity(open ? 0.5 : 0), radius: 18, y: 8)
            Group {
                if compact, let alert = model.currentAlert {
                    AlertCard(alert: alert, compact: true)
                        .environment(\.colorScheme, .dark)
                        .padding(.top, model.notchSize.height + 2)
                        .padding(.horizontal, top + 14)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(Tok.spring) { model.expandFromAlert() } }
                } else if open {
                    ExpandedView(inNotch: true)
                        .environment(\.colorScheme, light ? .light : .dark)
                        .padding(.horizontal, top + 8)
                        .padding(.bottom, 14)
                } else if showsPill {
                    ClosedPill(notchWidth: model.notchSize.width)
                        .padding(.horizontal, top + 6)
                }
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .top)).animation(Tok.spring.delay(0.05)),
                removal: .opacity.animation(.easeOut(duration: 0.1))))
        }
        .frame(width: size.width, height: size.height)
        .clipShape(NotchShape(topRadius: top, bottomRadius: open ? 26 : 10))
        .opacity(hidden ? 0 : 1)
        .environment(\.textScale, textScale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Tok.spring, value: open)
        .animation(Tok.spring, value: compact)
        .animation(Tok.spring, value: showsPill)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: model.hoveringClosedNotch)
    }
}

/// Running timer shown beside the closed notch.
private struct ClosedPill: View {
    @EnvironmentObject var focus: FocusController
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Ring(progress: focus.progress, lineWidth: 2.5, tint: Tok.accent)
                .frame(width: 14, height: 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer().frame(width: notchWidth - 24)
            Text(focus.displayText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(focus.clock.isRunning ? .white : .white.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
    }
}

/// The workspace: tabs and status around the notch, content below. Also used by window mode.
struct ExpandedView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var focus: FocusController
    var inNotch: Bool
    @Namespace private var tabNS

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                tabBar.frame(maxWidth: .infinity, alignment: .leading)
                if inNotch { Spacer().frame(width: model.notchSize.width + 8) }
                status.frame(maxWidth: inNotch ? .infinity : nil, alignment: .trailing)
            }
            .frame(height: inNotch ? max(model.notchSize.height, 26) : 30)

            ZStack(alignment: .top) {
                Group {
                    switch model.tab {
                    case .today: TodayView()
                    case .week: WeekView()
                    case .notes: NotesView()
                    case .focus: FocusView()
                    case .calendar: CalendarTabView()
                    case .clips: ClipsView()
                    case .insights: InsightsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .id(model.tab)
                .transition(.opacity.animation(.easeOut(duration: 0.12)))

                if let alert = model.currentAlert, !model.isCompact {
                    AlertCard(alert: alert)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(Tok.spring, value: model.currentAlert)
        }
        .foregroundStyle(Tok.ink(0.95))
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(NotchTab.allCases) { tab in
                TabButton(tab: tab, selected: model.tab == tab, ns: tabNS) {
                    withAnimation(Tok.spring) { model.tab = tab }
                }
            }
        }
    }

    private var status: some View {
        HStack(spacing: 8) {
            if focus.clock.isActive && model.tab != .focus {
                Button { model.tab = .focus } label: {
                    HStack(spacing: 4) {
                        Ring(progress: focus.progress, lineWidth: 2, tint: Tok.accent).frame(width: 11, height: 11)
                        Text(focus.displayText).nfont(11, .semibold, design: .rounded).monospacedDigit()
                    }
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Tok.accent.opacity(0.15), in: Capsule())
                    .foregroundStyle(Tok.accent)
                }
                .buttonStyle(.plain)
            }
            TimelineView(.everyMinute) { ctx in
                Text(ctx.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .nfont(12, .semibold)
                    .foregroundStyle(Tok.ink(0.6))
            }
            Menu {
                Button("Settings…") { SettingsWindow.show(model: model) }
                if inNotch {
                    Button("Open as Window") { model.close(); model.showWindow?() }
                }
                if let until = model.remindersPausedUntil {
                    Button("Resume Reminders (paused until \(until.formatted(date: .omitted, time: .shortened)))") { model.remindersPausedUntil = nil }
                } else {
                    Button("Pause Reminders for 1 Hour") { model.remindersPausedUntil = Date().addingTimeInterval(3600) }
                }
                Divider()
                Button("Quit Notchling") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle").nfont(13, .medium).foregroundStyle(Tok.ink(0.6))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
    }
}

private struct TabButton: View {
    let tab: NotchTab
    let selected: Bool
    let ns: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.icon).nfont(12, .semibold)
            .frame(width: 30)
            .frame(height: 24)
            .foregroundStyle(selected ? Tok.ink(1) : Tok.ink(hovering ? 0.8 : 0.5))
            .background {
                if selected {
                    Capsule().fill(Tok.fill(0.14)).matchedGeometryEffect(id: "tab", in: ns)
                } else if hovering {
                    Capsule().fill(Tok.fill(0.06))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tab.title)
    }
}
