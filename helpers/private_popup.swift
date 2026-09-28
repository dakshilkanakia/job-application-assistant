import Cocoa

guard CommandLine.arguments.count > 1,
      let data = FileManager.default.contents(atPath: CommandLine.arguments[1]),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
    exit(1)
}

let answerText = (json["answer"] as? String) ?? ""
let caveatText = json["caveat"] as? String
let footerText = (json["footer"] as? String) ?? "Copied to clipboard. Press Esc or F6 to dismiss."
let hidden = (json["hidden"] as? Bool) ?? true
let autoCloseSeconds = json["autoCloseSeconds"] as? Double
let isDot = (json["dot"] as? Bool) ?? false

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

if isDot {
    // Plain colored circle, bottom-left, same size/position as the green
    // busy-dot canvas indicator — just invisible on a shared screen too.
    let colorArr = json["color"] as? [Double] ?? [1, 1, 1]
    let screen = NSScreen.main!.frame
    let size: CGFloat = 10
    // x/y (if provided) are Hammerspoon's top-down coordinates for this same
    // dot's position, computed once in Lua and passed straight through so
    // this never independently drifts from where the green dot actually is.
    let winX: CGFloat
    let winY: CGFloat
    if let hsX = json["x"] as? Double, let hsY = json["y"] as? Double {
        winX = CGFloat(hsX)
        winY = screen.height - CGFloat(hsY) - size
    } else {
        winX = screen.minX + 12
        winY = screen.minY + 12
    }
    let dotWindow = NSWindow(
        contentRect: NSRect(x: winX, y: winY, width: size, height: size),
        styleMask: [.borderless],
        backing: .buffered, defer: false
    )
    dotWindow.isOpaque = false
    dotWindow.backgroundColor = .clear
    dotWindow.level = .floating
    dotWindow.hasShadow = false
    dotWindow.ignoresMouseEvents = true
    if hidden { dotWindow.sharingType = .none }

    let dotView = NSView(frame: NSRect(x: 0, y: 0, width: size, height: size))
    dotView.wantsLayer = true
    dotView.layer?.backgroundColor = NSColor(
        calibratedRed: colorArr[0], green: colorArr[1], blue: colorArr[2], alpha: 0.95
    ).cgColor
    dotView.layer?.cornerRadius = size / 2
    dotWindow.contentView = dotView

    dotWindow.orderFrontRegardless()

    signal(SIGTERM) { _ in NSApp.terminate(nil) }
    if let seconds = autoCloseSeconds {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { NSApp.terminate(nil) }
    }
    app.run()
    exit(0)
}

let screen = NSScreen.main!.frame
let w: CGFloat = 460
let h: CGFloat = 320
let panel = NSPanel(
    contentRect: NSRect(x: screen.maxX - w - 24, y: screen.maxY - h - 80, width: w, height: h),
    styleMask: [.nonactivatingPanel, .titled, .closable, .utilityWindow],
    backing: .buffered, defer: false
)
panel.level = .floating
panel.isFloatingPanel = true
panel.hidesOnDeactivate = false
if hidden { panel.sharingType = .none }
panel.title = "Claude (private)"
panel.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1.0)

class CloseDelegate: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }
}
let delegate = CloseDelegate()
panel.delegate = delegate

func makeLabel(_ text: String, size: CGFloat, color: NSColor, bold: Bool = false) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
    label.textColor = color
    label.backgroundColor = .clear
    label.isBezeled = false
    label.isEditable = false
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
}

let stack = NSStackView()
stack.orientation = .vertical
stack.alignment = .leading
stack.spacing = 10
stack.translatesAutoresizingMaskIntoConstraints = false

let answerLabel = makeLabel(answerText, size: 14, color: NSColor(calibratedWhite: 0.94, alpha: 1.0))
stack.addArrangedSubview(answerLabel)
answerLabel.widthAnchor.constraint(equalToConstant: w - 28).isActive = true

if let caveat = caveatText, !caveat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    let sep = NSBox()
    sep.boxType = .separator
    stack.addArrangedSubview(sep)
    let caveatLabel = makeLabel("\u{26A0} " + caveat, size: 12, color: NSColor(calibratedRed: 0.88, green: 0.72, blue: 0.30, alpha: 1.0))
    stack.addArrangedSubview(caveatLabel)
    caveatLabel.widthAnchor.constraint(equalToConstant: w - 28).isActive = true
}

if !footerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    let footerLabel = makeLabel(footerText, size: 11, color: NSColor(calibratedWhite: 0.55, alpha: 1.0))
    stack.addArrangedSubview(footerLabel)
    footerLabel.widthAnchor.constraint(equalToConstant: w - 28).isActive = true
}

// A flipped document view so content starts at the top and scrolls downward
// (AppKit's default coordinate system is bottom-up, which reads upside-down
// for a scrolling text view).
class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

let documentView = FlippedView()
documentView.translatesAutoresizingMaskIntoConstraints = false
documentView.addSubview(stack)

NSLayoutConstraint.activate([
    documentView.widthAnchor.constraint(equalToConstant: w),
    stack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 14),
    stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 14),
    stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -14),
    stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -14),
])

let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: w, height: h))
scrollView.hasVerticalScroller = true
scrollView.hasHorizontalScroller = false
scrollView.autohidesScrollers = false
scrollView.drawsBackground = true
scrollView.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1.0)
scrollView.documentView = documentView
panel.contentView = scrollView

panel.makeKeyAndOrderFront(nil)

signal(SIGTERM) { _ in NSApp.terminate(nil) }

if let seconds = autoCloseSeconds {
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
        NSApp.terminate(nil)
    }
}

app.run()
