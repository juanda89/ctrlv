import AppKit
import Foundation

struct ComparisonResult {
    let width: Int
    let height: Int
    let changedPixels: Int

    var totalPixels: Int { width * height }
    var mismatchRatio: Double {
        guard totalPixels > 0 else { return 0 }
        return Double(changedPixels) / Double(totalPixels)
    }
}

enum SnapshotComparisonError: LocalizedError {
    case usage
    case loadFailed(String)
    case sizeMismatch(expected: NSSize, actual: NSSize)
    case bitmapCreationFailed
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .usage:
            return "Usage: swift scripts/compare-menu-snapshots.swift <baseline.png> <candidate.png> <diff.png> [threshold]"
        case .loadFailed(let path):
            return "Could not load image at \(path)"
        case let .sizeMismatch(expected, actual):
            return "Image sizes differ. Expected \(Int(expected.width))x\(Int(expected.height)), got \(Int(actual.width))x\(Int(actual.height))"
        case .bitmapCreationFailed:
            return "Could not create bitmaps for comparison"
        case .pngEncodingFailed:
            return "Could not encode diff image"
        }
    }
}

func loadBitmap(at path: String) throws -> NSBitmapImageRep {
    guard let image = NSImage(contentsOfFile: path) else {
        throw SnapshotComparisonError.loadFailed(path)
    }

    let size = image.size
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width),
        pixelsHigh: Int(size.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw SnapshotComparisonError.bitmapCreationFailed
    }

    bitmap.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    image.draw(in: NSRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

func compare(
    baseline: NSBitmapImageRep,
    candidate: NSBitmapImageRep,
    diffOutputPath: String
) throws -> ComparisonResult {
    let width = baseline.pixelsWide
    let height = baseline.pixelsHigh

    guard width == candidate.pixelsWide, height == candidate.pixelsHigh else {
        throw SnapshotComparisonError.sizeMismatch(
            expected: baseline.size,
            actual: candidate.size
        )
    }

    guard let diffBitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw SnapshotComparisonError.bitmapCreationFailed
    }

    diffBitmap.size = baseline.size

    guard
        let baselineData = baseline.bitmapData,
        let candidateData = candidate.bitmapData,
        let diffData = diffBitmap.bitmapData
    else {
        throw SnapshotComparisonError.bitmapCreationFailed
    }

    var changedPixels = 0
    let bytesPerRow = baseline.bytesPerRow
    let samplesPerPixel = max(4, baseline.samplesPerPixel)

    for y in 0..<height {
        for x in 0..<width {
            let offset = (y * bytesPerRow) + (x * samplesPerPixel)

            let blueDelta = abs(Int(baselineData[offset]) - Int(candidateData[offset]))
            let greenDelta = abs(Int(baselineData[offset + 1]) - Int(candidateData[offset + 1]))
            let redDelta = abs(Int(baselineData[offset + 2]) - Int(candidateData[offset + 2]))
            let alphaDelta = abs(Int(baselineData[offset + 3]) - Int(candidateData[offset + 3]))
            let totalDelta = blueDelta + greenDelta + redDelta + alphaDelta

            if totalDelta > 4 {
                changedPixels += 1
                diffData[offset] = 120
                diffData[offset + 1] = 0
                diffData[offset + 2] = 255
                diffData[offset + 3] = 255
            } else {
                diffData[offset] = baselineData[offset]
                diffData[offset + 1] = baselineData[offset + 1]
                diffData[offset + 2] = baselineData[offset + 2]
                diffData[offset + 3] = 36
            }
        }
    }

    guard let pngData = diffBitmap.representation(using: .png, properties: [:]) else {
        throw SnapshotComparisonError.pngEncodingFailed
    }

    let diffURL = URL(fileURLWithPath: diffOutputPath)
    try FileManager.default.createDirectory(
        at: diffURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try pngData.write(to: diffURL)

    return ComparisonResult(width: width, height: height, changedPixels: changedPixels)
}

do {
    guard CommandLine.arguments.count >= 4 else {
        throw SnapshotComparisonError.usage
    }

    let baselinePath = CommandLine.arguments[1]
    let candidatePath = CommandLine.arguments[2]
    let diffPath = CommandLine.arguments[3]
    let threshold = CommandLine.arguments.count >= 5 ? (Double(CommandLine.arguments[4]) ?? 0.003) : 0.003

    let baseline = try loadBitmap(at: baselinePath)
    let candidate = try loadBitmap(at: candidatePath)
    let result = try compare(baseline: baseline, candidate: candidate, diffOutputPath: diffPath)

    print(
        "changed_pixels=\(result.changedPixels) total_pixels=\(result.totalPixels) mismatch_ratio=\(String(format: "%.6f", result.mismatchRatio)) threshold=\(String(format: "%.6f", threshold))"
    )

    exit(result.mismatchRatio > threshold ? 1 : 0)
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(2)
}
