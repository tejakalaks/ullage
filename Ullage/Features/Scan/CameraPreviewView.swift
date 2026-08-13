import AVFoundation
import SwiftUI

/// The live viewfinder.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
    }

    /// Backing the view with `AVCaptureVideoPreviewLayer` directly, rather than adding a
    /// sublayer, means the layer resizes with the view instead of needing manual layout on
    /// every bounds change.
    final class PreviewView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // Safe by construction: `layerClass` guarantees the type.
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
