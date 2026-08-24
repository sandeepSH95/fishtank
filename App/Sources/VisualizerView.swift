import AppKit
import OpenGL.GL3
import CProjectM

final class VisualizerView: NSOpenGLView {
    static let presetsFolder = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Fishtank/Presets", isDirectory: true)

    static let defaultPreset = "Aderrasi - Chromatic Abyss (Refined Abyss Mix).milk"

    private var projectM: projectm_handle?
    private var playlist: projectm_playlist_handle?
    private var displayLink: CADisplayLink?
    private let audioEngine: AudioTapEngine
    private var drainBuffer: [Float] = []
    private var overlay: PresetOverlay?

    private static let silenceThreshold: Float = 0.001
    private static let silenceTimeout: CFTimeInterval = 5
    private var lastAudibleTime = CACurrentMediaTime()
    private var isSleeping = false { didSet { updatePauseState() } }
    private var isOccluded = false { didSet { updatePauseState() } }
    private var wakeTimer: Timer?
    private var hintTimer: Timer?
    private var hasHeardAudio = false
    private var hintVisible = false

    init(frame: NSRect, audioEngine: AudioTapEngine) {
        self.audioEngine = audioEngine
        let attributes: [NSOpenGLPixelFormatAttribute] = [
            NSOpenGLPixelFormatAttribute(NSOpenGLPFAOpenGLProfile),
            NSOpenGLPixelFormatAttribute(NSOpenGLProfileVersion4_1Core),
            NSOpenGLPixelFormatAttribute(NSOpenGLPFADoubleBuffer),
            NSOpenGLPixelFormatAttribute(NSOpenGLPFAColorSize), 24,
            NSOpenGLPixelFormatAttribute(NSOpenGLPFADepthSize), 24,
            NSOpenGLPixelFormatAttribute(NSOpenGLPFAAccelerated),
            0,
        ]
        super.init(frame: frame, pixelFormat: NSOpenGLPixelFormat(attributes: attributes)!)!
        wantsBestResolutionOpenGLSurface = false
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func prepareOpenGL() {
        super.prepareOpenGL()
        guard let context = openGLContext else { return }
        context.makeCurrentContext()
        var swapInterval: GLint = 1
        context.setValues(&swapInterval, for: .swapInterval)

        guard let handle = projectm_create() else {
            NSLog("projectm_create failed")
            return
        }
        projectM = handle

        let backingSize = convertToBacking(bounds).size
        projectm_set_window_size(handle, Int(backingSize.width), Int(backingSize.height))
        projectm_set_fps(handle, 30)
        projectm_set_mesh_size(handle, 48, 32)
        projectm_set_aspect_correction(handle, true)
        projectm_set_preset_duration(handle, 60)
        drainBuffer = [Float](repeating: 0, count: Int(projectm_pcm_get_max_samples()) * 2)

        if let textures = Bundle.main.resourceURL?.appendingPathComponent("Textures") {
            textures.path.withCString { cString in
                var paths: UnsafePointer<CChar>? = cString
                projectm_set_texture_search_paths(handle, &paths, 1)
            }
        }

        if let playlist = projectm_playlist_create(handle) {
            self.playlist = playlist
            projectm_playlist_set_retry_count(playlist, 5)
            if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Presets") {
                let count = projectm_playlist_add_path(playlist, bundled.path, true, false)
                NSLog("loaded %u bundled presets", count)
            }
            try? FileManager.default.createDirectory(at: Self.presetsFolder, withIntermediateDirectories: true)
            projectm_playlist_add_path(playlist, Self.presetsFolder.path, true, false)

            projectm_playlist_set_preset_switched_event_callback(
                playlist, presetSwitchedCallback, Unmanaged.passUnretained(self).toOpaque()
            )
            projectm_playlist_set_preset_switch_failed_event_callback(
                playlist, presetSwitchFailedCallback, nil
            )

            projectm_playlist_set_shuffle(playlist, UserDefaults.standard.bool(forKey: "shufflePresets"))
            let startPreset = UserDefaults.standard.string(forKey: "currentPreset") ?? Self.defaultPreset
            projectm_playlist_set_position(playlist, position(of: startPreset) ?? 0, true)
            projectm_set_preset_locked(handle, UserDefaults.standard.bool(forKey: "lockPreset"))
        }

        let link = displayLink(target: self, selector: #selector(renderFrame))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        displayLink = link

        hintTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            guard let self, !self.hasHeardAudio else { return }
            self.hintVisible = true
            self.overlay?.showPersistent("Waiting for audio…")
        }
    }

    override var mouseDownCanMoveWindow: Bool { true }

    weak var contextMenu: NSMenu?

    override func rightMouseDown(with event: NSEvent) {
        guard let contextMenu else { return }
        NSMenu.popUpContextMenu(contextMenu, with: event, for: self)
    }

    private static let cornerHitSize: CGFloat = 14

    private enum Corner {
        case bottomLeft, bottomRight, topLeft, topRight
    }

