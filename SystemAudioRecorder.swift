import Cocoa
import AVFoundation
import CoreAudio
import AudioToolbox

// ─── Status Bar Controller ───────────────────────────────────────────────

final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var startItem: NSMenuItem!
    private var stopItem: NSMenuItem!
    private var settingsItem: NSMenuItem!

    weak var delegate: AppDelegate?

    func setup(delegate: AppDelegate) {
        self.delegate = delegate

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon(recording: false)

        menu = NSMenu()

        startItem = NSMenuItem(title: "Start Recording", action: #selector(startAction), keyEquivalent: "")
        startItem.target = self
        menu.addItem(startItem)

        stopItem = NSMenuItem(title: "Stop Recording", action: #selector(stopAction), keyEquivalent: "")
        stopItem.target = self
        stopItem.isEnabled = false
        menu.addItem(stopItem)

        menu.addItem(.separator())

        settingsItem = NSMenuItem(title: "Settings…", action: #selector(settingsAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitAction), keyEquivalent: "q", target: self))

        statusItem.menu = menu
    }

    func updateIcon(recording: Bool) {
        if let button = statusItem.button {
            if recording {
                button.attributedTitle = NSAttributedString(
                    string: "●",
                    attributes: [
                        .font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .bold),
                        .foregroundColor: NSColor.systemRed,
                        .baselineOffset: -1
                    ]
                )
            } else {
                button.attributedTitle = NSAttributedString(
                    string: "◎",
                    attributes: [
                        .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
                        .baselineOffset: -1
                    ]
                )
            }
        }
    }

    func setRecordingState(_ recording: Bool) {
        startItem.isEnabled = !recording
        stopItem.isEnabled = recording
        updateIcon(recording: recording)
    }

    @objc private func startAction() { delegate?.startRecording() }
    @objc private func stopAction()  { delegate?.stopRecording() }
    @objc private func settingsAction() { delegate?.showSettings() }
    @objc private func quitAction()  { NSApplication.shared.terminate(nil) }
}

// ─── Audio Device Finder ─────────────────────────────────────────────────

struct AudioDeviceFinder {
    /// Returns the AudioDeviceID for the BlackHole device, or nil if not found.
    static func findBlackHole() -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize
        )
        guard status == noErr else { return nil }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize, &deviceIDs
        )
        guard status == noErr else { return nil }

        for deviceID in deviceIDs {
            if let name = deviceName(deviceID), name.lowercased().contains("blackhole") {
                // Verify it has input channels
                if inputChannelCount(deviceID) > 0 {
                    return deviceID
                }
            }
        }
        return nil
    }

    /// Returns a list of all available input device names + IDs
    static func listInputDevices() -> [(id: AudioDeviceID, name: String)] {
        var results: [(AudioDeviceID, String)] = []
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize) == noErr else { return results }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs) == noErr else { return results }

        for deviceID in deviceIDs {
            if let name = deviceName(deviceID), inputChannelCount(deviceID) > 0 {
                results.append((deviceID, name))
            }
        }
        return results
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

// ─── Audio Recorder ──────────────────────────────────────────────────────

final class AudioRecorder: NSObject {
    private var audioUnit: AudioUnit?
    private var outputFile: ExtAudioFileRef?
    private var isRecording = false
    private var fileURL: URL?
    private var outputDir: URL
    private var numChannels: UInt32 = 2
    private var bytesPerFrame: UInt32 = 4

    override init() {
        outputDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent("SystemAudio")
        super.init()
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    }

    var onStateChange: ((Bool) -> Void)?
    var onError: ((String) -> Void)?

