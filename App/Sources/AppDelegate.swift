import AppKit
import SwiftUI
import CProjectM

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var window: FloatingWindow?
    private var visualizerView: VisualizerView?
    private let audioEngine = AudioTapEngine()

    private var shuffleItem: NSMenuItem?
    private var lockItem: NSMenuItem?
    private var softEdgesItem: NSMenuItem?
    private var windowOpacitySlider: NSSlider?
    private var backgroundOpacitySlider: NSSlider?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            "shufflePresets": true,
            "lockPreset": true,
            "windowOpacity": 1.0,
            "backgroundOpacity": 1.0,
            "softEdges": false,
        ])

        var major: Int32 = 0
        var minor: Int32 = 0
        var patch: Int32 = 0
        projectm_get_version_components(&major, &minor, &patch)
        NSLog("libprojectM %d.%d.%d", major, minor, patch)

        do {
            try audioEngine.start()
            NSLog("audio tap running at %.0f Hz, %d channels", audioEngine.sampleRate, audioEngine.channelCount)
        } catch {
            NSLog("audio capture unavailable: \(error)")
        }

        let defaults = UserDefaults.standard
        let window = FloatingWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300))
        let view = VisualizerView(
            frame: window.contentLayoutRect,
            audioEngine: audioEngine,
            shuffle: defaults.bool(forKey: "shufflePresets"),
            lockPreset: defaults.bool(forKey: "lockPreset"),
            startPreset: defaults.string(forKey: "currentPreset") ?? VisualizerView.defaultPreset
        )
        view.onPresetSwitched = { filename in
            UserDefaults.standard.set(filename, forKey: "currentPreset")
        }
        window.contentView = view
        if !window.setFrameUsingName("Visualizer") {
            window.center()
        }
        window.setFrameAutosaveName("Visualizer")
        window.orderFrontRegardless()
        self.window = window
        visualizerView = view

        statusItem = makeStatusItem()
        view.contextMenu = statusItem?.menu
        applySettings()
    }

    // Defaults are the single source of truth; this pushes them to the window,
    // the view, and the menu in one place.
    private func applySettings() {
        let defaults = UserDefaults.standard
        let windowOpacity = max(0.15, defaults.double(forKey: "windowOpacity"))
        let backgroundOpacity = defaults.double(forKey: "backgroundOpacity")
        let softEdges = defaults.bool(forKey: "softEdges")
        let shuffle = defaults.bool(forKey: "shufflePresets")
        let locked = defaults.bool(forKey: "lockPreset")

        window?.alphaValue = windowOpacity
        window?.hasShadow = backgroundOpacity >= 0.999 && !softEdges
        visualizerView?.backgroundOpacity = Float(backgroundOpacity)
        visualizerView?.softEdges = softEdges
        visualizerView?.setShuffle(shuffle)
        visualizerView?.setPresetLocked(locked)
        shuffleItem?.state = shuffle ? .on : .off
        lockItem?.state = locked ? .on : .off
        softEdgesItem?.state = softEdges ? .on : .off
        windowOpacitySlider?.doubleValue = windowOpacity
        backgroundOpacitySlider?.doubleValue = backgroundOpacity
    }

    func applicationWillTerminate(_ notification: Notification) {
        audioEngine.stop()
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "water.waves",
            accessibilityDescription: "Fishtank"
        )

        let menu = NSMenu()
        menu.addItem(makeItem("Hide Visualizer", #selector(toggleVisibility), ""))
        menu.addItem(makeItem("Click-Through", #selector(toggleClickThrough), ""))
        menu.addItem(.separator())
        let (windowOpacityItem, windowSlider) = makeSliderItem(
            title: "Window Opacity", minValue: 0.15, action: #selector(windowOpacityChanged)
        )
        menu.addItem(windowOpacityItem)
        windowOpacitySlider = windowSlider
        let (backgroundOpacityItem, backgroundSlider) = makeSliderItem(
            title: "Background Opacity", minValue: 0, action: #selector(backgroundOpacityChanged)
        )
        menu.addItem(backgroundOpacityItem)
        backgroundOpacitySlider = backgroundSlider
        softEdgesItem = makeItem("Soft Edges", #selector(toggleSoftEdges), "")
        menu.addItem(softEdgesItem!)
        menu.addItem(.separator())
        menu.addItem(makeItem("Next Preset", #selector(nextPreset), ""))
        menu.addItem(makeItem("Previous Preset", #selector(previousPreset), ""))
        shuffleItem = makeItem("Shuffle Presets", #selector(toggleShuffle), "")
        menu.addItem(shuffleItem!)
        lockItem = makeItem("Lock Preset", #selector(toggleLock), "")
        menu.addItem(lockItem!)
        menu.addItem(makeItem("Browse Presets", #selector(showPresetBrowser), ""))
        menu.addItem(.separator())
        menu.addItem(makeItem("Open Presets Folder", #selector(openPresetsFolder), ""))
        menu.addItem(makeItem("Credits", #selector(showCredits), ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit Fishtank",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: ""
        ))
        item.menu = menu
        return item
    }

    private func makeItem(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func makeSliderItem(
        title: String, minValue: Double, action: Selector
    ) -> (NSMenuItem, NSSlider) {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 46))
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 14, y: 27, width: 192, height: 16)
        let slider = NSSlider(value: 1, minValue: minValue, maxValue: 1, target: self, action: action)
        slider.isContinuous = true
        slider.frame = NSRect(x: 12, y: 5, width: 196, height: 20)
        container.addSubview(label)
        container.addSubview(slider)
        let item = NSMenuItem()
        item.view = container
        return (item, slider)
    }

    @objc private func windowOpacityChanged(_ sender: NSSlider) {
        UserDefaults.standard.set(sender.doubleValue, forKey: "windowOpacity")
        applySettings()
    }

    @objc private func backgroundOpacityChanged(_ sender: NSSlider) {
        UserDefaults.standard.set(sender.doubleValue, forKey: "backgroundOpacity")
        applySettings()
    }

    @objc private func toggleSoftEdges(_ sender: NSMenuItem) {
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "softEdges"), forKey: "softEdges")
        applySettings()
    }

    @objc private func toggleVisibility(_ sender: NSMenuItem) {
        guard let window else { return }
        if window.isVisible {
            window.orderOut(nil)
            sender.title = "Show Visualizer"
        } else {
            window.orderFrontRegardless()
            sender.title = "Hide Visualizer"
        }
    }

    @objc private func toggleClickThrough(_ sender: NSMenuItem) {
        guard let window else { return }
        window.ignoresMouseEvents.toggle()
        sender.state = window.ignoresMouseEvents ? .on : .off
    }

    @objc private func nextPreset() {
        visualizerView?.playNextPreset()
    }

    @objc private func previousPreset() {
        visualizerView?.playPreviousPreset()
    }

    @objc private func toggleShuffle(_ sender: NSMenuItem) {
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "shufflePresets"), forKey: "shufflePresets")
        applySettings()
    }

    @objc private func toggleLock(_ sender: NSMenuItem) {
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "lockPreset"), forKey: "lockPreset")
        applySettings()
    }

    @objc private func openPresetsFolder() {
        try? FileManager.default.createDirectory(
            at: VisualizerView.presetsFolder, withIntermediateDirectories: true
        )
        NSWorkspace.shared.open(VisualizerView.presetsFolder)
    }

    private var presetBrowserWindow: NSWindow?

    @objc private func showPresetBrowser() {
        if presetBrowserWindow == nil, let view = visualizerView {
            let browser = PresetBrowserView(presets: view.allPresets()) { [weak self] index in
                self?.visualizerView?.selectPreset(at: index)
            }
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 340, height: 520),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Presets"
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.contentView = NSHostingView(rootView: browser)
            window.center()
            presetBrowserWindow = window
        }
        presetBrowserWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    @objc private func showCredits() {
        if creditsWindow == nil {
            creditsWindow = makeCreditsWindow()
        }
        creditsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private var creditsWindow: NSWindow?

    private func makeCreditsWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Credits"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()

        let scroll = NSScrollView(frame: window.contentLayoutRect)
        scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width, .height]

        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false
        text.textContainerInset = NSSize(width: 12, height: 12)
        text.autoresizingMask = [.width]
        if let url = Bundle.main.url(forResource: "CREDITS", withExtension: "md"),
           let contents = try? String(contentsOf: url, encoding: .utf8) {
            text.textStorage?.setAttributedString(Self.renderMarkdown(contents))
        }
        scroll.documentView = text
        window.contentView = scroll
        return window
    }

    private static func renderMarkdown(_ markdown: String) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        guard let parsed = try? AttributedString(markdown: markdown, options: options) else {
            return NSAttributedString(string: markdown)
        }
        let styled = NSMutableAttributedString(parsed)
        let fullRange = NSRange(location: 0, length: styled.length)
        styled.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
        styled.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            let traits = (value as? NSFont)?.fontDescriptor.symbolicTraits ?? []
            let font: NSFont = traits.contains(.bold)
                ? .boldSystemFont(ofSize: 12)
                : .systemFont(ofSize: 12)
            styled.addAttribute(.font, value: font, range: range)
        }
        return styled
    }
}
