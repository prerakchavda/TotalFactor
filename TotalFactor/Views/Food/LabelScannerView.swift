import SwiftUI
import PhotosUI
#if canImport(Vision) && canImport(UIKit)
import Vision
import UIKit
#endif

/// Spec §1, §4 & §13 Nutrition Label OCR Scanner:
/// Extracts Calories, Protein, Carbs, Fat, Fiber, Sugar, Sodium, and Serving Weight from a photo of any Nutrition Facts panel.
struct LabelScannerView: View {
    let prefilledBarcode: String?
    var onParsed: (ParsedNutritionLabel, String?) -> Void

    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var rawLabelText: String = ""
    @State private var isProcessingOCR: Bool = false
    @State private var statusMessage: String? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let bc = prefilledBarcode, !bc.isEmpty {
                    HStack {
                        Image(systemName: "barcode")
                        Text("Barcode \(bc) not in online DBs — scan its Nutrition Facts label to save it!")
                            .font(.caption)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                }

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    VStack(spacing: 10) {
                        Image(systemName: "doc.text.viewfinder")
                            .font(.system(size: 42))
                            .foregroundStyle(Color.accentColor)
                        Text("Choose or Snap Nutrition Facts Photo")
                            .font(.headline)
                        Text("Vision OCR automatically reads Serving Size, Calories, Protein, Carbs, Fat, Fiber & Sodium.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity)
                    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                }
                .onChange(of: selectedPhotoItem) { _, newItem in
                    guard let newItem else { return }
                    processPhoto(newItem)
                }

                if isProcessingOCR {
                    ProgressView("Running Vision OCR...")
                }

                if let msg = statusMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Or Paste / Review Recognized Label Text")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $rawLabelText)
                        .frame(minHeight: 140)
                        .padding(6)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

                    HStack {
                        Button("Fill Demo Label") {
                            rawLabelText = """
                            Nutrition Facts
                            Serving size 1 bar (60g)
                            Calories 210
                            Total Fat 7g
                            Saturated Fat 2.5g
                            Sodium 190mg
                            Total Carbohydrate 22g
                            Dietary Fiber 5g
                            Total Sugars 2g
                            Protein 20g
                            """
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Spacer()

                        Button("Parse into Custom Food") {
                            let lines = rawLabelText.components(separatedBy: .newlines)
                            let parsed = NutritionLabelParser.parse(lines: lines)
                            onParsed(parsed, prefilledBarcode)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(rawLabelText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .padding()
        }
    }

    private func processPhoto(_ item: PhotosPickerItem) {
        isProcessingOCR = true
        statusMessage = nil
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                await MainActor.run {
                    isProcessingOCR = false
                    statusMessage = "Could not load image data."
                }
                return
            }

            #if canImport(Vision) && canImport(UIKit)
            guard let uiImage = UIImage(data: data), let cgImage = uiImage.cgImage else {
                await MainActor.run {
                    isProcessingOCR = false
                    statusMessage = "Unsupported image format."
                }
                return
            }

            let lines = await recognizeTextLines(from: cgImage)
            await MainActor.run {
                isProcessingOCR = false
                rawLabelText = lines.joined(separator: "\n")
                let parsed = NutritionLabelParser.parse(lines: lines)
                if parsed.isUsable {
                    onParsed(parsed, prefilledBarcode)
                } else {
                    statusMessage = "Recognized text — verify lines below and tap Parse."
                }
            }
            #else
            await MainActor.run {
                isProcessingOCR = false
            }
            #endif
        }
    }

    #if canImport(Vision) && canImport(UIKit)
    private func recognizeTextLines(from cgImage: CGImage) async -> [String] {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, _ in
                let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
                let strings = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: strings)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }
    #endif
}
