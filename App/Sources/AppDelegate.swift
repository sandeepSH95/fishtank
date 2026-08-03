import AppKit
import CProjectM

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private let audioEngine = AudioTapEngine()

    func applicationDidFinishLaunching(_ notification: Notification) {
        var major: Int32 = 0
        var minor: Int32 = 0
        var patch: Int32 = 0
        projectm_get_version_components(&major, &minor, &patch)
        NSLog("libprojectM %d.%d.%d", major, minor, patch)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Fishtank"
        window.isReleasedWhenClosed = false

        do {
            try audioEngine.start()
            NSLog("audio tap running at %.0f Hz, %d channels", audioEngine.sampleRate, audioEngine.channelCount)
        } catch {
            NSLog("audio capture unavailable: \(error)")
        }

        window.contentView = VisualizerView(frame: window.contentLayoutRect, audioEngine: audioEngine)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        self.window = window

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "water.waves",
            accessibilityDescription: "Fishtank"
        )
        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: "Quit Fishtank",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        item.menu = menu
        statusItem = item
    }

    func applicationWillTerminate(_ notification: Notification) {
        audioEngine.stop()
    }
}
