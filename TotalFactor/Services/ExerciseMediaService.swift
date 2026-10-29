import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
import ImageIO
#endif

public struct ExerciseGuideEntry: Sendable, Equatable {
    public var name: String
    public var mediaKey: String
    public var setupTip: String
    public var steps: [String]
    public var formCues: [String]
    public var commonMistakes: [String]

    public var hasBundledPhotos: Bool {
        !mediaKey.isEmpty
    }
}

private struct BundledExerciseGuideDTO: Decodable {
    var name: String
    var instructions: String?
    var mediaKey: String?
    var setupTip: String?
    var steps: [String]?
    var formCues: [String]?
    var commonMistakes: [String]?
}

/// Fast in-memory O(1) lookup for exercise demonstration photos and step-by-step Planet Fitness guides.
/// Avoids SwiftData schema migrations or per-row JSON decoding during scrolling.
public final class ExerciseGuideCatalog: @unchecked Sendable {
    public static let shared = ExerciseGuideCatalog()

    private let entriesByNormalizedName: [String: ExerciseGuideEntry]

    private init() {
        var map: [String: ExerciseGuideEntry] = [:]
        if let url = Bundle.main.url(forResource: "BundledExercises", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let items = try? JSONDecoder().decode([BundledExerciseGuideDTO].self, from: data) {
            for dto in items {
                let entry = ExerciseGuideEntry(
                    name: dto.name,
                    mediaKey: dto.mediaKey ?? "",
                    setupTip: dto.setupTip ?? "",
                    steps: (dto.steps?.isEmpty == false) ? dto.steps! : (dto.instructions.map { [$0] } ?? []),
                    formCues: dto.formCues ?? [],
                    commonMistakes: dto.commonMistakes ?? []
                )
                map[Self.normalize(dto.name)] = entry
            }
        }
        self.entriesByNormalizedName = map
    }

    public func guide(for exercise: Exercise) -> ExerciseGuideEntry {
        let directKey = Self.normalize(exercise.name)
        if let hit = entriesByNormalizedName[directKey] {
            return hit
        }

        let canonicalKey = Self.normalize(StrongCSVParser.canonicalExerciseName(for: exercise.name))
        if let aliasHit = entriesByNormalizedName[canonicalKey] {
            return aliasHit
        }

        // Graceful fallback for user-created custom exercises
        let fallbackSteps: [String] = exercise.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? [
                "Adjust the \(exercise.equipment.displayName.lowercased()) so your joints align cleanly through a pain-free range.",
                "Brace your core, initiate with your \(exercise.primaryMuscles.map(\.displayName).joined(separator: " & ").lowercased()), and drive smoothly to peak contraction.",
                "Lower the weight under a controlled 2-second eccentric back to the stretched position."
            ]
            : [exercise.instructions]

        return ExerciseGuideEntry(
            name: exercise.name,
            mediaKey: "",
            setupTip: "Adjust seat/stance for full comfortable range of motion and log weight consistently each session.",
            steps: fallbackSteps,
            formCues: [
                "Control every eccentric for ~2 seconds without bouncing.",
                "Keep tension on \(exercise.primaryMuscles.map(\.displayName).joined(separator: ", ")) rather than using momentum."
            ],
            commonMistakes: [
                "Cutting range of motion short to chase heavier stack weight."
            ]
        )
    }

    private static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

#if canImport(UIKit)
/// Off-main-thread downsampling image cache using `CGImageSourceCreateThumbnailAtIndex` + `NSCache`.
/// Eliminates UIKit main-thread JPEG decompression hitches when scrolling lists & workout cards.
public final class ExerciseImageCache: @unchecked Sendable {
    public static let shared = ExerciseImageCache()

    private let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 240
        c.totalCostLimit = 48 * 1024 * 1024 // 48 MB decoded bitmap cap
        return c
    }()

    private init() {}

    public func cachedImage(mediaKey: String, phase: Int, bucketSize: Int) -> UIImage? {
        guard !mediaKey.isEmpty else { return nil }
        let key = "\(mediaKey)_\(phase)_\(bucketSize)" as NSString
        return cache.object(forKey: key)
    }

    public func loadImage(mediaKey: String, phase: Int, bucketSize: Int) async -> UIImage? {
        guard !mediaKey.isEmpty else { return nil }
        let cacheKey = "\(mediaKey)_\(phase)_\(bucketSize)"
        if let hit = cache.object(forKey: cacheKey as NSString) {
            return hit
        }

        let resourceName = "\(mediaKey)_\(phase)"
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "jpg", subdirectory: "ExerciseMedia")
                ?? Bundle.main.url(forResource: resourceName, withExtension: "jpg") else {
            return nil
        }

        let decoded: UIImage? = await Task.detached(priority: .userInitiated) {
            let sourceOpts = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOpts) else {
                return nil
            }
            let downsampleOpts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: bucketSize
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOpts as CFDictionary) else {
                return nil
            }
            let img = UIImage(cgImage: cgImage)
            return img.preparingForDisplay() ?? img
        }.value

        if let decoded {
            let cost = Int(decoded.size.width * decoded.size.height * 4)
            cache.setObject(decoded, forKey: cacheKey as NSString, cost: cost)
        }
        return decoded
    }
}
#endif

/// Fast, zero-hitch thumbnail badge for exercise rows, workout previews, and active workout headers.
struct ExerciseThumbnailView: View {
    let exercise: Exercise
    var size: CGFloat = 46
    var cornerRadius: CGFloat = 10
    var phase: Int = 1 // Phase 1 (contracted/action pose) makes the clearest small thumbnail!

    #if canImport(UIKit)
    @State private var loadedImage: UIImage? = nil
    #endif

    var body: some View {
        let guide = ExerciseGuideCatalog.shared.guide(for: exercise)
        #if canImport(UIKit)
        let bucket = size <= 64 ? 140 : 560
        let immediate = loadedImage ?? ExerciseImageCache.shared.cachedImage(mediaKey: guide.mediaKey, phase: phase, bucketSize: bucket)

        Group {
            if let uiImage = immediate {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
                    )
            } else {
                fallbackBadge
            }
        }
        .task(id: "\(guide.mediaKey)_\(phase)_\(bucket)") {
            guard immediate == nil, !guide.mediaKey.isEmpty else { return }
            loadedImage = await ExerciseImageCache.shared.loadImage(
                mediaKey: guide.mediaKey,
                phase: phase,
                bucketSize: bucket
            )
        }
        #else
        fallbackBadge
        #endif
    }

    private var fallbackBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
            Image(systemName: equipmentSymbol(for: exercise.equipment))
                .font(.system(size: size * 0.40, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: size, height: size)
    }

    private func equipmentSymbol(for eq: Equipment) -> String {
        switch eq {
        case .machine, .smithMachine: return "gearshape.2.fill"
        case .cable: return "arrow.up.and.down.and.sparkles"
        case .dumbbell, .barbell, .ezBar, .trapBar: return "dumbbell.fill"
        case .bodyweight: return "figure.strengthtraining.functional"
        case .kettlebell: return "scalemass.fill"
        case .bands: return "scribble.variable"
        }
    }
}
