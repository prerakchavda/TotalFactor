import Foundation
#if canImport(Speech) && canImport(AVFoundation)
import Speech
import AVFoundation
#endif

/// On-device / Apple Speech live dictation service for hands-free meal logging in `QuickAddFoodSheet`.
/// Restores background gym audio (`notifyOthersOnDeactivation`) as soon as dictation stops.
@MainActor
@Observable
public final class SpeechDictationService {
    public var isRecording: Bool = false
    public var errorMessage: String? = nil

    #if canImport(Speech) && canImport(AVFoundation)
    private let speechRecognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var audioEngine: AVAudioEngine? = nil
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest? = nil
    private var recognitionTask: SFSpeechRecognitionTask? = nil
    #endif

    public init() {}

    public func toggleRecording(existingPrefix: String, onTranscriptUpdate: @escaping @MainActor (String) -> Void) {
        if isRecording {
            stopRecording()
        } else {
            Task {
                await startRecording(existingPrefix: existingPrefix, onTranscriptUpdate: onTranscriptUpdate)
            }
        }
    }

    public func startRecording(
        existingPrefix: String,
        onTranscriptUpdate: @escaping @MainActor (String) -> Void
    ) async {
        errorMessage = nil
        #if canImport(Speech) && canImport(AVFoundation)
        let speechAllowed = await requestSpeechPermission()
        guard speechAllowed else {
            errorMessage = "Speech recognition permission was denied. Enable it in iOS Settings → Total Factor."
            return
        }

        let micAllowed = await AVAudioApplication.requestRecordPermission()
        guard micAllowed else {
            errorMessage = "Microphone permission was denied. Enable it in iOS Settings → Total Factor."
            return
        }

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognizer is currently unavailable on this device."
            return
        }

        stopRecording()

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = false
            }

            let inputNode = engine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                request.append(buffer)
            }

            let basePrefix = existingPrefix.trimmingCharacters(in: .whitespacesAndNewlines)

            self.audioEngine = engine
            self.recognitionRequest = request
            self.isRecording = true

            engine.prepare()
            try engine.start()

            self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let spoken = result?.bestTranscription.formattedString
                let isFinal = result?.isFinal ?? false
                let hadError = (error != nil)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let spoken, !spoken.isEmpty {
                        let combined = basePrefix.isEmpty ? spoken : "\(basePrefix), \(spoken)"
                        onTranscriptUpdate(combined)
                    }
                    if isFinal || hadError {
                        self.stopRecording()
                    }
                }
            }
        } catch {
            stopRecording()
            errorMessage = "Could not start microphone dictation: \(error.localizedDescription)"
        }
        #else
        errorMessage = "Speech dictation is only supported on iOS."
        #endif
    }

    public func stopRecording() {
        #if canImport(Speech) && canImport(AVFoundation)
        if let engine = audioEngine {
            if engine.isRunning {
                engine.stop()
            }
            engine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #else
        isRecording = false
        #endif
    }

    #if canImport(Speech)
    private func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
    #endif
}
