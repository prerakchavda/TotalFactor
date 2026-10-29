import SwiftUI
import SwiftData
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

/// Spec §7 Progress Photos:
/// - Support single photo viewing, gallery history reel, and side-by-side / split-slider comparison.
/// - Filtered by pose (Front / Side / Back) with date & weight badges.
/// - Camera capture and PhotosPicker support with downsampling.
/// - Delete photo capability.
struct PhotoCompareView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let unitSystem: UnitSystem
    let currentWeightKg: Double?

    @Query(sort: \ProgressPhoto.date, order: .forward) private var allPhotos: [ProgressPhoto]

    @State private var selectedPose: PhotoPose = .front
    @State private var compareMode: CompareDisplayMode = .slider
    @State private var pickerItem: PhotosPickerItem? = nil
    @State private var showingCamera: Bool = false
    @State private var sliderPosition: CGFloat = 0.5
    @State private var leftPhotoID: UUID? = nil
    @State private var rightPhotoID: UUID? = nil
    @State private var photoToDelete: ProgressPhoto? = nil
    @State private var showingDeleteConfirmation: Bool = false
    @State private var fullScreenPhoto: ProgressPhoto? = nil

    private enum CompareDisplayMode: String, CaseIterable, Identifiable {
        case slider = "Split Slider"
        case sideBySide = "Side by Side"
        var id: String { rawValue }
    }

    private var posePhotos: [ProgressPhoto] {
        allPhotos.filter { $0.pose == selectedPose }
    }

    private var beforePhoto: ProgressPhoto? {
        if let id = leftPhotoID, let found = posePhotos.first(where: { $0.id == id }) {
            return found
        }
        return posePhotos.first
    }

    private var afterPhoto: ProgressPhoto? {
        if let id = rightPhotoID, let found = posePhotos.first(where: { $0.id == id }) {
            return found
        }
        return posePhotos.count > 1 ? posePhotos.last : nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Pose Selector
                    Picker("Pose", selection: $selectedPose) {
                        ForEach(PhotoPose.allCases) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    // Main Comparison / Single Photo Area
                    if posePhotos.count >= 2, let before = beforePhoto, let after = afterPhoto {
                        comparisonSection(before: before, after: after)
                    } else if let single = posePhotos.first {
                        singlePhotoSection(single)
                    } else {
                        emptyStateSection
                    }

                    // Photo Action Buttons (Camera & Library)
                    actionButtons

                    // History Gallery Reel
                    if !posePhotos.isEmpty {
                        gallerySection
                    }
                }
                .padding(.vertical, 8)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Progress Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: pickerItem) { _, newItem in
                handlePhotosPickerItem(newItem)
            }
            #if canImport(UIKit)
            .sheet(isPresented: $showingCamera) {
                ProgressPhotoCameraPicker { capturedImage in
                    saveCapturedImage(capturedImage)
                }
            }
            #endif
            .sheet(item: $fullScreenPhoto) { photo in
                FullScreenPhotoViewer(photo: photo, unitSystem: unitSystem)
            }
            .confirmationDialog(
                "Delete Progress Photo?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Photo", role: .destructive) {
                    if let target = photoToDelete {
                        deletePhoto(target)
                    }
                }
                Button("Cancel", role: .cancel) {
                    photoToDelete = nil
                }
            } message: {
                Text("This will permanently remove this progress photo from your history.")
            }
        }
    }

    // MARK: - Comparison Section (>= 2 photos)

    private func comparisonSection(before: ProgressPhoto, after: ProgressPhoto) -> some View {
        VStack(spacing: 12) {
            // Mode Picker (Slider vs Side-by-Side)
            Picker("Mode", selection: $compareMode) {
                ForEach(CompareDisplayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            // Selectors for Before & After photos
            HStack(spacing: 12) {
                Menu {
                    ForEach(posePhotos) { p in
                        Button {
                            leftPhotoID = p.id
                        } label: {
                            HStack {
                                Text("\(p.dayKey)\(p.weightKgAtCapture.map { " (\(UnitsFormatter.formatWeight($0, system: unitSystem)))" } ?? "")")
                                if p.id == before.id { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Before")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            Text(before.dayKey)
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                        }
                        if let w = before.weightKgAtCapture {
                            Text(UnitsFormatter.formatWeight(w, system: unitSystem))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }

                // Delta Summary Pill
                let dayDiff = max(0, Calendar.current.dateComponents([.day], from: before.date, to: after.date).day ?? 0)
                VStack(spacing: 2) {
                    Text("\(dayDiff)d apart")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                    if let bw = before.weightKgAtCapture, let aw = after.weightKgAtCapture {
                        let diff = aw - bw
                        Text(UnitsFormatter.formatSignedWeightDelta(diff, system: unitSystem))
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(diff <= 0 ? .green : .orange)
                    }
                }
                .padding(.horizontal, 8)

                Menu {
                    ForEach(posePhotos) { p in
                        Button {
                            rightPhotoID = p.id
                        } label: {
                            HStack {
                                Text("\(p.dayKey)\(p.weightKgAtCapture.map { " (\(UnitsFormatter.formatWeight($0, system: unitSystem)))" } ?? "")")
                                if p.id == after.id { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("After")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            Text(after.dayKey)
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                        }
                        if let w = after.weightKgAtCapture {
                            Text(UnitsFormatter.formatWeight(w, system: unitSystem))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal)

            // Visual comparison area
            if compareMode == .slider {
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    ZStack(alignment: .leading) {
                        photoImage(after.imageData)
                            .frame(width: w, height: h)
                            .clipped()

                        photoImage(before.imageData)
                            .frame(width: w, height: h)
                            .mask(alignment: .leading) {
                                Rectangle()
                                    .frame(width: max(0, w * sliderPosition), height: h)
                            }

                        // Draggable Divider Line & Knob
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 3, height: h)
                            .offset(x: w * sliderPosition - 1.5)

                        Circle()
                            .fill(Color.white)
                            .frame(width: 32, height: 32)
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                            .overlay(
                                Image(systemName: "arrow.left.and.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.black)
                            )
                            .offset(x: w * sliderPosition - 16, y: h / 2 - 16)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { val in
                                sliderPosition = min(0.96, max(0.04, val.location.x / max(1, w)))
                            }
                    )
                }
                .frame(height: 380)
                .padding(.horizontal)
            } else {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        photoImage(before.imageData)
                            .frame(height: 320)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        Text("Before: \(before.dayKey)")
                            .font(.caption2.weight(.bold))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        photoImage(after.imageData)
                            .frame(height: 320)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        Text("After: \(after.dayKey)")
                            .font(.caption2.weight(.bold))
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Single Photo Section (1 photo)

    private func singlePhotoSection(_ photo: ProgressPhoto) -> some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                photoImage(photo.imageData)
                    .frame(height: 380)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(photo.dayKey)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                        if let w = photo.weightKgAtCapture {
                            Text(UnitsFormatter.formatWeight(w, system: unitSystem))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    Spacer()
                    Button {
                        fullScreenPhoto = photo
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.weight(.semibold))
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                            .foregroundStyle(.white)
                    }
                }
                .padding(14)
                .background(
                    LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                )
            }
            .padding(.horizontal)

            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.accentColor)
                Text("Add another \(selectedPose.displayName.lowercased()) photo on a future date to compare side-by-side or with the interactive pose slider!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Empty State (0 photos)

    private var emptyStateSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 24)

            VStack(spacing: 6) {
                Text("No \(selectedPose.displayName) Photos Yet")
                    .font(.headline)
                Text("Capture or choose your first \(selectedPose.displayName.lowercased()) pose photo to track physique changes over time.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - Action Buttons (Camera & Library)

    private var actionButtons: some View {
        HStack(spacing: 12) {
            #if canImport(UIKit)
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showingCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
            }
            #endif

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Choose Photo", systemImage: "photo.badge.plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal)
    }

    // MARK: - History Gallery Reel

    private var gallerySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(selectedPose.displayName) History (\(posePhotos.count))")
                    .font(.headline)
                Spacer()
                Text("Tap to view • Hold to delete")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(posePhotos) { photo in
                        VStack(alignment: .leading, spacing: 6) {
                            ZStack(alignment: .topTrailing) {
                                photoImage(photo.imageData)
                                    .frame(width: 100, height: 130)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .onTapGesture {
                                        fullScreenPhoto = photo
                                    }

                                Button {
                                    photoToDelete = photo
                                    showingDeleteConfirmation = true
                                } label: {
                                    Image(systemName: "trash.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.white, .red)
                                }
                                .padding(4)
                            }

                            Text(photo.dayKey)
                                .font(.caption2.weight(.bold))
                                .lineLimit(1)

                            if let w = photo.weightKgAtCapture {
                                Text(UnitsFormatter.formatWeight(w, system: unitSystem))
                                    .font(.system(size: 10).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 100)
                        .contextMenu {
                            Button {
                                leftPhotoID = photo.id
                            } label: {
                                Label("Set as 'Before'", systemImage: "arrow.left.to.line")
                            }
                            Button {
                                rightPhotoID = photo.id
                            } label: {
                                Label("Set as 'After'", systemImage: "arrow.right.to.line")
                            }
                            Divider()
                            Button(role: .destructive) {
                                photoToDelete = photo
                                showingDeleteConfirmation = true
                            } label: {
                                Label("Delete Photo", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func photoImage(_ data: Data?) -> some View {
        #if canImport(UIKit)
        if let data, let uiImg = UIImage(data: data) {
            Image(uiImage: uiImg)
                .resizable()
                .scaledToFill()
        } else {
            Color.secondary.opacity(0.15)
        }
        #else
        Color.secondary.opacity(0.15)
        #endif
    }

    private func handlePhotosPickerItem(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                #if canImport(UIKit)
                if let uiImg = UIImage(data: data) {
                    await MainActor.run {
                        saveCapturedImage(uiImg)
                    }
                    return
                }
                #endif
                await MainActor.run {
                    insertPhoto(data: data)
                }
            }
        }
    }

    #if canImport(UIKit)
    private func saveCapturedImage(_ image: UIImage) {
        // Downsample to max 1600px dimension and compress to JPEG 0.8
        let maxDim: CGFloat = 1600
        let size = image.size
        let scale = min(1.0, maxDim / max(size.width, size.height))
        let targetSize = CGSize(width: round(size.width * scale), height: round(size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        if let jpeg = resized.jpegData(compressionQuality: 0.8) {
            insertPhoto(data: jpeg)
        }
    }
    #endif

    private func insertPhoto(data: Data) {
        let p = ProgressPhoto(
            pose: selectedPose,
            imageData: data,
            weightKgAtCapture: currentWeightKg
        )
        modelContext.insert(p)
        try? modelContext.save()
        rightPhotoID = p.id
    }

    private func deletePhoto(_ photo: ProgressPhoto) {
        modelContext.delete(photo)
        try? modelContext.save()
        photoToDelete = nil
        if leftPhotoID == photo.id { leftPhotoID = nil }
        if rightPhotoID == photo.id { rightPhotoID = nil }
    }
}

// MARK: - Full Screen Viewer

private struct FullScreenPhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let photo: ProgressPhoto
    let unitSystem: UnitSystem

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                #if canImport(UIKit)
                if let data = photo.imageData, let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .padding()
                }
                #endif
            }
            .navigationTitle("\(photo.pose.displayName) • \(photo.dayKey)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

// MARK: - Native Camera Picker

#if canImport(UIKit)
private struct ProgressPhotoCameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onCapture: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ProgressPhotoCameraPicker

        init(parent: ProgressPhotoCameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let img = info[.originalImage] as? UIImage {
                parent.onCapture(img)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
#endif