    func start(deviceID: AudioDeviceID) throws {
        guard !isRecording else { return }

        // ── Create output file ──
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "SystemAudio_\(formatter.string(from: Date())).wav"
        fileURL = outputDir.appendingPathComponent(filename)

        var audioStreamDesc = AudioStreamBasicDescription(
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
            &audioStreamDesc,
            nil,
            AudioFileFlags.eraseFile.rawValue,
            &outputFile
        )
        guard status == noErr else {
            throw RecorderError.fileCreationFailed
        }

        // ── Create HAL AudioUnit ──
        var componentDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        guard let component = AudioComponentFindNext(nil, &componentDesc) else {
            throw RecorderError.audioUnitCreationFailed
        }

        status = AudioComponentInstanceNew(component, &audioUnit)
        guard status == noErr else {
            throw RecorderError.audioUnitCreationFailed
        }

        // Enable input, disable output
        var enable: UInt32 = 1
        var disable: UInt32 = 0
        let elementInput: AudioUnitElement = 1
        let elementOutput: AudioUnitElement = 0

        AudioUnitSetProperty(audioUnit!, kAudioOutputUnitProperty_EnableIO,
                             kAudioUnitScope_Input, elementInput, &enable, UInt32(MemoryLayout<UInt32>.size))
        AudioUnitSetProperty(audioUnit!, kAudioOutputUnitProperty_EnableIO,
                             kAudioUnitScope_Output, elementOutput, &disable, UInt32(MemoryLayout<UInt32>.size))

        // Set the input device
        var inputDeviceID = deviceID
        AudioUnitSetProperty(audioUnit!, kAudioOutputUnitProperty_CurrentDevice,
                             kAudioUnitScope_Global, 0, &inputDeviceID, UInt32(MemoryLayout<AudioDeviceID>.size))

        // Get device's actual stream format
        var deviceFormat = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = AudioUnitGetProperty(audioUnit!, kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Input, elementInput, &deviceFormat, &formatSize)
        guard status == noErr else {
            throw RecorderError.streamFormatError
        }

        // Set client format (what we want the callbacks to deliver — 16-bit int is easier)
        var clientFormat = deviceFormat
        clientFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
        clientFormat.mBitsPerChannel = 16
        clientFormat.mBytesPerFrame = 2 * clientFormat.mChannelsPerFrame
        clientFormat.mBytesPerPacket = clientFormat.mBytesPerFrame

        // Store for use in the render callback
        numChannels = clientFormat.mChannelsPerFrame
        bytesPerFrame = clientFormat.mBytesPerFrame

        status = AudioUnitSetProperty(audioUnit!, kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Output, elementInput, &clientFormat, formatSize)
        guard status == noErr else {
            throw RecorderError.streamFormatError
        }

        // Set the client format on the ExtAudioFile too
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

        // Initialize and start
        status = AudioUnitInitialize(audioUnit!)
        guard status == noErr else {
            throw RecorderError.audioUnitInitFailed(status)
        }

        status = AudioOutputUnitStart(audioUnit!)
        guard status == noErr else {
            throw RecorderError.audioUnitStartFailed(status)
        }

        isRecording = true
        onStateChange?(true)

        print("[SystemAudioRecorder] Recording started → \(fileURL?.path ?? "unknown")")
    }

    func stop() {
        guard isRecording, let au = audioUnit else { return }

        AudioOutputUnitStop(au)
        AudioUnitUninitialize(au)
        AudioComponentInstanceDispose(au)
        audioUnit = nil

        if let file = outputFile {
            ExtAudioFileDispose(file)
            outputFile = nil
        }

        isRecording = false
        onStateChange?(false)

        if let url = fileURL {
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attrs?[.size] as? Int64) ?? 0
            print("[SystemAudioRecorder] Recording stopped — \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) → \(url.path)")
            // Reveal in Finder
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    func setOutputDirectory(_ url: URL) {
        outputDir = url
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    }

    var recording: Bool { isRecording }

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

        // Allocate buffer for audio data using the actual byte size
        let bufferByteSize = Int(inNumberFrames) * Int(recorder.bytesPerFrame)
        var audioData = [UInt8](repeating: 0, count: bufferByteSize)

        var buffer = AudioBuffer(
            mNumberChannels: recorder.numChannels,
            mDataByteSize: UInt32(bufferByteSize),
            mData: &audioData
        )
        var bufferList = AudioBufferList(mNumberBuffers: 1, mBuffers: (buffer))

        var status = AudioUnitRender(au, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, &bufferList)
        guard status == noErr else {
            print("[SystemAudioRecorder] AudioUnitRender error: \(status)")
            return status
        }

        // Synchronous write — avoids use-after-free of the stack buffer
        status = ExtAudioFileWrite(file, inNumberFrames, &bufferList)
        if status != noErr {
            print("[SystemAudioRecorder] ExtAudioFileWrite error: \(status)")
        }
        return noErr
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
        case .fileCreationFailed:
            return "Could not create output audio file."
        case .audioUnitCreationFailed:
            return "Could not create audio capture unit."
        case .streamFormatError:
            return "Could not configure audio stream format."
        case .audioUnitInitFailed(let s):
            return "Audio unit initialization failed (error \(s))."
        case .audioUnitStartFailed(let s):
            return "Audio unit start failed (error \(s))."
        }
    }
}

