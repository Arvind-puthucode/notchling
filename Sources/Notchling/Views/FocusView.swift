import NotchlingCore
import SwiftUI

struct FocusView: View {
    @EnvironmentObject var focus: FocusController
    @State private var mode: FocusClock.Mode = .countdown
    @State private var minutes = 25

    var body: some View {
        HStack(spacing: 24) {
            VStack(spacing: 12) {
                Text(focus.clock.isActive ? focus.displayText : FocusController.format(mode == .countdown ? Double(minutes * 60) : 0))
                    .font(.system(size: 54, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(focus.clock.isRunning ? .white : .white.opacity(0.7))
                controls
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Mode")
                Picker("", selection: $mode) {
                    Text("Countdown").tag(FocusClock.Mode.countdown)
                    Text("Stopwatch").tag(FocusClock.Mode.stopwatch)
                }
                .pickerStyle(.segmented).labelsHidden()
                .disabled(focus.clock.isActive)

                if mode == .countdown {
                    HStack(spacing: 6) {
                        ForEach([15, 25, 45, 60], id: \.self) { m in
                            Button("\(m)") { minutes = m }
                                .buttonStyle(.pill(minutes == m ? .orange : .white))
                        }
                    }
                    .disabled(focus.clock.isActive)
                }

                SectionLabel("Sound")
                Picker("", selection: $focus.sound) {
                    ForEach(NoisePlayer.Sound.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                Slider(value: $focus.volume, in: 0...1)
                    .controlSize(.small)
            }
            .frame(width: 220)
        }
    }

    @ViewBuilder private var controls: some View {
        HStack(spacing: 8) {
            if !focus.clock.isActive {
                Button("Start") { focus.start(mode, minutes: minutes) }.buttonStyle(.pill(.orange))
            } else {
                if focus.clock.isRunning {
                    Button("Pause") { focus.pause() }.buttonStyle(.pill)
                } else {
                    Button("Resume") { focus.resume() }.buttonStyle(.pill(.orange))
                }
                if focus.clock.mode == .countdown {
                    Button("+5 min") { focus.addFive() }.buttonStyle(.pill)
                }
                Button("End") { focus.stop() }.buttonStyle(.pill(.red))
            }
        }
    }
}
