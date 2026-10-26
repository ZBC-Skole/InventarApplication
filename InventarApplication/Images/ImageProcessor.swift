//
//  ImageProcessor.swift
//  InventarApplication
//

import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// The result of importing an image: ready to store on `Equipment`.
nonisolated struct ProcessedImage: Sendable {
    /// The photo, downscaled and re-encoded.
    var photo: Data
    /// The foreground subject on a transparent background, if Vision found one.
    var cutout: Data?
    /// A small PNG of `cutout` (or `photo` when there is no cutout).
    var thumbnail: Data
}

/// Prepares imported images and lifts the subject out using on-device Vision.
nonisolated enum ImageProcessor {
    enum Failure: Error {
        case unreadableImage
        case encodingFailed
    }

    /// Longest side, in pixels, of stored photos and cutouts.
    static let maxPixelSize = 2048
    /// Longest side, in pixels, of table thumbnails.
    static let thumbnailPixelSize = 128

    /// Downscales the image, tries to cut out the subject, and makes a thumbnail.
    ///
    /// Runs off the main actor. If background removal fails or finds no clear
    /// subject, `cutout` is `nil` and the original photo is used instead.
    @concurrent
    static func process(_ data: Data) async throws -> ProcessedImage {
        let photo = try downscaledImage(from: data, maxPixelSize: maxPixelSize)
        let cutout = try? await subjectCutout(of: photo)

        return ProcessedImage(
            photo: try encode(photo),
            cutout: try cutout.map { try encode($0, as: .png) },
            thumbnail: try encode(
                resized(cutout ?? photo, maxPixelSize: thumbnailPixelSize),
                as: .png
            )
        )
    }

    /// Makes a table thumbnail from already stored image data.
    @concurrent
    static func thumbnail(from data: Data) async throws -> Data {
        let image = try downscaledImage(from: data, maxPixelSize: thumbnailPixelSize)
        return try encode(image, as: .png)
    }

    // MARK: - Background removal

    /// Returns every foreground instance Vision finds, cropped to their extent,
    /// or `nil` when the image has no distinct subject.
    private static func subjectCutout(of image: CGImage) async throws -> CGImage? {
        let handler = ImageRequestHandler(image)
        let request = GenerateForegroundInstanceMaskRequest()
        guard let observation = try await handler.perform(request),
            !observation.allInstances.isEmpty
        else { return nil }

        let maskedBuffer = try observation.generateMaskedImage(
            for: observation.allInstances,
            imageFrom: handler,
            croppedToInstancesExtent: true
        )
        let maskedImage = CIImage(cvPixelBuffer: maskedBuffer)
        return CIContext().createCGImage(maskedImage, from: maskedImage.extent)
    }

    // MARK: - Decoding and encoding

    /// Decodes `data`, applying EXIF orientation and limiting the longest side.
    private static func downscaledImage(from data: Data, maxPixelSize: Int) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { throw Failure.unreadableImage }
        return image
    }

    private static func resized(_ image: CGImage, maxPixelSize: Int) -> CGImage {
        let scale = CGFloat(maxPixelSize) / CGFloat(max(image.width, image.height))
        guard scale < 1 else { return image }

        let width = max(1, Int(CGFloat(image.width) * scale))
        let height = max(1, Int(CGFloat(image.height) * scale))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return image }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    /// Encodes as JPEG, or PNG when the image has transparency or `type` asks for it.
    private static func encode(_ image: CGImage, as type: UTType? = nil) throws -> Data {
        let hasAlpha = ![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        let type = type ?? (hasAlpha ? .png : .jpeg)

        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data,
                type.identifier as CFString,
                1,
                nil
            )
        else { throw Failure.encodingFailed }

        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.85]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.encodingFailed }
        return data as Data
    }
}
