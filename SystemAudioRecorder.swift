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

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 280),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "System Audio Recorder"
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
        let titleLabel = NSTextField(labelWithString: "System Audio Recorder")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 18)
        titleLabel.alignment = .center
        titleLabel.frame = NSRect(x: 20, y: 230, width: 380, height: 24)
        contentView.addSubview(titleLabel)

        // ── Status indicator ──
        statusLabel = NSTextField(labelWithString: "Ready")
        statusLabel.font = NSFont.systemFont(ofSize: 13)
        statusLabel.alignment = .center
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.frame = NSRect(x: 20, y: 205, width: 380, height: 18)
        contentView.addSubview(statusLabel)

        // ── Record Button ──
        recordButton = NSButton(title: "Start Recording", target: self, action: #selector(toggleRecording))
        recordButton.frame = NSRect(x: 110, y: 135, width: 200, height: 52)
        recordButton.bezelStyle = .rounded
        recordButton.font = NSFont.boldSystemFont(ofSize: 15)
        recordButton.keyEquivalent = "\r" // Enter key toggles
        contentView.addSubview(recordButton)

        // ── Duration ──
        durationLabel = NSTextField(labelWithString: "")
        durationLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 20, weight: .medium)
        durationLabel.alignment = .center
        durationLabel.frame = NSRect(x: 20, y: 100, width: 380, height: 26)
        durationLabel.isHidden = true
        contentView.addSubview(durationLabel)

        // ── Output folder ──
        let folderLabel = NSTextField(labelWithString: "Saves to: /Users/howardkeziah/System-Audio-Recordings/")
        folderLabel.font = NSFont.systemFont(ofSize: 10)
        folderLabel.textColor = .tertiaryLabelColor
        folderLabel.alignment = .center
        folderLabel.frame = NSRect(x: 20, y: 70, width: 380, height: 16)
        contentView.addSubview(folderLabel)

        // ── Show in Finder ──
        let finderBtn = NSButton(title: "Show Recordings in Finder", target: self, action: #selector(showInFinder))
        finderBtn.frame = NSRect(x: 130, y: 35, width: 160, height: 24)
        finderBtn.bezelStyle = .rounded
        finderBtn.font = NSFont.systemFont(ofSize: 11)
        contentView.addSubview(finderBtn)

        // ── Requirement note ──
        let noteLabel = NSTextField(labelWithString: "Requires BlackHole. Download: github.com/ExistentialAudio/BlackHole")
        noteLabel.font = NSFont.systemFont(ofSize: 9)
        noteLabel.textColor = .quaternaryLabelColor
        noteLabel.alignment = .center
        noteLabel.frame = NSRect(x: 20, y: 8, width: 380, height: 14)
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
            recordingStartTime = Date()
            startDurationTimer()
        } else {
            recordButton.title = "●  Start Recording"
            recordButton.contentTintColor = nil
            statusLabel.stringValue = "Ready"
            statusLabel.textColor = .secondaryLabelColor
            durationLabel.isHidden = true
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
        }
    }

    @objc private func toggleRecording() {
        if recorder.recording {
            recorder.stop()
        } else {
            guard let deviceID = AudioDeviceFinder.findBlackHole() else {
                showBlackHoleMissing()
                return
            }
            do {
                try recorder.start(deviceID: deviceID)
            } catch {
                showError(error.localizedDescription)
            }
        }
    }

    @objc private func showInFinder() {
        NSWorkspace.shared.open(recorder.outputDirectory)
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
        var count: UInt32 = 0
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

    let outputDirectory: URL = {
        let dir = URL(fileURLWithPath: "/Users/howardkeziah/System-Audio-Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    var onStateChange: ((Bool) -> Void)?
    var onError: ((String) -> Void)?
    var recording: Bool { isRecording }

    func start(deviceID: AudioDeviceID) throws {
        guard !isRecording else { return }

        // ── Create output file ──
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "SystemAudio_\(formatter.string(from: Date())).wav"
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

        var buffer = AudioBuffer(
            mNumberChannels: recorder.numChannels,
            mDataByteSize: UInt32(bufferByteSize),
            mData: &audioData
        )
        var bufferList = AudioBufferList(mNumberBuffers: 1, mBuffers: (buffer))

        var status = AudioUnitRender(au, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, &bufferList)
        guard status == noErr else { return status }

        status = ExtAudioFileWrite(file, inNumberFrames, &bufferList)
        return status
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
