import SwiftUI
import SwiftData
#if canImport(VisionKit) && canImport(UIKit)
import VisionKit
import UIKit
#endif

struct BarcodeScannerView: View {
    @Environment(\.modelContext) private var modelContext

    let usdaApiKey: String
    var onResolved: (BarcodeLookupOutcome) -> Void

    @State private var manualBarcode: String = ""
    @State private var isLookingUp: Bool = false
    @State private var statusText: String = "Point camera at any UPC / EAN barcode"

    private var scannerAvailable: Bool {
        #if canImport(VisionKit) && canImport(UIKit)
        return DataScannerViewController.isSupported && DataScannerViewController.isAvailable
        #else
        return false
        #endif
    }

    var body: some View {
        VStack(spacing: 16) {
            if scannerAvailable {
                #if canImport(VisionKit) && canImport(UIKit)
                HardwareBarcodeScannerRepresentable { scannedDigits in
                    guard !isLookingUp else { return }
                    lookup(barcode: scannedDigits)
                }
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)
                #endif
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Live Camera Scanner Requires Physical iPhone")
                        .font(.subheadline.weight(.semibold))
                    Text("Enter a UPC/EAN barcode below to run the full Cache → Open Food Facts → USDA Branded → Label OCR cascade.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)
            }

            if isLookingUp {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                TextField("Manual UPC / EAN (e.g. 0016000275287)", text: $manualBarcode)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)

                Button("Lookup") {
                    lookup(barcode: manualBarcode)
                }
                .buttonStyle(.borderedProminent)
                .disabled(manualBarcode.trimmingCharacters(in: .whitespaces).isEmpty || isLookingUp)
            }
            .padding(.horizontal)

            Text("Barcode data includes crowdsourced Open Food Facts (ODbL) & USDA FoodData Central.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Spacer()
        }
        .padding(.top, 12)
    }

    private func lookup(barcode: String) {
        isLookingUp = true
        statusText = "Checking local cache, Open Food Facts & USDA..."
        Task {
            let outcome = await BarcodeLookupCoordinator.resolve(
                barcode: barcode,
                usdaApiKey: usdaApiKey,
                context: modelContext
            )
            await MainActor.run {
                isLookingUp = false
                onResolved(outcome)
            }
        }
    }
}

#if canImport(VisionKit) && canImport(UIKit)
private struct HardwareBarcodeScannerRepresentable: UIViewControllerRepresentable {
    var onBarcodeScanned: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBarcodeScanned: onBarcodeScanned)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onBarcodeScanned: (String) -> Void
        private var didEmit = false

        init(onBarcodeScanned: @escaping (String) -> Void) {
            self.onBarcodeScanned = onBarcodeScanned
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !didEmit else { return }
            for item in addedItems {
                if case .barcode(let code) = item, let payload = code.payloadStringValue, !payload.isEmpty {
                    didEmit = true
                    dataScanner.stopScanning()
                    onBarcodeScanned(payload)
                    break
                }
            }
        }
    }
}
#endif
