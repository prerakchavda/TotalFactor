import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// Program Import & Export Service:
/// - Serializes complete workout programs (splits, exercises, sets, reps, RIR, rest) to/from JSON.
/// - Enables sharing routines with friends, backing up programs, or importing community splits.
@MainActor
public enum ProgramImportExportService {

    public struct ExportableProgramDTO: Codable {
        public var app: String = "TotalFactor"
        public var version: Int = 1
        public var name: String
        public var daysPerWeek: Int
        public var scheduleMode: String
        public var workouts: [ExportableWorkoutDTO]

        public init(
            name: String,
            daysPerWeek: Int,
            scheduleMode: String,
            workouts: [ExportableWorkoutDTO]
        ) {
            self.name = name
            self.daysPerWeek = daysPerWeek
            self.scheduleMode = scheduleMode
            self.workouts = workouts
        }
    }

    public struct ExportableWorkoutDTO: Codable {
        public var name: String
        public var order: Int
        public var scheduledWeekday: Int?
        public var slots: [ExportableSlotDTO]

        public init(
            name: String,
            order: Int,
            scheduledWeekday: Int? = nil,
            slots: [ExportableSlotDTO]
        ) {
            self.name = name
            self.order = order
            self.scheduledWeekday = scheduledWeekday
            self.slots = slots
        }
    }

    public struct ExportableSlotDTO: Codable {
        public var order: Int
        public var exerciseName: String
        public var equipment: String
        public var movementPattern: String
        public var sets: Int
        public var repRangeLow: Int
        public var repRangeHigh: Int
        public var targetRIR: Int
        public var restSeconds: Int
        public var progressionRule: String

        public init(
            order: Int,
            exerciseName: String,
            equipment: String = "barbell",
            movementPattern: String = "isolation",
            sets: Int = 3,
            repRangeLow: Int = 6,
            repRangeHigh: Int = 10,
            targetRIR: Int = 2,
            restSeconds: Int = 120,
            progressionRule: String = "doubleProgression"
        ) {
            self.order = order
            self.exerciseName = exerciseName
            self.equipment = equipment
            self.movementPattern = movementPattern
            self.sets = sets
            self.repRangeLow = repRangeLow
            self.repRangeHigh = repRangeHigh
            self.targetRIR = targetRIR
            self.restSeconds = restSeconds
            self.progressionRule = progressionRule
        }
    }

    // MARK: - Export

    public static func makeDTO(from program: Program) -> ExportableProgramDTO {
        let workoutDTOs = program.sortedWorkouts.map { w in
            let slotDTOs = w.sortedSlots.map { s in
                ExportableSlotDTO(
                    order: s.order,
                    exerciseName: s.exercise?.name ?? "Custom Movement",
                    equipment: s.exercise?.equipment.rawValue ?? Equipment.barbell.rawValue,
                    movementPattern: s.exercise?.movementPattern.rawValue ?? MovementPattern.isolation.rawValue,
                    sets: s.sets,
                    repRangeLow: s.repRangeLow,
                    repRangeHigh: s.repRangeHigh,
                    targetRIR: s.targetRIR,
                    restSeconds: s.restSeconds,
                    progressionRule: s.progressionRuleRaw
                )
            }
            return ExportableWorkoutDTO(
                name: w.name,
                order: w.order,
                scheduledWeekday: w.scheduledWeekday,
                slots: slotDTOs
            )
        }

        return ExportableProgramDTO(
            name: program.name,
            daysPerWeek: program.daysPerWeek,
            scheduleMode: program.scheduleModeRaw,
            workouts: workoutDTOs
        )
    }

    public static func exportProgramToJSON(program: Program) throws -> String {
        let dto = makeDTO(from: program)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(dto)
        return String(decoding: data, as: UTF8.self)
    }

    public static func exportProgramToFile(program: Program) throws -> URL {
        let json = try exportProgramToJSON(program: program)
        let safeName = program.name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = "\(safeName.isEmpty ? "Program" : safeName).totalfactorprogram"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try json.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }

    // MARK: - Import

    public static func importProgram(from data: Data, into context: ModelContext) throws -> Program {
        let decoder = JSONDecoder()
        let dto = try decoder.decode(ExportableProgramDTO.self, from: data)

        // Fetch all existing exercises in database for resolution
        let existingExercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        var exerciseByName: [String: Exercise] = [:]
        for ex in existingExercises {
            exerciseByName[ex.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = ex
        }

        let newProgram = Program(
            name: dto.name,
            daysPerWeek: max(1, min(7, dto.daysPerWeek)),
            isActive: false,
            scheduleMode: ProgramScheduleMode(rawValue: dto.scheduleMode) ?? .rollingSplit
        )
        context.insert(newProgram)

        for wDTO in dto.workouts.sorted(by: { $0.order < $1.order }) {
            let workout = ProgramWorkout(
                name: wDTO.name,
                order: wDTO.order,
                scheduledWeekday: wDTO.scheduledWeekday
            )
            workout.program = newProgram
            context.insert(workout)

            for sDTO in wDTO.slots.sorted(by: { $0.order < $1.order }) {
                let cleanExName = sDTO.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
                let lookupKey = cleanExName.lowercased()

                let resolvedExercise: Exercise
                if let matched = exerciseByName[lookupKey] {
                    resolvedExercise = matched
                } else {
                    // Create new custom exercise if not found in database
                    let eq = Equipment(rawValue: sDTO.equipment) ?? .barbell
                    let mp = MovementPattern(rawValue: sDTO.movementPattern) ?? .isolation
                    let created = Exercise(
                        name: cleanExName,
                        primaryMuscles: [.chest],
                        secondaryMuscles: [],
                        equipment: eq,
                        movementPattern: mp,
                        isCustom: true
                    )
                    context.insert(created)
                    exerciseByName[lookupKey] = created
                    resolvedExercise = created
                }

                let slot = ExerciseSlot(
                    order: sDTO.order,
                    exercise: resolvedExercise,
                    sets: max(1, sDTO.sets),
                    repRangeLow: max(1, sDTO.repRangeLow),
                    repRangeHigh: max(sDTO.repRangeLow, sDTO.repRangeHigh),
                    targetRIR: max(0, min(5, sDTO.targetRIR)),
                    restSeconds: max(15, sDTO.restSeconds),
                    progressionRule: ProgressionRule(rawValue: sDTO.progressionRule) ?? .doubleProgression
                )
                slot.workout = workout
                context.insert(slot)
            }
        }

        try context.save()
        _ = CoachingCoordinator.evaluate(context: context)
        return newProgram
    }

    public static func importProgram(from jsonString: String, into context: ModelContext) throws -> Program {
        guard let data = jsonString.data(using: .utf8) else {
            throw NSError(domain: "ProgramImport", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid program text encoding."])
        }
        return try importProgram(from: data, into: context)
    }

    public static func importProgram(from fileURL: URL, into context: ModelContext) throws -> Program {
        let accessed = fileURL.startAccessingSecurityScopedResource()
        defer { if accessed { fileURL.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: fileURL)
        return try importProgram(from: data, into: context)
    }
}
