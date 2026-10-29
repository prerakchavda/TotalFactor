import Foundation
import SwiftData

@Model
public final class WeighIn {
    public var id: UUID = UUID()
    public var date: Date = Date()
    public var dayKey: String = ""
    /// Stored internally in kilograms per spec §2.
    public var weightKg: Double = 80.0
    public var sourceRaw: String = WeighInSource.manual.rawValue
    public var healthKitUUID: UUID? = nil

    public init(
        date: Date = .now,
        dayKey: String? = nil,
        weightKg: Double,
        source: WeighInSource = .manual,
        healthKitUUID: UUID? = nil
    ) {
        self.date = date
        self.dayKey = dayKey ?? DayKey.from(date)
        self.weightKg = weightKg
        self.sourceRaw = source.rawValue
        self.healthKitUUID = healthKitUUID
    }

    public var source: WeighInSource {
        get { WeighInSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    public var asSample: RawWeighInSample {
        RawWeighInSample(timestamp: date, dayKey: dayKey, weightKg: weightKg)
    }
}

@Model
public final class BodyMetric {
    public var id: UUID = UUID()
    public var date: Date = Date()
    public var dayKey: String = ""
    public var typeRaw: String = BodyMetricType.waist.rawValue
    /// Stored in `%` for `.bodyFat` and `cm` internally for circumference measurements.
    public var value: Double = 0.0
    public var healthKitUUID: UUID? = nil

    public init(
        date: Date = .now,
        dayKey: String? = nil,
        type: BodyMetricType,
        value: Double,
        healthKitUUID: UUID? = nil
    ) {
        self.date = date
        self.dayKey = dayKey ?? DayKey.from(date)
        self.typeRaw = type.rawValue
        self.value = value
        self.healthKitUUID = healthKitUUID
    }

    public var type: BodyMetricType {
        get { BodyMetricType(rawValue: typeRaw) ?? .waist }
        set { typeRaw = newValue.rawValue }
    }
}

@Model
public final class ProgressPhoto {
    public var id: UUID = UUID()
    public var date: Date = Date()
    public var dayKey: String = ""
    public var poseRaw: String = PhotoPose.front.rawValue
    public var weightKgAtCapture: Double? = nil
    public var caption: String = ""

    @Attribute(.externalStorage)
    public var imageData: Data? = nil

    public init(
        date: Date = .now,
        dayKey: String? = nil,
        pose: PhotoPose = .front,
        imageData: Data?,
        weightKgAtCapture: Double? = nil,
        caption: String = ""
    ) {
        self.date = date
        self.dayKey = dayKey ?? DayKey.from(date)
        self.poseRaw = pose.rawValue
        self.imageData = imageData
        self.weightKgAtCapture = weightKgAtCapture
        self.caption = caption
    }

    public var pose: PhotoPose {
        get { PhotoPose(rawValue: poseRaw) ?? .front }
        set { poseRaw = newValue.rawValue }
    }
}
