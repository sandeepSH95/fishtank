import AppKit

// Preset name and author, shown briefly in the window's bottom-left corner.
// Lives in a child window because subviews don't composite over the GL surface.
final class PresetOverlay {
    private let overlayWindow: NSWindow
    private let label: NSTextField
    private var hideTimer: Timer?
    private weak var parent: NSWindow?

    init(parent: NSWindow) {
        self.parent = parent

        label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.7)
        shadow.shadowBlurRadius = 4
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        label.shadow = shadow

        let container = NSView()
        container.addSubview(label)

        overlayWindow = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        overlayWindow.isOpaque = false
        overlayWindow.backgroundColor = .clear
        overlayWindow.hasShadow = false
        overlayWindow.ignoresMouseEvents = true
        overlayWindow.contentView = container
        overlayWindow.alphaValue = 0
        parent.addChildWindow(overlayWindow, ordered: .above)

        NotificationCenter.default.addObserver(
            self, selector: #selector(reposition),
            name: NSWindow.didResizeNotification, object: parent
        )
    }

    func show(_ text: String) {
        label.stringValue = text
        label.sizeToFit()
        label.setFrameOrigin(NSPoint(x: 4, y: 4))
        reposition()

        hideTimer?.invalidate()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            overlayWindow.animator().alphaValue = 1
        }
        hideTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 1
                self.overlayWindow.animator().alphaValue = 0
            }
        }
    }

    @objc private func reposition() {
        guard let parent else { return }
        let size = NSSize(width: label.frame.width + 8, height: label.frame.height + 8)
        let origin = NSPoint(x: parent.frame.minX + 10, y: parent.frame.minY + 10)
        overlayWindow.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    deinit {
        hideTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        parent?.removeChildWindow(overlayWindow)
    }
}
