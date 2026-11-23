import NotchlingCore
import SwiftUI

struct FocusView: View {
    @EnvironmentObject var focus: FocusController
    @State private var mode: FocusClock.Mode = .countdown
    @AppStorage("focus.lastMinutes") private var minutes = 25

    var body: some View {
        HStack(spacing: 26) {
            ZStack {
                Ring(progress: focus.clock.isActive ? focus.progress : 0, lineWidth: 7, tint: Tok.accent)
                VStack(spacing: 2) {
                    Text(focus.clock.isActive ? focus.displayText : FocusController.format(mode == .countdown ? Double(minutes * 60) : 0))
                        .nfont(40, .semibold, design: .rounded)
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: focus.clock.mode == .countdown))
                        .animation(.default, value: focus.displayText)
                    Text(status).nfont(11, .semibold).foregroundStyle(Tok.ink(0.45))
                }
            }
            .frame(width: 190, height: 190)
            .padding(.leading, 8)

            VStack(alignment: .leading, spacing: 12) {
                controls
                if !focus.clock.isActive {
                    Picker("", selection: $mode) {
                        Text("Countdown").tag(FocusClock.Mode.countdown)
                        Text("Stopwatch").tag(FocusClock.Mode.stopwatch)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 220)
                    if mode == .countdown {
                        HStack(spacing: 5) {
                            ForEach([15, 25, 45, 60, 90], id: \.self) { m in
                                Button("\(m)") { minutes = m }
                                    .buttonStyle(.pill(Tok.accent, prominent: minutes == m))
                            }
                        }
                    }
                }
                SectionLabel("Background sound")
                HStack(spacing: 5) {
                    ForEach(NoisePlayer.Sound.allCases) { s in
                        Button { focus.sound = s } label: { Label(s.label, systemImage: s.icon).labelStyle(.iconOnly) }
                            .buttonStyle(.pill(Tok.accent, prominent: focus.sound == s))
                            .help(s.label)
                    }
                    if focus.sound != .off {
                        Slider(value: $focus.volume, in: 0...1).controlSize(.mini).frame(width: 80)
                    }
                }
                Text("Pauses while your Mac sleeps. Only active time counts.")
                    .nfont(10).foregroundStyle(Tok.ink(0.35))
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }

    private var status: String {
        guard focus.clock.isActive else { return mode == .countdown ? "READY" : "STOPWATCH" }
        return focus.clock.isRunning ? "FOCUSING" : "PAUSED"
    }

    @ViewBuilder private var controls: some View {
        HStack(spacing: 6) {
            if !focus.clock.isActive {
                Button { focus.start(mode, minutes: minutes) } label: { Label("Start focus", systemImage: "play.fill") }
                    .buttonStyle(.pill(Tok.accent, prominent: true))
                    .keyboardShortcut(.space, modifiers: [])
            } else {
                if focus.clock.isRunning {
                    Button { focus.pause() } label: { Label("Pause", systemImage: "pause.fill") }.buttonStyle(.pill)
                } else {
                    Button { focus.resume() } label: { Label("Resume", systemImage: "play.fill") }.buttonStyle(.pill(Tok.accent, prominent: true))
                }
                if focus.clock.mode == .countdown {
                    Button("+5 min") { focus.addFive() }.buttonStyle(.pill)
                }
                Button { focus.stop() } label: { Label("End", systemImage: "stop.fill") }.buttonStyle(.pill(Tok.danger))
            }
        }
    }
}

extension NoisePlayer.Sound {
    var icon: String {
        switch self {
        case .off: return "speaker.slash"
        case .brown: return "wind"
        case .pink: return "leaf"
        case .white: return "aqi.medium"
        case .rain: return "cloud.rain"
        case .ocean: return "water.waves"
        }
    }
}
