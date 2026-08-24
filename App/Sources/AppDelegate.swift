import AppKit
import SwiftUI
import CProjectM

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var window: FloatingWindow?
    private var visualizerView: VisualizerView?
    private let audioEngine = AudioTapEngine()

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            "shufflePresets": true,
            "lockPreset": true,
            "windowOpacity": 1.0,
            "backgroundOpacity": 1.0,
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

        let window = FloatingWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300))
        let view = VisualizerView(frame: window.contentLayoutRect, audioEngine: audioEngine)
        window.contentView = view
        if !window.setFrameUsingName("Visualizer") {
            window.center()
        }
        window.setFrameAutosaveName("Visualizer")
        window.orderFrontRegardless()
        self.window = window
        visualizerView = view

        let windowOpacity = max(0.15, UserDefaults.standard.double(forKey: "windowOpacity"))
        let backgroundOpacity = UserDefaults.standard.double(forKey: "backgroundOpacity")
        window.alphaValue = windowOpacity
        view.backgroundOpacity = Float(backgroundOpacity)
        window.hasShadow = backgroundOpacity >= 0.999

        statusItem = makeStatusItem()
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
        menu.addItem(makeSliderItem(
            title: "Window Opacity",
            value: UserDefaults.standard.double(forKey: "windowOpacity"),
            minValue: 0.15,
            action: #selector(windowOpacityChanged)
        ))
        menu.addItem(makeSliderItem(
            title: "Background Opacity",
            value: UserDefaults.standard.double(forKey: "backgroundOpacity"),
            minValue: 0,
            action: #selector(backgroundOpacityChanged)
        ))
        menu.addItem(.separator())
        menu.addItem(makeItem("Next Preset", #selector(nextPreset), ""))
        menu.addItem(makeItem("Previous Preset", #selector(previousPreset), ""))
        let shuffle = makeItem("Shuffle Presets", #selector(toggleShuffle), "")
        shuffle.state = UserDefaults.standard.bool(forKey: "shufflePresets") ? .on : .off
        menu.addItem(shuffle)
        let lock = makeItem("Lock Preset", #selector(toggleLock), "")
        lock.state = UserDefaults.standard.bool(forKey: "lockPreset") ? .on : .off
        menu.addItem(lock)
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
        visualizerView?.contextMenu = menu
        return item
    }

    private func makeItem(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func makeSliderItem(
        title: String, value: Double, minValue: Double, action: Selector
    ) -> NSMenuItem {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 46))
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 14, y: 27, width: 192, height: 16)
        let slider = NSSlider(value: value, minValue: minValue, maxValue: 1, target: self, action: action)
        slider.isContinuous = true
        slider.frame = NSRect(x: 12, y: 5, width: 196, height: 20)
        container.addSubview(label)
        container.addSubview(slider)
        let item = NSMenuItem()
        item.view = container
        return item
    }

    @objc private func windowOpacityChanged(_ sender: NSSlider) {
        UserDefaults.standard.set(sender.doubleValue, forKey: "windowOpacity")
        window?.alphaValue = sender.doubleValue
    }

    @objc private func backgroundOpacityChanged(_ sender: NSSlider) {
        UserDefaults.standard.set(sender.doubleValue, forKey: "backgroundOpacity")
        visualizerView?.backgroundOpacity = Float(sender.doubleValue)
        window?.hasShadow = sender.doubleValue >= 0.999
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
        let enabled = sender.state != .on
        sender.state = enabled ? .on : .off
        UserDefaults.standard.set(enabled, forKey: "shufflePresets")
        visualizerView?.setShuffle(enabled)
    }

    @objc private func toggleLock(_ sender: NSMenuItem) {
        let locked = sender.state != .on
        sender.state = locked ? .on : .off
        UserDefaults.standard.set(locked, forKey: "lockPreset")
        visualizerView?.setPresetLocked(locked)
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
