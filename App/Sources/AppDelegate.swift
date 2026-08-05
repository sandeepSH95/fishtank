import AppKit
import SwiftUI
import CProjectM

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var window: FloatingWindow?
    private var visualizerView: VisualizerView?
    private let audioEngine = AudioTapEngine()

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["shufflePresets": true, "lockPreset": true])

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
        menu.addItem(makeItem("Hide Visualizer", #selector(toggleVisibility), "h"))
        menu.addItem(makeItem("Click-Through", #selector(toggleClickThrough), "t"))
        menu.addItem(.separator())
        menu.addItem(makeItem("Next Preset", #selector(nextPreset), "n"))
        menu.addItem(makeItem("Previous Preset", #selector(previousPreset), "p"))
        let shuffle = makeItem("Shuffle Presets", #selector(toggleShuffle), "")
        shuffle.state = UserDefaults.standard.bool(forKey: "shufflePresets") ? .on : .off
        menu.addItem(shuffle)
        let lock = makeItem("Lock Preset", #selector(toggleLock), "")
        lock.state = UserDefaults.standard.bool(forKey: "lockPreset") ? .on : .off
        menu.addItem(lock)
        menu.addItem(makeItem("Browse Presets", #selector(showPresetBrowser), "b"))
        menu.addItem(.separator())
        menu.addItem(makeItem("Open Presets Folder", #selector(openPresetsFolder), ""))
        menu.addItem(makeItem("Credits", #selector(showCredits), ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit Fishtank",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
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
        window.center()

        let scroll = NSScrollView(frame: window.contentLayoutRect)
        scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width, .height]

        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false
        text.font = .systemFont(ofSize: 12)
        text.textContainerInset = NSSize(width: 12, height: 12)
        text.autoresizingMask = [.width]
        if let url = Bundle.main.url(forResource: "CREDITS", withExtension: "md"),
           let contents = try? String(contentsOf: url, encoding: .utf8) {
            text.string = contents
        }
        scroll.documentView = text
        window.contentView = scroll
        return window
    }
}
