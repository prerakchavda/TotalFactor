import Foundation
import Vision
#if canImport(UIKit)
import UIKit
#endif

/// Result of on-device Apple Vision classification on a meal photo or plate camera capture.
public struct DetectedPlateFood: Identifiable, Sendable {
    public var id: String { identifier }
    public var identifier: String
    public var displayName: String
    public var confidence: Float
    public var suggestedSearchQuery: String

    public init(identifier: String, displayName: String, confidence: Float, suggestedSearchQuery: String) {
        self.identifier = identifier
        self.displayName = displayName
        self.confidence = confidence
        self.suggestedSearchQuery = suggestedSearchQuery
    }
}

/// 100% on-device, private meal photo classifier using Apple's built-in `Vision.framework` (`VNClassifyImageRequest`).
/// Recognizes common foods, dishes, fruits, proteins, and meals on the Apple Neural Engine without requiring
/// any external cloud AI API, Google Gemini key, or internet connection.
public enum AppleVisionFoodClassifier {

    /// Curated subset of Apple's 1,300+ Vision taxonomy classes mapped to high-yield USDA food queries.
    private static let foodTaxonomyMap: [String: (display: String, query: String)] = [
        "scrambled_eggs": ("Scrambled Eggs", "scrambled eggs"),
        "fried_egg": ("Fried Eggs", "fried eggs"),
        "egg": ("Eggs", "eggs whole"),
        "grilled_chicken": ("Grilled Chicken", "chicken breast cooked"),
        "fried_chicken": ("Fried Chicken", "fried chicken"),
        "steak": ("Steak", "beef top sirloin steak cooked"),
        "beef": ("Beef", "ground beef"),
        "salmon": ("Salmon", "salmon cooked"),
        "tuna": ("Tuna", "tuna canned"),
        "fish": ("Fish", "fish cooked"),
        "seafood": ("Seafood", "shrimp cooked"),
        "bacon": ("Bacon", "bacon cooked"),
        "sausage": ("Sausage", "pork sausage"),
        "meatball": ("Meatballs", "meatballs"),
        "hamburger": ("Burger", "hamburger"),
        "pizza": ("Pizza", "cheese pizza"),
        "sandwich": ("Sandwich", "turkey sandwich"),
        "taco": ("Taco", "beef taco"),
        "sushi": ("Sushi", "sushi roll"),
        "pasta": ("Pasta", "pasta cooked"),
        "spaghetti": ("Spaghetti", "spaghetti cooked"),
        "rice": ("White Rice", "white rice cooked"),
        "salad": ("Salad", "garden salad"),
        "soup": ("Soup", "chicken vegetable soup"),
        "bread": ("Bread", "whole wheat bread"),
        "white_bread": ("White Bread", "white bread"),
        "toast": ("Toast", "bread"),
        "pancake": ("Pancakes", "pancake"),
        "waffle": ("Waffles", "waffle"),
        "oatmeal": ("Oatmeal", "rolled oats"),
        "yogurt": ("Greek Yogurt", "greek yogurt plain"),
        "cheese": ("Cheese", "cheddar cheese"),
        "apple": ("Apple", "apple raw"),
        "banana": ("Banana", "banana raw"),
        "orange": ("Orange", "orange raw"),
        "oranges": ("Orange", "orange raw"),
        "citrus_fruit": ("Citrus Fruit", "orange raw"),
        "strawberry": ("Strawberries", "strawberries raw"),
        "blueberry": ("Blueberries", "blueberries raw"),
        "blackberry": ("Blackberries", "blackberries raw"),
        "raspberry": ("Raspberries", "raspberries raw"),
        "avocado": ("Avocado", "avocado raw"),
        "broccoli": ("Broccoli", "broccoli cooked"),
        "carrot": ("Carrots", "carrots raw"),
        "potato": ("Potato", "baked potato"),
        "tomato": ("Tomato", "tomato raw"),
        "coffee": ("Coffee", "black coffee"),
        "cookie": ("Cookie", "chocolate chip cookie"),
        "cake": ("Cake", "cake"),
        "cake_regular": ("Cake", "cake"),
        "cupcake": ("Cupcake", "cupcake"),
        "cheesecake": ("Cheesecake", "cheesecake"),
        "pie": ("Pie", "apple pie"),
        "dessert": ("Dessert", "ice cream")
    ]

    #if canImport(UIKit)
    /// Classifies foods present in a `UIImage` completely on-device.
    public static func classifyFood(in image: UIImage) async -> [DetectedPlateFood] {
        guard let cgImage = image.cgImage else { return [] }
        return await classifyFood(in: cgImage)
    }
    #endif

    /// Classifies foods present in a `CGImage` on the Apple Neural Engine via `VNClassifyImageRequest`.
    public static func classifyFood(in cgImage: CGImage) async -> [DetectedPlateFood] {
        await withCheckedContinuation { continuation in
            let request = VNClassifyImageRequest { req, error in
                guard error == nil,
                      let observations = req.results as? [VNClassificationObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                var detected: [DetectedPlateFood] = []
                for obs in observations {
                    guard obs.confidence >= 0.035 else { continue }
                    let key = obs.identifier.lowercased()
                    if let mapped = foodTaxonomyMap[key] {
                        detected.append(
                            DetectedPlateFood(
                                identifier: obs.identifier,
                                displayName: mapped.display,
                                confidence: obs.confidence,
                                suggestedSearchQuery: mapped.query
                            )
                        )
                    }
                }

                // Deduplicate by displayName, keep highest confidence
                var bestByDisplay: [String: DetectedPlateFood] = [:]
                for item in detected {
                    if let prev = bestByDisplay[item.displayName] {
                        if item.confidence > prev.confidence {
                            bestByDisplay[item.displayName] = item
                        }
                    } else {
                        bestByDisplay[item.displayName] = item
                    }
                }

                let sorted = bestByDisplay.values.sorted { $0.confidence > $1.confidence }
                continuation.resume(returning: Array(sorted.prefix(5)))
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }
}
