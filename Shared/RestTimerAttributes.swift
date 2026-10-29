import Foundation
#if canImport(ActivityKit)
import ActivityKit

public struct RestTimerAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var endDate: Date
        public var totalSeconds: Int
        public var isPaused: Bool
        public var remainingWhenPaused: Int
        public var nextSetSummary: String

        public init(
            endDate: Date,
            totalSeconds: Int,
            isPaused: Bool = false,
            remainingWhenPaused: Int = 0,
            nextSetSummary: String = ""
        ) {
            self.endDate = endDate
            self.totalSeconds = totalSeconds
            self.isPaused = isPaused
            self.remainingWhenPaused = remainingWhenPaused
            self.nextSetSummary = nextSetSummary
        }
    }

    public var workoutName: String
    public var exerciseName: String
    public var setNumber: Int

    public init(workoutName: String, exerciseName: String, setNumber: Int) {
        self.workoutName = workoutName
        self.exerciseName = exerciseName
        self.setNumber = setNumber
    }
}
#endif
