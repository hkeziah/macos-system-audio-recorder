import Cocoa
import AVFoundation
import CoreAudio
import AudioToolbox

// ─── Main Window Controller ──────────────────────────────────────────────

final class MainWindowController: NSWindowController {
    private let recorder = AudioRecorder()
    private var recordButton: NSButton!
    private var statusLabel: NSTextField!
    private var durationLabel: NSTextField!
    private var outputLabel: NSTextField!
    private var durationTimer: Timer?
    private var recordingStartTime: Date?
    private var levelLabel: NSTextField!
    private var silenceLabel: NSTextField!
    private var transcribeToggle: NSButton!
    private var transcribeLabel: NSTextField!
    private var titleField: NSTextField!

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 370),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "System Audio Record and Transcribe"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
        updateUI(recording: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        // ── Title ──
        let titleLabel = NSTextField(labelWithString: "System Audio Record and Transcribe")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 18)
        titleLabel.alignment = .center
        titleLabel.frame = NSRect(x: 20, y: 328, width: 380, height: 24)
        contentView.addSubview(titleLabel)

        // ── Status indicator ──
        statusLabel = NSTextField(labelWithString: "Ready")
        statusLabel.font = NSFont.systemFont(ofSize: 13)
        statusLabel.alignment = .center
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.frame = NSRect(x: 20, y: 306, width: 380, height: 18)
        contentView.addSubview(statusLabel)

        // ── File title field ──
        let titleFieldLabel = NSTextField(labelWithString: "File Title (optional)")
        titleFieldLabel.font = NSFont.systemFont(ofSize: 10)
        titleFieldLabel.textColor = .secondaryLabelColor
        titleFieldLabel.frame = NSRect(x: 80, y: 280, width: 120, height: 14)
        contentView.addSubview(titleFieldLabel)

        titleField = NSTextField(frame: NSRect(x: 80, y: 258, width: 260, height: 22))
        titleField.placeholderString = "e.g. meeting-notes"
        titleField.font = NSFont.systemFont(ofSize: 12)
        titleField.bezelStyle = .roundedBezel
        titleField.isEditable = true
        titleField.isSelectable = true
        contentView.addSubview(titleField)

        // ── Transcription toggle ──
        transcribeToggle = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleTranscription))
        transcribeToggle.frame = NSRect(x: 80, y: 228, width: 20, height: 20)
        transcribeToggle.state = .on
        contentView.addSubview(transcribeToggle)

        transcribeLabel = NSTextField(labelWithString: "Transcribe to markdown when recording stops")
        transcribeLabel.font = NSFont.systemFont(ofSize: 10)
        transcribeLabel.textColor = .secondaryLabelColor
        transcribeLabel.frame = NSRect(x: 104, y: 230, width: 270, height: 16)
        contentView.addSubview(transcribeLabel)

        // ── Record Button ──
        recordButton = NSButton(title: "Start Recording", target: self, action: #selector(toggleRecording))
        recordButton.frame = NSRect(x: 110, y: 175, width: 200, height: 50)
        recordButton.bezelStyle = .rounded
        recordButton.font = NSFont.boldSystemFont(ofSize: 15)
        recordButton.keyEquivalent = "\r" // Enter key toggles
        contentView.addSubview(recordButton)

        // ── Show in Finder (tight below the record button) ──
        let finderBtn = NSButton(title: "Show Recordings in Finder", target: self, action: #selector(showInFinder))
        finderBtn.frame = NSRect(x: 130, y: 148, width: 160, height: 24)
        finderBtn.bezelStyle = .rounded
        finderBtn.font = NSFont.systemFont(ofSize: 11)
        contentView.addSubview(finderBtn)

        // ── Duration (visible during recording) ──
        durationLabel = NSTextField(labelWithString: "")
        durationLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 20, weight: .medium)
        durationLabel.alignment = .center
        durationLabel.frame = NSRect(x: 20, y: 118, width: 380, height: 26)
        durationLabel.isHidden = true
        contentView.addSubview(durationLabel)

        // ── Audio level meter (visible during recording) ──
        levelLabel = NSTextField(labelWithString: "")
        levelLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        levelLabel.alignment = .center
        levelLabel.textColor = .tertiaryLabelColor
        levelLabel.frame = NSRect(x: 20, y: 98, width: 380, height: 16)
        levelLabel.isHidden = true
        contentView.addSubview(levelLabel)

        // ── Silence countdown (visible during recording) ──
        silenceLabel = NSTextField(labelWithString: "")
        silenceLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        silenceLabel.alignment = .center
        silenceLabel.textColor = .secondaryLabelColor
        silenceLabel.frame = NSRect(x: 20, y: 78, width: 380, height: 16)
        silenceLabel.isHidden = true
        contentView.addSubview(silenceLabel)

        // ── Output folder ──
        let folderLabel = NSTextField(labelWithString: "Saves to: /Users/howardkeziah/System-Audio-Recordings/")
        folderLabel.font = NSFont.systemFont(ofSize: 10)
        folderLabel.textColor = .tertiaryLabelColor
        folderLabel.alignment = .center
        folderLabel.frame = NSRect(x: 20, y: 54, width: 380, height: 16)
        contentView.addSubview(folderLabel)

        // ── Requirement note ──
        let noteLabel = NSTextField(labelWithString: "Requires BlackHole. Download: github.com/ExistentialAudio/BlackHole")
        noteLabel.font = NSFont.systemFont(ofSize: 9)
        noteLabel.textColor = .quaternaryLabelColor
        noteLabel.alignment = .center
        noteLabel.frame = NSRect(x: 20, y: 10, width: 380, height: 14)
        contentView.addSubview(noteLabel)

        // ── Set up callbacks ──
        recorder.onStateChange = { [weak self] recording in
            DispatchQueue.main.async {
                self?.updateUI(recording: recording)
            }
        }
        recorder.onError = { [weak self] msg in
            DispatchQueue.main.async {
                self?.showError(msg)
            }
        }
    }

    private func updateUI(recording: Bool) {
        if recording {
            recordButton.title = "■  Stop Recording"
            recordButton.contentTintColor = .systemRed
            statusLabel.stringValue = "●  Recording system audio…"
            statusLabel.textColor = .systemRed
            durationLabel.isHidden = false
            levelLabel.isHidden = false
            silenceLabel.isHidden = false
            recordingStartTime = Date()
            startDurationTimer()
        } else {
            recordButton.title = "●  Start Recording"
            recordButton.contentTintColor = nil
            statusLabel.stringValue = "Ready"
            statusLabel.textColor = .secondaryLabelColor
            durationLabel.isHidden = true
            levelLabel.isHidden = true
            silenceLabel.isHidden = true
            durationTimer?.invalidate()
            durationTimer = nil
            recordingStartTime = nil
        }
    }

    private func startDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, let start = self.recordingStartTime else { return }
            let elapsed = Date().timeIntervalSince(start)
            let h = Int(elapsed) / 3600
            let m = (Int(elapsed) % 3600) / 60
            let s = Int(elapsed) % 60
            self.durationLabel.stringValue = String(format: "%02d:%02d:%02d", h, m, s)

            // Audio level
            let db: Float = self.recorder.currentPeakLevel > 0
                ? 20 * log10(self.recorder.currentPeakLevel)
                : -96
            let bar = String(repeating: "█", count: max(1, Int((db + 60) / 3)))
            self.levelLabel.stringValue = String(format: "Level: %.1f dB  %@", db, bar)

            // Silence countdown
            let silentSec = self.recorder.silentSeconds
            if silentSec > 0 {
                self.silenceLabel.stringValue = String(format: "Silence: %.0fs / %.0fs", silentSec, self.recorder.maxSilentSeconds)
            } else {
                self.silenceLabel.stringValue = ""
            }

            // Check for silence auto-stop
            if silentSec >= self.recorder.maxSilentSeconds {
                self.recorder.stop()
                let sec = Int(self.recorder.maxSilentSeconds)
                self.statusLabel.stringValue = "Stopped — \(sec)s silence detected"
                self.statusLabel.textColor = .secondaryLabelColor
                self.maybeTranscribe()
            }
        }
    }

    @objc private func toggleRecording() {
        if recorder.recording {
            stopAndMaybeTranscribe()
        } else {
            guard let deviceID = AudioDeviceFinder.findBlackHole() else {
                showBlackHoleMissing()
                return
            }
            do {
                recorder.customFilename = titleField.stringValue
                try recorder.start(deviceID: deviceID)
            } catch {
                showError(error.localizedDescription)
            }
        }
    }

    @objc private func showInFinder() {
        NSWorkspace.shared.open(recorder.outputDirectory)
    }

    @objc private func toggleTranscription() {
        // Just toggles the checkbox state; checked state read at stop time
    }

    private func stopAndMaybeTranscribe() {
        let fileURL = recorder.lastRecordedFileURL
        recorder.stop()
        if transcribeToggle.state == .on, let url = fileURL {
            transcribe(url)
        }
    }

    private func maybeTranscribe() {
        if transcribeToggle.state == .on, let url = recorder.lastRecordedFileURL {
            transcribe(url)
        }
    }

    private func transcribe(_ audioURL: URL) {
        let customTitle = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        statusLabel.stringValue = "Transcribing…"
        statusLabel.textColor = .systemOrange
        Transcriber.transcribe(audioURL, title: customTitle.isEmpty ? nil : customTitle) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let mdURL):
                    self?.statusLabel.stringValue = "Transcription saved"
                    self?.statusLabel.textColor = .secondaryLabelColor
                    NSWorkspace.shared.activateFileViewerSelecting([mdURL])
                case .failure(let error):
                    self?.statusLabel.stringValue = "Transcription failed: \(error.localizedDescription)"
                    self?.statusLabel.textColor = .systemRed
                }
            }
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Recording Error"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.runModal()
    }

    private func showBlackHoleMissing() {
        let alert = NSAlert()
        alert.messageText = "BlackHole Not Installed"
        alert.informativeText = """
        System audio recording requires BlackHole, a free virtual audio driver.

        1. Download from github.com/ExistentialAudio/BlackHole/releases
        2. Install the .pkg and restart your Mac
        3. Open Audio MIDI Setup → + → Create Multi-Output Device
        4. Check both \"BlackHole 2ch\" and your speakers
        5. Right-click → \"Use This Device For Sound Output\"

        This lets you hear audio while recording it.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Download BlackHole")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "https://github.com/ExistentialAudio/BlackHole/releases")!)
        }
    }
}

// ─── Audio Device Finder ─────────────────────────────────────────────────

struct AudioDeviceFinder {
    static func findBlackHole() -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize) == noErr else { return nil }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs) == noErr else { return nil }

        for deviceID in deviceIDs {
            if let name = deviceName(deviceID), name.lowercased().contains("blackhole"), inputChannelCount(deviceID) > 0 {
                return deviceID
            }
        }
        return nil
    }

    private static func deviceName(_ deviceID: AudioDeviceID) -> String? {
        var name: CFString?
        var propertySize = UInt32(MemoryLayout<CFString?>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = withUnsafeMutablePointer(to: &name) {
            AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, $0)
        }
        return status == noErr ? name as String? : nil
    }

    private static func inputChannelCount(_ deviceID: AudioDeviceID) -> UInt32 {
        var propertySize = UInt32(MemoryLayout<UInt32>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &propertySize)
        guard status == noErr else { return 0 }

        let buffer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(propertySize))
        defer { buffer.deallocate() }
        status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, buffer)
        guard status == noErr else { return 0 }

        let buffers = UnsafeMutableAudioBufferListPointer(buffer)
        return buffers.reduce(0) { $0 + $1.mNumberChannels }
    }
}

// ─── Audio Recorder Engine ───────────────────────────────────────────────

final class AudioRecorder: NSObject {
    private var audioUnit: AudioUnit?
    private var outputFile: ExtAudioFileRef?
    private var isRecording = false
    private var fileURL: URL?
    private var numChannels: UInt32 = 2
    private var bytesPerFrame: UInt32 = 4
    private var sampleRate: Float64 = 44100
    private var silentFrames: Int64 = 0
    let maxSilentSeconds: Float64 = 20.0
    private let silenceThreshold: Float = 0.001   // Peak below this = silence (-60dB)

    let outputDirectory: URL = {
        let dir = URL(fileURLWithPath: "/Users/howardkeziah/System-Audio-Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    var onStateChange: ((Bool) -> Void)?
    var onError: ((String) -> Void)?
    var onAutoStopped: (() -> Void)?
    var currentPeakLevel: Float = 0         // Read by UI thread
    var silentSeconds: Float64 {
        Float64(silentFrames) / sampleRate
    }
    var recording: Bool { isRecording }
    var lastRecordedFileURL: URL? { fileURL }
    var customFilename: String?

    func start(deviceID: AudioDeviceID) throws {
        guard !isRecording else { return }

        // ── Create output file ──
        let filename: String
        if let custom = customFilename, !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            filename = custom + ".wav"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            filename = "SystemAudio_\(formatter.string(from: Date())).wav"
        }
        fileURL = outputDirectory.appendingPathComponent(filename)

        var fileFormat = AudioStreamBasicDescription(
            mSampleRate: 44100,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 16,
            mReserved: 0
        )

        var status = ExtAudioFileCreateWithURL(
            fileURL! as CFURL,
            kAudioFileWAVEType,
            &fileFormat,
            nil,
            AudioFileFlags.eraseFile.rawValue,
            &outputFile
        )
        guard status == noErr else { throw RecorderError.fileCreationFailed }

        // ── Create HAL AudioUnit for the specific input device ──
        var componentDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        guard let component = AudioComponentFindNext(nil, &componentDesc) else {
            if let file = outputFile { ExtAudioFileDispose(file); outputFile = nil }
            throw RecorderError.audioUnitCreationFailed
        }

        status = AudioComponentInstanceNew(component, &audioUnit)
        guard status == noErr else {
            if let file = outputFile { ExtAudioFileDispose(file); outputFile = nil }
            throw RecorderError.audioUnitCreationFailed
        }

        // Enable input, disable output
        var enable: UInt32 = 1
        var disable: UInt32 = 0
        let inputElement: AudioUnitElement = 1
        let outputElement: AudioUnitElement = 0

        AudioUnitSetProperty(audioUnit!, kAudioOutputUnitProperty_EnableIO,
                             kAudioUnitScope_Input, inputElement, &enable, UInt32(MemoryLayout<UInt32>.size))
        AudioUnitSetProperty(audioUnit!, kAudioOutputUnitProperty_EnableIO,
                             kAudioUnitScope_Output, outputElement, &disable, UInt32(MemoryLayout<UInt32>.size))

        // Set the BlackHole device
        var inputDeviceID = deviceID
        AudioUnitSetProperty(audioUnit!, kAudioOutputUnitProperty_CurrentDevice,
                             kAudioUnitScope_Global, 0, &inputDeviceID, UInt32(MemoryLayout<AudioDeviceID>.size))

        // Get and configure stream format
        var deviceFormat = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = AudioUnitGetProperty(audioUnit!, kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Input, inputElement, &deviceFormat, &formatSize)
        guard status == noErr else {
            cleanup()
            throw RecorderError.streamFormatError
        }

        var clientFormat = deviceFormat
        clientFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
        clientFormat.mBitsPerChannel = 16
        clientFormat.mBytesPerFrame = 2 * clientFormat.mChannelsPerFrame
        clientFormat.mBytesPerPacket = clientFormat.mBytesPerFrame

        numChannels = clientFormat.mChannelsPerFrame
        bytesPerFrame = clientFormat.mBytesPerFrame
        sampleRate = clientFormat.mSampleRate
        silentFrames = 0

        status = AudioUnitSetProperty(audioUnit!, kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Output, inputElement, &clientFormat, formatSize)
        guard status == noErr else {
            cleanup()
            throw RecorderError.streamFormatError
        }

        ExtAudioFileSetProperty(outputFile!, kExtAudioFileProperty_ClientDataFormat,
                                UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &clientFormat)

        // Set render callback
        var callbackStruct = AURenderCallbackStruct(
            inputProc: renderCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        AudioUnitSetProperty(audioUnit!, kAudioOutputUnitProperty_SetInputCallback,
                             kAudioUnitScope_Global, 0, &callbackStruct,
                             UInt32(MemoryLayout<AURenderCallbackStruct>.size))

        status = AudioUnitInitialize(audioUnit!)
        guard status == noErr else {
            cleanup()
            throw RecorderError.audioUnitInitFailed(status)
        }

        status = AudioOutputUnitStart(audioUnit!)
        guard status == noErr else {
            cleanup()
            throw RecorderError.audioUnitStartFailed(status)
        }

        isRecording = true
        onStateChange?(true)
        print("[SystemAudioRecorder] ● Recording → \(fileURL!.path)")
    }

    func stop() {
        guard isRecording, let au = audioUnit else { return }

        AudioOutputUnitStop(au)
        cleanup()

        isRecording = false
        onStateChange?(false)

        if let url = fileURL {
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attrs?[.size] as? Int64) ?? 0
            print("[SystemAudioRecorder] ■ Stopped — \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) → \(url.path)")
            // Reveal in Finder
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func cleanup() {
        AudioUnitUninitialize(audioUnit!)
        AudioComponentInstanceDispose(audioUnit!)
        audioUnit = nil

        if let file = outputFile {
            ExtAudioFileDispose(file)
            outputFile = nil
        }
    }

    // MARK: - Render Callback

    private let renderCallback: AURenderCallback = { (
        inRefCon,
        ioActionFlags,
        inTimeStamp,
        inBusNumber,
        inNumberFrames,
        ioData
    ) -> OSStatus in
        let recorder = Unmanaged<AudioRecorder>.fromOpaque(inRefCon).takeUnretainedValue()
        guard let file = recorder.outputFile, let au = recorder.audioUnit else { return noErr }

        let bufferByteSize = Int(inNumberFrames) * Int(recorder.bytesPerFrame)
        var audioData = [UInt8](repeating: 0, count: bufferByteSize)

        return audioData.withUnsafeMutableBytes { rawPtr -> OSStatus in
            guard let baseAddr = rawPtr.baseAddress else { return noErr }

            var buffer = AudioBuffer(
                mNumberChannels: recorder.numChannels,
                mDataByteSize: UInt32(bufferByteSize),
                mData: baseAddr
            )
            var bufferList = AudioBufferList(mNumberBuffers: 1, mBuffers: (buffer))

            var status = AudioUnitRender(au, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, &bufferList)
            guard status == noErr else { return status }

            status = ExtAudioFileWrite(file, inNumberFrames, &bufferList)

            // ── Silence detection for auto-stop ──
            let samples = rawPtr.bindMemory(to: Int16.self)
            let sampleCount = bufferByteSize / 2
            var peak: Float = 0
            for i in 0..<sampleCount {
                let f = abs(Float(samples[i]) / 32768.0)
                if f > peak { peak = f }
            }
            recorder.currentPeakLevel = peak

            if peak < recorder.silenceThreshold {
                recorder.silentFrames += Int64(inNumberFrames)
            } else {
                recorder.silentFrames = 0
            }

            return status
        }
    }
}

enum RecorderError: LocalizedError {
    case fileCreationFailed
    case audioUnitCreationFailed
    case streamFormatError
    case audioUnitInitFailed(OSStatus)
    case audioUnitStartFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .fileCreationFailed: return "Could not create output audio file. Check folder permissions."
        case .audioUnitCreationFailed: return "Could not create audio capture unit."
        case .streamFormatError: return "Could not configure audio stream format."
        case .audioUnitInitFailed(let s): return "Audio unit init failed (error \(s))."
        case .audioUnitStartFailed(let s): return "Audio unit start failed (error \(s))."
        }
    }
}

// ─── Transcriber ──────────────────────────────────────────────────────────

// DeepSeek API models for transcript formatting
private struct DSApiMessage: Codable {
    let role: String
    let content: String
}

private struct DSApiRequest: Encodable {
    let model: String
    let messages: [DSApiMessage]
    let temperature: Double
}

private struct DSApiResponse: Decodable {
    struct Choice: Decodable { let message: DSApiMessage }
    let choices: [Choice]
}

final class Transcriber {
    /// Transcribes a WAV file to markdown using whisper.cpp (local, fast, offline).
    static func transcribe(_ audioURL: URL, title: String? = nil, completion: @escaping (Result<URL, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            // Find whisper-cli binary
            let whisperBin: String
            if let brew = findBrewBinary("whisper-cli") {
                whisperBin = brew
            } else if let path = findInPath("whisper-cli") {
                whisperBin = path
            } else {
                completion(.failure(TranscriberError.whisperNotInstalled))
                return
            }

            // Find model
            let modelPath = NSHomeDirectory() + "/whisper-models/ggml-tiny.en.bin"
            guard FileManager.default.fileExists(atPath: modelPath) else {
                completion(.failure(TranscriberError.modelNotFound(modelPath)))
                return
            }

            // Output path (whisper-cli appends .txt)
            let basePath = audioURL.deletingPathExtension().path

            let process = Process()
            process.executableURL = URL(fileURLWithPath: whisperBin)
            process.arguments = [
                "-m", modelPath,
                "-f", audioURL.path,
                "-otxt",
                "-of", basePath,
                "--no-timestamps",
                "-l", "en"
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()

                guard process.terminationStatus == 0 else {
                    completion(.failure(TranscriberError.whisperFailed(process.terminationStatus)))
                    return
                }

                // Read whisper.cpp output
                let txtPath = basePath + ".txt"
                guard let transcript = try? String(contentsOfFile: txtPath, encoding: .utf8),
                      !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    completion(.failure(TranscriberError.noTranscript))
                    return
                }

                // Clean up the .txt file
                try? FileManager.default.removeItem(atPath: txtPath)

                // Format transcript for readability
                let mdURL = audioURL.deletingPathExtension().appendingPathExtension("md")
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                let timestamp = formatter.string(from: Date())
                let heading = title ?? audioURL.deletingPathExtension().lastPathComponent
                let formatted = formatTranscript(transcript.trimmingCharacters(in: .whitespacesAndNewlines))

                let md = """
                # \(heading)
                **Recorded:** \(timestamp)

                \(formatted)
                """

                try md.write(to: mdURL, atomically: true, encoding: .utf8)
                completion(.success(mdURL))

            } catch {
                completion(.failure(error))
            }
        }
    }

    /// Formats raw transcript via DeepSeek API; falls back to simple paragraph merging on failure.
    private static func formatTranscript(_ raw: String) -> String {
        // Try DeepSeek first
        if let key = loadDeepSeekKey() {
            if let formatted = formatWithDeepSeek(raw: raw, apiKey: key) {
                return formatted
            }
        }
        // Fallback: simple sentence/paragraph grouping
        return simpleFormat(raw)
    }

    private static func loadDeepSeekKey() -> String? {
        // Check environment variable first, then config file
        if let env = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"], !env.isEmpty {
            return env
        }
        let keyPath = NSHomeDirectory() + "/.deepseek_key"
        if let key = try? String(contentsOfFile: keyPath, encoding: .utf8) {
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    private static func formatWithDeepSeek(raw: String, apiKey: String) -> String? {
        let systemPrompt = """
        You are a document formatter. Your task is to reformat the following transcript into a clean, professional, highly readable Markdown document.

        ## Critical Requirements

        1. Preserve ALL original text.
           - Do not add information.
           - Do not remove information.
           - Do not summarize.
           - Do not paraphrase.
           - Do not rewrite wording.

        2. You MAY:
           - Add headings, subheadings, paragraph breaks.
           - Add bullet lists, numbered lists, blockquotes.
           - Add emphasis (bold/italic) when it improves readability.

        3. You MUST NOT:
           - Correct grammar, fix spelling, alter wording.
           - Condense or expand content.
           - Interpret content or insert commentary.

        4. Preserve all examples, quotations, URLs, names, numbers, dates, timestamps exactly.

        ## Output Format

        Return ONLY the formatted Markdown. No preamble, no explanation.
        """

        let messages = [
            DSApiMessage(role: "system", content: systemPrompt),
            DSApiMessage(role: "user", content: raw)
        ]
        let body = DSApiRequest(model: "deepseek-v4-flash", messages: messages, temperature: 0.1)

        guard let url = URL(string: "https://api.deepseek.com/chat/completions"),
              let jsonData = try? JSONEncoder().encode(body) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData
        request.timeoutInterval = 120

        let semaphore = DispatchSemaphore(value: 0)
        var result: String?

        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            guard let data = data, error == nil,
                  let httpResp = response as? HTTPURLResponse,
                  (200...299).contains(httpResp.statusCode),
                  let decoded = try? JSONDecoder().decode(DSApiResponse.self, from: data),
                  let content = decoded.choices.first?.message.content,
                  !content.isEmpty else { return }
            result = content
        }.resume()

        semaphore.wait()
        return result
    }

    /// Simple fallback formatter: merges hard-wrapped lines into flowing paragraphs.
    private static func simpleFormat(_ raw: String) -> String {
        // Join all lines with spaces, collapsing multiple spaces
        let joined = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        // Split into sentences on period/exclamation/question + space or end
        var sentences: [String] = []
        var current = ""
        for char in joined {
            current.append(char)
            if char == "." || char == "!" || char == "?" {
                sentences.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
        }
        let remainder = current.trimmingCharacters(in: .whitespaces)
        if !remainder.isEmpty {
            sentences.append(remainder)
        }

        // Group sentences into paragraphs (4-5 sentences per paragraph)
        var paragraphs: [String] = []
        var para: [String] = []
        for sentence in sentences {
            para.append(sentence)
            if para.count >= 4 {
                paragraphs.append(para.joined(separator: " "))
                para = []
            }
        }
        if !para.isEmpty {
            paragraphs.append(para.joined(separator: " "))
        }

        return paragraphs.joined(separator: "\n\n")
    }

    private static func findBrewBinary(_ name: String) -> String? {
        let brewPrefixes = ["/opt/homebrew/bin", "/usr/local/bin"]
        for prefix in brewPrefixes {
            let path = prefix + "/" + name
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    private static func findInPath(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let path = path, !path.isEmpty, process.terminationStatus == 0 {
                return path
            }
        } catch {}
        return nil
    }
}

enum TranscriberError: LocalizedError {
    case whisperNotInstalled
    case modelNotFound(String)
    case whisperFailed(Int32)
    case noTranscript

    var errorDescription: String? {
        switch self {
        case .whisperNotInstalled:
            return "whisper-cli not found. Install: brew install whisper-cli"
        case .modelNotFound(let path):
            return "Whisper model not found at \(path). Download: curl -L -o \(path) https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin"
        case .whisperFailed(let code):
            return "whisper-cli exited with code \(code)"
        case .noTranscript:
            return "No speech detected in recording"
        }
    }
}

// ─── App Delegate ────────────────────────────────────────────────────────

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWC: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        mainWC = MainWindowController()
        mainWC?.showWindow(nil)
        mainWC?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Check for BlackHole on launch
        if AudioDeviceFinder.findBlackHole() == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.mainWC?.window?.makeKeyAndOrderFront(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

// ─── Entry Point ─────────────────────────────────────────────────────────

let app = NSApplication.shared
app.setActivationPolicy(.regular) // Show in Dock
let delegate = AppDelegate()
app.delegate = delegate
app.run()
