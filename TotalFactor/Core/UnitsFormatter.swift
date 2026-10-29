import Foundation

public enum UnitsFormatter {
    public static let kgPerLb: Double = 0.45359237
    public static let lbPerKg: Double = 2.20462262185
    public static let cmPerInch: Double = 2.54
    public static let gramsPerOunce: Double = 28.349523125

    public static func kgToLb(_ kg: Double) -> Double {
        kg * lbPerKg
    }

    public static func lbToKg(_ lb: Double) -> Double {
        lb * kgPerLb
    }

    public static func displayWeight(_ kg: Double, system: UnitSystem) -> Double {
        system == .imperial ? kgToLb(kg) : kg
    }

    public static func internalKg(fromDisplay value: Double, system: UnitSystem) -> Double {
        system == .imperial ? lbToKg(value) : value
    }

    public static func formatWeight(_ kg: Double, system: UnitSystem, decimals: Int = 1, includeUnit: Bool = true) -> String {
        let val = displayWeight(kg, system: system)
        let num = String(format: "%.\(decimals)f", val)
        return includeUnit ? "\(num) \(system.weightSymbol)" : num
    }

    public static func formatSignedWeightDelta(_ deltaKg: Double, system: UnitSystem, decimals: Int = 1) -> String {
        let val = displayWeight(deltaKg, system: system)
        let sign = val > 0.005 ? "+" : ""
        return "\(sign)\(String(format: "%.\(decimals)f", val)) \(system.weightSymbol)"
    }

    public static func formatGymLoad(_ kg: Double, system: UnitSystem) -> String {
        let val = displayWeight(kg, system: system)
        let rounded = (val * 4).rounded() / 4.0
        if abs(rounded.rounded() - rounded) < 0.01 {
            return "\(Int(rounded.rounded())) \(system.weightSymbol)"
        }
        return String(format: "%.1f %@", rounded, system.weightSymbol)
    }

    public static func cmToFeetInches(_ cm: Double) -> (feet: Int, inches: Int) {
        let totalInches = Int((cm / cmPerInch).rounded())
        return (totalInches / 12, totalInches % 12)
    }

    public static func feetInchesToCm(feet: Int, inches: Int) -> Double {
        Double(feet * 12 + inches) * cmPerInch
    }

    public static func displayLength(_ cm: Double, system: UnitSystem) -> Double {
        system == .imperial ? (cm / cmPerInch) : cm
    }

    public static func internalCm(fromDisplay value: Double, system: UnitSystem) -> Double {
        system == .imperial ? (value * cmPerInch) : value
    }
}
