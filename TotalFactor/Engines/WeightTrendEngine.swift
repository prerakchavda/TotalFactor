import Foundation

public struct RawWeighInSample: Equatable, Sendable {
    public var timestamp: Date
    public var dayKey: String
    public var weightKg: Double

    public init(timestamp: Date, dayKey: String? = nil, weightKg: Double) {
        self.timestamp = timestamp
        self.dayKey = dayKey ?? DayKey.from(timestamp)
        self.weightKg = weightKg
    }
}

public struct DailyWeightPoint: Identifiable, Equatable, Sendable {
    public var id: String { dayKey }
    public var dayKey: String
    public var date: Date
    /// Nil on missing days — we carry `trendKg` forward unchanged and never fabricate scale points.
    public var scaleKg: Double?
    public var trendKg: Double

    public init(dayKey: String, date: Date, scaleKg: Double?, trendKg: Double) {
        self.dayKey = dayKey
        self.date = date
        self.scaleKg = scaleKg
        self.trendKg = trendKg
    }
}

public struct WeightTrendSummary: Equatable, Sendable {
    public var latestTrendKg: Double?
    public var latestScaleKg: Double?
    public var change7dKg: Double?
    public var change14dKg: Double?
    public var change30dKg: Double?
    public var weeklyRateKg: Double?
    public var weeklyRatePercentBW: Double?
    public var weighInsLast7Days: Int
    public var weighInsLast28Days: Int
}

public enum WeightTrendEngine {
    /// Exact spec §7 EMA helper over raw `(date, kg)` tuples.
    public static func trend(weights: [(date: Date, kg: Double)], alpha: Double = 0.1) -> [(Date, Double)] {
        guard let first = weights.first else { return [] }
        let clampedAlpha = min(max(alpha, 0.01), 1.0)
        var t = first.kg
        return weights.map { w in
            t = t + clampedAlpha * (w.kg - t)
            return (w.date, t)
        }
    }

    /// Resolves multiple weigh-ins on the same calendar day according to the user's `WeighInRule`.
    public static func resolveDailyScaleWeights(
        samples: [RawWeighInSample],
        rule: WeighInRule = .firstMorning,
        calendar: Calendar = .current
    ) -> [String: Double] {
        let grouped = Dictionary(grouping: samples.filter { $0.weightKg > 20 && $0.weightKg < 400 }, by: \.dayKey)
        var resolved: [String: Double] = [:]

        for (dayKey, daySamples) in grouped {
            let sorted = daySamples.sorted { $0.timestamp < $1.timestamp }
            guard let first = sorted.first, let last = sorted.last else { continue }

            switch rule {
            case .firstMorning:
                // Prefer the earliest morning sample (03:00–12:00); otherwise fall back to earliest of the day.
                let morningSample = sorted.first { sample in
                    let hour = calendar.component(.hour, from: sample.timestamp)
                    return hour >= 3 && hour < 12
                }
                resolved[dayKey] = (morningSample ?? first).weightKg
            case .average:
                let sum = sorted.reduce(0.0) { $0 + $1.weightKg }
                resolved[dayKey] = sum / Double(sorted.count)
            case .last:
                resolved[dayKey] = last.weightKg
            }
        }
        return resolved
    }

