import AppKit
import CProjectM

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        var major: Int32 = 0
        var minor: Int32 = 0
        var patch: Int32 = 0
        projectm_get_version_components(&major, &minor, &patch)
        NSLog("libprojectM %d.%d.%d", major, minor, patch)

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
}
