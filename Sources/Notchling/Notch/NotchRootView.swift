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
    @AppStorage(Prefs.width) private var width = 680.0
    @AppStorage(Prefs.height) private var height = 360.0
    @AppStorage(Prefs.fakeNotch) private var fakeNotch = true

    private var showsPill: Bool { focus.clock.isActive && !model.isOpen }

    private var size: CGSize {
        if model.isOpen { return CGSize(width: width, height: height) }
        let extra = showsPill ? NotchWindowController.sidePill : 0
        return CGSize(width: model.notchSize.width + 2 * extra, height: model.notchSize.height)
    }

    private var hidden: Bool {
        !model.isOpen && !showsPill && !model.screenHasHardwareNotch && !fakeNotch
    }

    var body: some View {
        let open = model.isOpen
        let top: CGFloat = open ? 14 : 6
        ZStack(alignment: .top) {
            NotchShape(topRadius: top, bottomRadius: open ? 24 : 10)
                .fill(Color.black)
                .shadow(color: .black.opacity(open ? 0.45 : 0), radius: 14, y: 6)
            if open {
                ExpandedView()
                    .padding(.horizontal, top + 6)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            } else if showsPill {
                ClosedPill(notchWidth: model.notchSize.width)
                    .padding(.horizontal, top + 4)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .opacity(hidden ? 0 : 1)
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: open)
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: showsPill)
    }
}

/// Running timer shown beside the closed notch.
private struct ClosedPill: View {
    @EnvironmentObject var focus: FocusController
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: focus.clock.isRunning ? "timer" : "pause.fill")
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer().frame(width: notchWidth - 20)
            Text(focus.displayText)
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: 12, weight: .semibold))
        .frame(maxHeight: .infinity)
    }
}

/// Open workspace: tabs in the left "ear", date and settings in the right one, content below.
struct ExpandedView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                HStack(spacing: 2) {
                    ForEach(NotchTab.allCases) { tab in
                        Button { model.tab = tab } label: {
                            Image(systemName: tab.icon)
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 26, height: 22)
                                .background(model.tab == tab ? Color.white.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 6))
                                .foregroundStyle(model.tab == tab ? .white : .white.opacity(0.55))
                        }
                        .buttonStyle(.plain)
                        .help(tab.title)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer().frame(width: model.notchSize.width)
                HStack(spacing: 10) {
                    Text(Date.now, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Button { SettingsWindow.show(model: model) } label: {
                        Image(systemName: "gearshape").foregroundStyle(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: max(model.notchSize.height, 24))

            ZStack {
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
                if let alert = model.currentAlert {
                    AlertCard(alert: alert)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: model.currentAlert)
        }
        .foregroundStyle(.white)
    }
}
