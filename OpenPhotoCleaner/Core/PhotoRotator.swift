import Photos
import CoreImage
import ImageIO

enum RotateError: LocalizedError {
    case unsupported
    case noImage

    var errorDescription: String? {
        switch self {
        case .unsupported: String(localized: "Only still photos can be rotated.")
        case .noImage: String(localized: "The photo could not be read.")
        }
    }
}

extension PHAsset {
    /// Identifies this asset *and* its current edit state, so cached images are dropped after a rotation.
    var cacheKey: String { "\(localIdentifier)|\(modificationDate?.timeIntervalSince1970 ?? 0)" }
}

/// Rotates a still photo by 90° as a normal Photos edit (the original is kept; "Revert" in Photos undoes it).
enum PhotoRotator {
    static func rotate(_ asset: PHAsset, clockwise: Bool) async throws {
        guard asset.mediaType == .image, !asset.mediaSubtypes.contains(.photoLive) else { throw RotateError.unsupported }

        let input: PHContentEditingInput = try await withCheckedThrowingContinuation { continuation in
            let options = PHContentEditingInputRequestOptions()
            options.isNetworkAccessAllowed = true
            asset.requestContentEditingInput(with: options) { input, _ in
                if let input { continuation.resume(returning: input) } else { continuation.resume(throwing: RotateError.noImage) }
            }
        }
        guard let url = input.fullSizeImageURL,
              let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { throw RotateError.noImage }

        let rotated = image.oriented(clockwise ? .right : .left)
        let output = PHContentEditingOutput(contentEditingInput: input)
        output.adjustmentData = PHAdjustmentData(
            formatIdentifier: "com.openphotocleaner.rotate", formatVersion: "1.0", data: Data([clockwise ? 1 : 0]))
        let colorSpace = rotated.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        try CIContext().writeJPEGRepresentation(of: rotated, to: output.renderedContentURL, colorSpace: colorSpace)

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest(for: asset).contentEditingOutput = output
        }
    }
}
