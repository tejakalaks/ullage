import UIKit

/// Gets a photograph ready to send to a model.
///
/// A modern iPhone photo is around 4000 pixels on the long edge and several megabytes. Sending
/// that costs the user money and time for no benefit: vision models tile images and a label
/// is legible well below that. Downscaling to 1400px keeps the small print on a back label
/// readable while cutting the payload by an order of magnitude.
enum ImagePreparer {
    static let maximumDimension: CGFloat = 1400
    static let compressionQuality: CGFloat = 0.72

    /// Downscales, corrects orientation and JPEG-encodes.
    ///
    /// The orientation step matters more than it looks: `UIImage` carries rotation as metadata
    /// that some encoders drop, and a sideways label is markedly harder to read.
    static func prepare(_ image: UIImage) -> Data? {
        let normalized = resized(image, fitting: maximumDimension)
        return normalized.jpegData(compressionQuality: compressionQuality)
    }

    static func resized(_ image: UIImage, fitting maximum: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }

        let longestEdge = max(size.width, size.height)
        let scale = longestEdge > maximum ? maximum / longestEdge : 1
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// A small version for the cellar list and the scan thumbnail strip.
    static func thumbnail(_ image: UIImage, maximum: CGFloat = 400) -> Data? {
        resized(image, fitting: maximum).jpegData(compressionQuality: 0.7)
    }
}
