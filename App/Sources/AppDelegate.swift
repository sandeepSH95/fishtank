import AppKit
import CProjectM

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var window: FloatingWindow?
    private var visualizerView: VisualizerView?
    private let audioEngine = AudioTapEngine()

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        window.center()
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
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit Fishtank",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        item.menu = menu
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
}
