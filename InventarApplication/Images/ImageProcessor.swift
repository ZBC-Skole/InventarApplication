//
//  ImageProcessor.swift
//  InventarApplication
//

import CoreImage
import CoreImage.CIFilterBuiltins
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

    /// A cutout is only worth it when the subject covers part of the photo:
    /// below this it's likely noise, above it there's barely any background.
    private static let usefulSubjectCoverage = 0.01...0.9
    /// Transparent margin around the cropped subject, relative to its longest side.
    private static let cutoutPadding = 0.04

    /// Lifts the foreground subject out of `image`, or returns `nil` when
    /// there is no distinct subject or removing the background wouldn't help.
    ///
    /// Follows the usual Vision approach: generate a full-resolution mask of
    /// all foreground instances, then blend the photo with it over a
    /// transparent background.
    private static func subjectCutout(of image: CGImage) async throws -> CGImage? {
        let handler = ImageRequestHandler(image)
        let request = GenerateForegroundInstanceMaskRequest()
        guard let observation = try await handler.perform(request),
            !observation.allInstances.isEmpty
        else { return nil }

        let mask = CIImage(
            cvPixelBuffer: try observation.generateScaledMask(
                for: observation.allInstances,
                scaledToImageFrom: handler
            )
        )
        let context = CIContext()
        guard let subject = subjectRegion(in: mask, context: context),
            usefulSubjectCoverage.contains(subject.coverage)
        else { return nil }

        let input = CIImage(cgImage: image)
        let filter = CIFilter.blendWithMask()
        filter.inputImage = input
        filter.maskImage = mask
        filter.backgroundImage = CIImage.empty()
        guard let output = filter.outputImage else { return nil }

        let padding = max(subject.bounds.width, subject.bounds.height) * cutoutPadding
        let cropRect = subject.bounds
            .insetBy(dx: -padding, dy: -padding)
            .intersection(input.extent)
            .integral
        return context.createCGImage(output, from: cropRect)
    }

    /// Finds where the subject is in a mask and how much of the image it covers,
    /// by sampling a small copy of the mask.
    private static func subjectRegion(
        in mask: CIImage,
        context: CIContext
    ) -> (bounds: CGRect, coverage: Double)? {
        let sampleSize = 256.0
        let scale = min(1, sampleSize / max(mask.extent.width, mask.extent.height))
        let sample = mask.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let width = Int(sample.extent.width.rounded(.up))
        let height = Int(sample.extent.height.rounded(.up))
        guard width > 0, height > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height)
        context.render(
            sample,
            toBitmap: &pixels,
            rowBytes: width,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .L8,
            colorSpace: nil
        )

        var minX = width, minY = height, maxX = -1, maxY = -1
        var subjectPixels = 0
        for row in 0..<height {
            for column in 0..<width where pixels[row * width + column] > 127 {
                subjectPixels += 1
                minX = min(minX, column)
                maxX = max(maxX, column)
                minY = min(minY, row)
                maxY = max(maxY, row)
            }
        }
        guard subjectPixels > 0 else { return nil }

        // Bitmap rows run top to bottom; Core Image's y axis runs bottom to top.
        let bounds = CGRect(
            x: CGFloat(minX) / scale,
            y: CGFloat(height - 1 - maxY) / scale,
            width: CGFloat(maxX - minX + 1) / scale,
            height: CGFloat(maxY - minY + 1) / scale
        )
        return (bounds, Double(subjectPixels) / Double(width * height))
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