// ─── Settings Window ─────────────────────────────────────────────────────

final class SettingsWindowController: NSWindowController {
    private var directoryLabel: NSTextField!
    var outputDirectory: URL {
        didSet {
            directoryLabel?.stringValue = outputDirectory.path
        }
    }
    var onDirectoryChange: ((URL) -> Void)?

    init(directory: URL) {
        self.outputDirectory = directory
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "System Audio Recorder Settings"
        window.center()
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let titleLabel = NSTextField(labelWithString: "Output Folder")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 12)
        titleLabel.frame = NSRect(x: 20, y: 150, width: 100, height: 16)
        contentView.addSubview(titleLabel)

        directoryLabel = NSTextField(labelWithString: outputDirectory.path)
        directoryLabel.frame = NSRect(x: 20, y: 120, width: 340, height: 20)
        directoryLabel.lineBreakMode = .byTruncatingMiddle
        contentView.addSubview(directoryLabel)

        let chooseBtn = NSButton(title: "Choose…", target: self, action: #selector(chooseFolder))
        chooseBtn.frame = NSRect(x: 370, y: 117, width: 80, height: 24)
        chooseBtn.bezelStyle = .rounded
        contentView.addSubview(chooseBtn)

        let noteLabel = NSTextField(labelWithString: """
        To record system audio, install BlackHole (free, open-source):
        https://github.com/ExistentialAudio/BlackHole

        Then set up a Multi-Output Device in Audio MIDI Setup:
        Open Audio MIDI Setup → '+' → Create Multi-Output Device →
        check both BlackHole and your speakers.

        Set the Multi-Output Device as your system output to hear audio
        while recording.
        """)
        noteLabel.frame = NSRect(x: 20, y: 10, width: 420, height: 95)
        noteLabel.font = NSFont.systemFont(ofSize: 10)
        noteLabel.textColor = .secondaryLabelColor
        noteLabel.maximumNumberOfLines = 0
        contentView.addSubview(noteLabel)
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Select Output Folder"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self = self else { return }
            self.outputDirectory = url
            self.onDirectoryChange?(url)
        }
    }
}

// ─── App Delegate ────────────────────────────────────────────────────────

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusBar = StatusBarController()
    private let recorder = AudioRecorder()
    private var settingsWC: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar.setup(delegate: self)
        recorder.onStateChange = { [weak self] recording in
            DispatchQueue.main.async {
                self?.statusBar.setRecordingState(recording)
            }
        }
        recorder.onError = { [weak self] msg in
            DispatchQueue.main.async {
                self?.showAlert(message: msg)
            }
        }

        // Check for BlackHole at launch
        if AudioDeviceFinder.findBlackHole() == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showBlackHoleMissing()
            }
        }
    }

    func startRecording() {
        guard let deviceID = AudioDeviceFinder.findBlackHole() else {
            showBlackHoleMissing()
            return
        }
        do {
            try recorder.start(deviceID: deviceID)
        } catch {
            showAlert(message: error.localizedDescription)
        }
    }

    func stopRecording() {
        recorder.stop()
    }

    func showSettings() {
        if settingsWC == nil {
            settingsWC = SettingsWindowController(directory: recorder.outputDirectory)
            settingsWC?.onDirectoryChange = { [weak self] url in
                self?.recorder.setOutputDirectory(url)
            }
        }
        settingsWC?.outputDirectory = recorder.outputDirectory
        settingsWC?.showWindow(nil)
        settingsWC?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showBlackHoleMissing() {
        let alert = NSAlert()
        alert.messageText = "BlackHole Not Found"
        alert.informativeText = """
        System audio recording requires BlackHole, a free open-source virtual audio driver.

        1. Download BlackHole from github.com/ExistentialAudio/BlackHole
        2. Install it (requires restarting your Mac)
        3. Open Audio MIDI Setup → '+' → Create Multi-Output Device
        4. Check both BlackHole and your speakers
        5. Set the Multi-Output Device as your system output

        Without this, only your microphone can be recorded.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open BlackHole Download Page")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "https://github.com/ExistentialAudio/BlackHole/releases")!)
        }
    }

    private func showAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.runModal()
    }
}

// ─── Entry Point ─────────────────────────────────────────────────────────

let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // No dock icon — menu bar only
let delegate = AppDelegate()
app.delegate = delegate
app.run()