    private func corner(at point: NSPoint) -> Corner? {
        let s = Self.cornerHitSize
        let left = point.x < s
        let right = point.x > bounds.maxX - s
        let bottom = point.y < s
        let top = point.y > bounds.maxY - s
        if left && bottom { return .bottomLeft }
        if right && bottom { return .bottomRight }
        if left && top { return .topLeft }
        if right && top { return .topRight }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let corner = corner(at: point) {
            resize(from: corner)
        } else {
            window?.performDrag(with: event)
        }
    }

    private func resize(from corner: Corner) {
        guard let window else { return }
        let start = window.frame
        let anchor: NSPoint
        let grabbedCorner: NSPoint
        switch corner {
        case .bottomLeft:
            anchor = NSPoint(x: start.maxX, y: start.maxY)
            grabbedCorner = NSPoint(x: start.minX, y: start.minY)
        case .bottomRight:
            anchor = NSPoint(x: start.minX, y: start.maxY)
            grabbedCorner = NSPoint(x: start.maxX, y: start.minY)
        case .topLeft:
            anchor = NSPoint(x: start.maxX, y: start.minY)
            grabbedCorner = NSPoint(x: start.minX, y: start.maxY)
        case .topRight:
            anchor = NSPoint(x: start.minX, y: start.minY)
            grabbedCorner = NSPoint(x: start.maxX, y: start.maxY)
        }
        let startMouse = NSEvent.mouseLocation
        let grabOffset = NSPoint(x: grabbedCorner.x - startMouse.x, y: grabbedCorner.y - startMouse.y)
        while true {
            guard let event = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]),
                  event.type == .leftMouseDragged else { break }
            let mouse = NSEvent.mouseLocation
            var target = NSPoint(x: mouse.x + grabOffset.x, y: mouse.y + grabOffset.y)
            if let limit = window.screen?.visibleFrame {
                target.x = min(max(target.x, limit.minX), limit.maxX)
                target.y = min(max(target.y, limit.minY), limit.maxY)
            }
            let width = max(window.minSize.width, abs(target.x - anchor.x))
            let height = max(window.minSize.height, abs(target.y - anchor.y))
            var frame = NSRect(x: anchor.x, y: anchor.y, width: width, height: height)
            if target.x < anchor.x { frame.origin.x = anchor.x - width }
            if target.y < anchor.y { frame.origin.y = anchor.y - height }
            window.setFrame(frame, display: true)
            renderFrame()
        }
    }

    override func resetCursorRects() {
        let s = Self.cornerHitSize
        let corners: [(NSRect, Corner)] = [
            (NSRect(x: 0, y: 0, width: s, height: s), .bottomLeft),
            (NSRect(x: bounds.maxX - s, y: 0, width: s, height: s), .bottomRight),
            (NSRect(x: 0, y: bounds.maxY - s, width: s, height: s), .topLeft),
            (NSRect(x: bounds.maxX - s, y: bounds.maxY - s, width: s, height: s), .topRight),
        ]
        for (rect, corner) in corners {
            addCursorRect(rect, cursor: resizeCursor(for: corner))
        }
    }

    private func resizeCursor(for corner: Corner) -> NSCursor {
        guard #available(macOS 15.0, *) else { return .crosshair }
        switch corner {
        case .bottomLeft: return .frameResize(position: .bottomLeft, directions: .all)
        case .bottomRight: return .frameResize(position: .bottomRight, directions: .all)
        case .topLeft: return .frameResize(position: .topLeft, directions: .all)
        case .topRight: return .frameResize(position: .topRight, directions: .all)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        if let window {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(occlusionChanged),
                name: NSWindow.didChangeOcclusionStateNotification,
                object: window
            )
            if overlay == nil {
                overlay = PresetOverlay(parent: window)
            }
        }
    }

    override func reshape() {
        super.reshape()
        guard let handle = projectM, let context = openGLContext else { return }
        context.makeCurrentContext()
        let backingSize = convertToBacking(bounds).size
        projectm_set_window_size(handle, Int(backingSize.width), Int(backingSize.height))
    }

    func playNextPreset() {
        guard let playlist else { return }
        projectm_playlist_play_next(playlist, true)
    }

    func playPreviousPreset() {
        guard let playlist else { return }
        projectm_playlist_play_previous(playlist, true)
    }

    func setShuffle(_ enabled: Bool) {
        guard let playlist else { return }
        projectm_playlist_set_shuffle(playlist, enabled)
    }

    func setPresetLocked(_ locked: Bool) {
        guard let handle = projectM else { return }
        projectm_set_preset_locked(handle, locked)
    }

    func allPresets() -> [PresetItem] {
        guard let playlist else { return [] }
        let bundledRoot = Bundle.main.resourceURL?.appendingPathComponent("Presets").path ?? ""
        let size = projectm_playlist_size(playlist)
        var items: [PresetItem] = []
        items.reserveCapacity(Int(size))
        for index in 0..<size {
            guard let name = projectm_playlist_item(playlist, index) else { continue }
            let path = String(cString: name)
            projectm_playlist_free_string(name)
            let parsed = PresetItem.parse(filename: path)
            let category: String
            if path.hasPrefix(bundledRoot) {
                let relative = path.dropFirst(bundledRoot.count + 1)
                category = relative.contains("/") ? String(relative.prefix(while: { $0 != "/" })) : "Other"
            } else {
                category = "Your Presets"
            }
            items.append(PresetItem(
                id: index,
                title: parsed.title,
                author: parsed.author,
                category: category,
                filename: URL(fileURLWithPath: path).lastPathComponent
            ))
        }
        return items
    }

    private func position(of filename: String) -> UInt32? {
        guard let playlist else { return nil }
        for index in 0..<projectm_playlist_size(playlist) {
            guard let item = projectm_playlist_item(playlist, index) else { continue }
            let path = String(cString: item)
            projectm_playlist_free_string(item)
            if path.hasSuffix("/" + filename) { return index }
        }
        return nil
    }

    func selectPreset(at index: UInt32) {
        guard let playlist else { return }
        projectm_playlist_set_position(playlist, index, true)
    }

    fileprivate func presetDidSwitch(to index: UInt32) {
        guard let playlist, let name = projectm_playlist_item(playlist, index) else { return }
        let filename = String(cString: name)
        projectm_playlist_free_string(name)

        UserDefaults.standard.set(
            URL(fileURLWithPath: filename).lastPathComponent, forKey: "currentPreset"
        )

        let parsed = PresetItem.parse(filename: filename)
        if let author = parsed.author {
            overlay?.show("\(parsed.title) · \(author)")
        } else {
            overlay?.show(parsed.title)
        }
    }

    @objc private func occlusionChanged() {
        isOccluded = !(window?.occlusionState.contains(.visible) ?? true)
    }

    private func updatePauseState() {
        displayLink?.isPaused = isOccluded || isSleeping
    }

    @objc private func renderFrame() {
        guard let handle = projectM, let context = openGLContext else { return }
        context.makeCurrentContext()

        var peak: Float = 0
        while true {
            let samplesRead = drainBuffer.withUnsafeMutableBufferPointer { pointer in
                audioEngine.read(into: pointer.baseAddress!, maxSamples: pointer.count)
            }
            guard samplesRead >= 2 else { break }
            for i in 0..<samplesRead where abs(drainBuffer[i]) > peak {
                peak = abs(drainBuffer[i])
            }
            projectm_pcm_add_float(handle, drainBuffer, UInt32(samplesRead / 2), PROJECTM_STEREO)
            if samplesRead < drainBuffer.count { break }
        }

        let now = CACurrentMediaTime()
        if peak > Self.silenceThreshold {
            lastAudibleTime = now
            noteAudioHeard()
        } else if now - lastAudibleTime > Self.silenceTimeout {
            sleepUntilAudible()
            return
        }

        glClearColor(0, 0, 0, 1)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT))
        projectm_opengl_render_frame(handle)
        context.flushBuffer()
    }

    private func sleepUntilAudible() {
        isSleeping = true
        wakeTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.checkForWake()
        }
    }

    private func checkForWake() {
        var peak: Float = 0
        while true {
            let samplesRead = drainBuffer.withUnsafeMutableBufferPointer { pointer in
                audioEngine.read(into: pointer.baseAddress!, maxSamples: pointer.count)
            }
            guard samplesRead > 0 else { break }
            for i in 0..<samplesRead where abs(drainBuffer[i]) > peak {
                peak = abs(drainBuffer[i])
            }
            if samplesRead < drainBuffer.count { break }
        }
        if peak > Self.silenceThreshold {
            wakeTimer?.invalidate()
            wakeTimer = nil
            lastAudibleTime = CACurrentMediaTime()
            isSleeping = false
            noteAudioHeard()
        }
    }

    private func noteAudioHeard() {
        guard !hasHeardAudio else { return }
        hasHeardAudio = true
        hintTimer?.invalidate()
        hintTimer = nil
        if hintVisible {
            hintVisible = false
            overlay?.hide()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        wakeTimer?.invalidate()
        hintTimer?.invalidate()
        displayLink?.invalidate()
        if let playlist {
            projectm_playlist_set_preset_switched_event_callback(playlist, nil, nil)
            projectm_playlist_set_preset_switch_failed_event_callback(playlist, nil, nil)
        }
        if let handle = projectM {
            projectm_destroy(handle)
        }
        if let playlist {
            projectm_playlist_destroy(playlist)
        }
    }
}

private let presetSwitchFailedCallback: projectm_playlist_preset_switch_failed_event = { filename, message, _ in
    let name = filename.map { String(cString: $0) } ?? "?"
    let reason = message.map { String(cString: $0) } ?? ""
    NSLog("preset failed to load: %@ (%@)", name, reason)
}

private let presetSwitchedCallback: projectm_playlist_preset_switched_event = { _, index, userData in
    guard let userData else { return }
    let view = Unmanaged<VisualizerView>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async {
        view.presetDidSwitch(to: index)
    }
}