    /// Builds a continuous calendar series from the earliest weigh-in through `endDayKey`.
    /// Missing days keep `scaleKg = nil` and carry `trendKg` forward unchanged per spec §7.
    public static func buildDailySeries(
        samples: [RawWeighInSample],
        rule: WeighInRule = .firstMorning,
        alpha: Double = 0.1,
        through endDayKey: String? = nil,
        calendar: Calendar = .current
    ) -> [DailyWeightPoint] {
        let dailyMap = resolveDailyScaleWeights(samples: samples, rule: rule, calendar: calendar)
        guard let startKey = dailyMap.keys.min() else { return [] }
        let finalKey: String
        if let endDayKey, endDayKey >= startKey {
            finalKey = endDayKey
        } else {
            finalKey = dailyMap.keys.max() ?? startKey
        }

        let clampedAlpha = min(max(alpha, 0.01), 1.0)
        let keys = DayKey.range(from: startKey, to: finalKey, calendar: calendar)
        guard let initialScale = dailyMap[startKey] else { return [] }

        var currentTrend = initialScale
        var points: [DailyWeightPoint] = []
        points.reserveCapacity(keys.count)

        for (index, key) in keys.enumerated() {
            let dt = DayKey.date(from: key, calendar: calendar) ?? .now
            if let measured = dailyMap[key] {
                if index == 0 {
                    currentTrend = measured
                } else {
                    currentTrend = currentTrend + clampedAlpha * (measured - currentTrend)
                }
                points.append(DailyWeightPoint(dayKey: key, date: dt, scaleKg: measured, trendKg: currentTrend))
            } else {
                // Missing day: carry trend forward unchanged, do not fabricate a scale weigh-in.
                points.append(DailyWeightPoint(dayKey: key, date: dt, scaleKg: nil, trendKg: currentTrend))
            }
        }
        return points
    }

    public static func summarize(
        series: [DailyWeightPoint],
        referenceDayKey: String? = nil,
        calendar: Calendar = .current
    ) -> WeightTrendSummary {
        guard !series.isEmpty else {
            return WeightTrendSummary(
                latestTrendKg: nil,
                latestScaleKg: nil,
                change7dKg: nil,
                change14dKg: nil,
                change30dKg: nil,
                weeklyRateKg: nil,
                weeklyRatePercentBW: nil,
                weighInsLast7Days: 0,
                weighInsLast28Days: 0
            )
        }

        let byKey = Dictionary(series.map { ($0.dayKey, $0) }, uniquingKeysWith: { _, latest in latest })
        let endPoint: DailyWeightPoint
        if let ref = referenceDayKey, let exact = byKey[ref] {
            endPoint = exact
        } else {
            endPoint = series[series.count - 1]
        }

        let latestScale = series.last(where: { $0.scaleKg != nil && $0.dayKey <= endPoint.dayKey })?.scaleKg

        func delta(daysBack: Int) -> Double? {
            let targetKey = DayKey.addingDays(-daysBack, to: endPoint.dayKey, calendar: calendar)
            guard let past = byKey[targetKey] else { return nil }
            return endPoint.trendKg - past.trendKg
        }

        let d7 = delta(daysBack: 7)
        let d14 = delta(daysBack: 14)
        let d30 = delta(daysBack: 30)

        let weeklyRate: Double?
        if let d14 {
            weeklyRate = d14 / 2.0
        } else if let d7 {
            weeklyRate = d7
        } else {
            weeklyRate = nil
        }

        let pctRate: Double?
        if let weeklyRate, endPoint.trendKg > 0 {
            pctRate = (weeklyRate / endPoint.trendKg) * 100.0
        } else {
            pctRate = nil
        }

        let start7 = DayKey.addingDays(-6, to: endPoint.dayKey, calendar: calendar)
        let start28 = DayKey.addingDays(-27, to: endPoint.dayKey, calendar: calendar)

        let count7 = series.filter { $0.dayKey >= start7 && $0.dayKey <= endPoint.dayKey && $0.scaleKg != nil }.count
        let count28 = series.filter { $0.dayKey >= start28 && $0.dayKey <= endPoint.dayKey && $0.scaleKg != nil }.count

        return WeightTrendSummary(
            latestTrendKg: endPoint.trendKg,
            latestScaleKg: latestScale,
            change7dKg: d7,
            change14dKg: d14,
            change30dKg: d30,
            weeklyRateKg: weeklyRate,
            weeklyRatePercentBW: pctRate,
            weighInsLast7Days: count7,
            weighInsLast28Days: count28
        )
    }
}
