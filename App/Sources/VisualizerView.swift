import AppKit
import OpenGL.GL3
import CProjectM

final class VisualizerView: NSOpenGLView {
    private var projectM: projectm_handle?
    private var playlist: projectm_playlist_handle?
    private var displayLink: CADisplayLink?
    private let audioEngine: AudioTapEngine
    private var drainBuffer: [Float] = []

    private static let silenceThreshold: Float = 0.001
    private static let silenceTimeout: CFTimeInterval = 5
    private var lastAudibleTime = CACurrentMediaTime()
    private var isSleeping = false { didSet { updatePauseState() } }
    private var isOccluded = false { didSet { updatePauseState() } }
    private var wakeTimer: Timer?

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
        wantsBestResolutionOpenGLSurface = true
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

        if let playlist = projectm_playlist_create(handle) {
            self.playlist = playlist
            let presets = (Bundle.main.urls(forResourcesWithExtension: "milk", subdirectory: nil) ?? [])
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for preset in presets {
                projectm_playlist_add_preset(playlist, preset.path, false)
            }
            projectm_playlist_set_position(playlist, 0, true)
        }

        let link = displayLink(target: self, selector: #selector(renderFrame))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
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
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        wakeTimer?.invalidate()
        displayLink?.invalidate()
        if let handle = projectM {
            projectm_destroy(handle)
        }
        if let playlist {
            projectm_playlist_destroy(playlist)
        }
    }
}
