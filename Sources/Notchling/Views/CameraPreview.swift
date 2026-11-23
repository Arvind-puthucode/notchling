import AVFoundation
import SwiftUI

/// Mirror-style camera preview for a quick look before a call. Starts on appear, stops on disappear.
struct CameraPreview: NSViewRepresentable {
    final class PreviewView: NSView {
        let session = AVCaptureSession()
        private let layerPreview: AVCaptureVideoPreviewLayer

        override init(frame: NSRect) {
            layerPreview = AVCaptureVideoPreviewLayer(session: session)
            super.init(frame: frame)
            wantsLayer = true
            layerPreview.videoGravity = .resizeAspectFill
            layerPreview.connection?.automaticallyAdjustsVideoMirroring = false
            layer?.addSublayer(layerPreview)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            layerPreview.frame = bounds
            if let c = layerPreview.connection, c.isVideoMirroringSupported {
                c.automaticallyAdjustsVideoMirroring = false
                c.isVideoMirrored = true
            }
        }

        func start() {
            let session = self.session
            AVCaptureDevice.requestAccess(for: .video) { ok in
                guard ok else { return }
                DispatchQueue.global(qos: .userInitiated).async { [session] in
                    guard session.inputs.isEmpty, let device = AVCaptureDevice.default(for: .video),
                          let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
                        if !session.isRunning { session.startRunning() }
                        return
                    }
                    session.beginConfiguration()
                    session.sessionPreset = .medium
                    session.addInput(input)
                    session.commitConfiguration()
                    session.startRunning()
                }
            }
        }

        func stop() {
            DispatchQueue.global(qos: .userInitiated).async { [session] in session.stopRunning() }
        }
    }

    func makeNSView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.start()
        return v
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {}

    static func dismantleNSView(_ nsView: PreviewView, coordinator: ()) {
        nsView.stop()
    }
}
