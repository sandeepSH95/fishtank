import AppKit
import OpenGL.GL3
import CProjectM

final class VisualizerView: NSOpenGLView {
    private var projectM: projectm_handle?
    private var displayLink: CADisplayLink?
    private let audioEngine: AudioTapEngine
    private var drainBuffer: [Float] = []

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
        projectm_set_preset_locked(handle, true)
        drainBuffer = [Float](repeating: 0, count: Int(projectm_pcm_get_max_samples()) * 2)

        if let preset = Bundle.main.url(forResource: "211-wave", withExtension: "milk") {
            projectm_load_preset_file(handle, preset.path, false)
        }

        let link = displayLink(target: self, selector: #selector(renderFrame))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    override func reshape() {
        super.reshape()
        guard let handle = projectM, let context = openGLContext else { return }
        context.makeCurrentContext()
        let backingSize = convertToBacking(bounds).size
        projectm_set_window_size(handle, Int(backingSize.width), Int(backingSize.height))
    }

    @objc private func renderFrame() {
        guard let handle = projectM, let context = openGLContext else { return }
        context.makeCurrentContext()
        while true {
            let samplesRead = drainBuffer.withUnsafeMutableBufferPointer { pointer in
                audioEngine.read(into: pointer.baseAddress!, maxSamples: pointer.count)
            }
            guard samplesRead >= 2 else { break }
            projectm_pcm_add_float(handle, drainBuffer, UInt32(samplesRead / 2), PROJECTM_STEREO)
            if samplesRead < drainBuffer.count { break }
        }
        glClearColor(0, 0, 0, 1)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT))
        projectm_opengl_render_frame(handle)
        context.flushBuffer()
    }

    deinit {
        displayLink?.invalidate()
        if let handle = projectM {
            projectm_destroy(handle)
        }
    }
}
