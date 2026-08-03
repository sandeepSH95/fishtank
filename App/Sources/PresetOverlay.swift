import AppKit

// Preset name and author, shown briefly in the window's bottom-left corner.
// Lives in a child window because subviews don't composite over the GL surface.
// Titles wider than the window scroll across behind soft gradient-faded edges.
final class PresetOverlay {
    private static let margin: CGFloat = 10
    private static let fadeInset: CGFloat = 12
    private static let scrollSpeed: CGFloat = 40

    private let overlayWindow: NSWindow
    private let container: NSView
    private let label: NSTextField
    private let fadeMask = CAGradientLayer()
    private var stageTimer: Timer?
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

        container = NSView()
        container.wantsLayer = true
        container.addSubview(label)

        fadeMask.startPoint = CGPoint(x: 0, y: 0.5)
        fadeMask.endPoint = CGPoint(x: 1, y: 0.5)
        fadeMask.colors = [
            NSColor.clear.cgColor, NSColor.black.cgColor,
            NSColor.black.cgColor, NSColor.clear.cgColor,
        ]

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
        stageTimer?.invalidate()
        label.stringValue = text
        label.sizeToFit()
        reposition()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            overlayWindow.animator().alphaValue = 1
        }

        if isOverflowing {
            let target = overlayWindow.frame.width - Self.fadeInset - label.frame.width
            stageTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
                self?.scroll(to: target)
            }
        } else {
            scheduleFadeOut(after: 4)
        }
    }

    private var isOverflowing: Bool {
        label.frame.width + Self.fadeInset * 2 > availableWidth()
    }

    private func scroll(to targetX: CGFloat) {
        let distance = label.frame.origin.x - targetX
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = distance / Self.scrollSpeed
            context.timingFunction = CAMediaTimingFunction(name: .linear)
            label.animator().setFrameOrigin(NSPoint(x: targetX, y: 4))
        }, completionHandler: { [weak self] in
            self?.scheduleFadeOut(after: 1.5)
        })
    }

    private func scheduleFadeOut(after delay: TimeInterval) {
        stageTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 1
                self.overlayWindow.animator().alphaValue = 0
            }
        }
    }

    private func availableWidth() -> CGFloat {
        max(60, (parent?.frame.width ?? 0) - Self.margin * 2)
    }

    @objc private func reposition() {
        guard let parent else { return }
        let overflowing = isOverflowing
        let width = overflowing ? availableWidth() : label.frame.width + 8
        let size = NSSize(width: width, height: label.frame.height + 8)
        let origin = NSPoint(x: parent.frame.minX + Self.margin, y: parent.frame.minY + Self.margin)
        overlayWindow.setFrame(NSRect(origin: origin, size: size), display: true)
        label.setFrameOrigin(NSPoint(x: overflowing ? Self.fadeInset : 4, y: 4))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if overflowing {
            fadeMask.frame = CGRect(origin: .zero, size: size)
            let fade = Self.fadeInset / width
            fadeMask.locations = [0, NSNumber(value: fade), NSNumber(value: 1 - fade), 1]
            container.layer?.mask = fadeMask
        } else {
            container.layer?.mask = nil
        }
        CATransaction.commit()
    }

    deinit {
        stageTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        parent?.removeChildWindow(overlayWindow)
    }
}
