import AVFoundation
import Speech

/// Dictation for the add-task field. Recognition runs on the Mac when the language supports it.
@MainActor
final class SpeechInput: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var transcript = ""
    @Published private(set) var error: String?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var onFinish: ((String) -> Void)?

    func toggle(onFinish: @escaping (String) -> Void) {
        isListening ? stop() : start(onFinish: onFinish)
    }

    func start(onFinish: @escaping (String) -> Void) {
        self.onFinish = onFinish
        error = nil
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    self.error = "Allow Speech Recognition in System Settings › Privacy."
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { ok in
                    DispatchQueue.main.async {
                        ok ? self.begin() : (self.error = "Allow Microphone in System Settings › Privacy.")
                    }
                }
            }
        }
    }

    private func begin() {
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            error = "Speech recognition isn't available for this language."
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        request.addsPunctuation = false
        self.request = request
        transcript = ""

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        do {
            try engine.start()
        } catch {
            self.error = error.localizedDescription
            return
        }
        isListening = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, err in
            DispatchQueue.main.async {
                guard let self else { return }
                if let result { self.transcript = result.bestTranscription.formattedString }
                if err != nil || result?.isFinal == true { self.finish() }
            }
        }
    }

    func stop() {
        guard isListening else { return }
        request?.endAudio() // final result arrives through the task callback
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.finish() }
    }

    private func finish() {
        guard isListening else { return }
        isListening = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        task?.cancel()
        task = nil
        request = nil
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { onFinish?(text) }
        onFinish = nil
    }
}
