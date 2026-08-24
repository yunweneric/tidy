import Cocoa

/// The hover preview beside the clipboard panel.
///
/// Drawn by AppKit rather than by Flutter, because it has to appear *outside*
/// the popover. A popover clips its content to its own frame, so a preview
/// pane inside it would have to make the popover wider — and the popover is
/// anchored to a status item, so widening it slides the rows out from under
/// the pointer that is hovering them. A separate window has none of that
/// problem: the list stays exactly where it is and the preview appears next to
/// it, which is also what every other app that does this does.
///
/// It is deliberately not a second Flutter engine. This shows one clip's text
/// or one clip's image; a whole Dart isolate to draw that would cost more than
/// the feature.
final class ClipPreviewPanel {

  private let panel: NSPanel
  private let effect = NSVisualEffectView()
  private let scroll = NSScrollView()
  private let textView = NSTextView()
  private let imageView = NSImageView()
  private let caption = NSTextField(labelWithString: "")

  private let width: CGFloat = 320
  private let maxHeight: CGFloat = 420
  private let gap: CGFloat = 8
  private let padding: CGFloat = 12

  init() {
    panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: width, height: 200),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: true
    )
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = true
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    // Above the popover, and visible from every Space for the same reason the
    // popover is: the menu bar is.
    panel.level = .popUpMenu
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    // The pointer is on the list, not on this. Letting it take clicks would
    // only let the user dismiss their own preview by touching it.
    panel.ignoresMouseEvents = true

    effect.material = .popover
    effect.blendingMode = .behindWindow
    effect.state = .active
    effect.wantsLayer = true
    effect.layer?.cornerRadius = 10
    effect.layer?.masksToBounds = true

    textView.isEditable = false
    textView.isSelectable = false
    textView.drawsBackground = false
    textView.textContainerInset = NSSize(width: 0, height: 0)
    textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)

    scroll.drawsBackground = false
    scroll.hasVerticalScroller = false
    scroll.documentView = textView

    imageView.imageScaling = .scaleProportionallyUpOrDown
    imageView.isHidden = true

    caption.font = .systemFont(ofSize: 10)
    caption.textColor = .secondaryLabelColor
    caption.lineBreakMode = .byTruncatingTail

    panel.contentView = effect
    effect.addSubview(scroll)
    effect.addSubview(imageView)
    effect.addSubview(caption)
  }

  // MARK: - Showing

  /// Shows the preview for [entry] beside [anchorWindow], vertically lined up
  /// with the row the pointer is on.
  ///
  /// - Parameter rowTop: the row's distance from the top of the popover, in
  ///   points, as the Flutter panel measures it.
  func show(entry: ClipboardEntry, beside anchorWindow: NSWindow, rowTop: CGFloat) {
    let image = self.image(for: entry)
    let text = image == nil ? self.text(for: entry) : nil

    // Nothing to preview is not a preview. A blank card following the pointer
    // down the list is worse than no card.
    guard image != nil || !(text ?? "").isEmpty else {
      hide()
      return
    }

    caption.stringValue = self.caption(for: entry)
    let height = layout(image: image, text: text)

    let anchor = anchorWindow.frame
    var origin = NSPoint(
      x: anchor.maxX + gap,
      // AppKit's y grows upward; rowTop counts down from the top of the panel.
      y: anchor.maxY - rowTop - height
    )

    let screen = anchorWindow.screen ?? NSScreen.main
    if let visible = screen?.visibleFrame {
      // No room on the right — the status item is near the right edge on most
      // menu bars — so flip to the left of the panel instead of hanging off
      // the display.
      if origin.x + width > visible.maxX {
        origin.x = anchor.minX - width - gap
      }
      origin.x = max(visible.minX + gap, origin.x)
      origin.y = min(origin.y, visible.maxY - height)
      origin.y = max(origin.y, visible.minY + gap)
    }

    panel.setFrame(NSRect(x: origin.x, y: origin.y, width: width, height: height), display: true)
    panel.orderFrontRegardless()
  }

  func hide() {
    panel.orderOut(nil)
  }

  // MARK: - Content

  /// Lays the panel out for whichever kind of content this is, and returns the
  /// height it needs.
  private func layout(image: NSImage?, text: String?) -> CGFloat {
    let captionHeight: CGFloat = 14
    let inner = width - padding * 2

    if let image {
      imageView.image = image
      imageView.isHidden = false
      scroll.isHidden = true

      let ratio = image.size.height / max(image.size.width, 1)
      let imageHeight = min(inner * ratio, maxHeight - padding * 3 - captionHeight)
      let height = imageHeight + padding * 3 + captionHeight

      imageView.frame = NSRect(
        x: padding,
        y: padding * 2 + captionHeight,
        width: inner,
        height: imageHeight
      )
      caption.frame = NSRect(x: padding, y: padding, width: inner, height: captionHeight)
      return height
    }

    imageView.isHidden = true
    scroll.isHidden = false
    textView.string = text ?? ""
    textView.textColor = .labelColor

    // Measure the text at the panel's width so short clips get a short card.
    let measured = (text ?? "").boundingRect(
      with: NSSize(width: inner, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      attributes: [.font: textView.font ?? NSFont.systemFont(ofSize: 11)]
    ).height

    let textHeight = min(ceil(measured) + 4, maxHeight - padding * 3 - captionHeight)
    let height = textHeight + padding * 3 + captionHeight

    scroll.frame = NSRect(
      x: padding,
      y: padding * 2 + captionHeight,
      width: inner,
      height: textHeight
    )
    textView.frame = NSRect(x: 0, y: 0, width: inner, height: textHeight)
    caption.frame = NSRect(x: padding, y: padding, width: inner, height: captionHeight)
    return height
  }

  /// The whole text, including the part too long to sit inline in the index.
  private func text(for entry: ClipboardEntry) -> String? {
    if let text = entry.text { return text }
    guard entry.blobExtension == "txt",
          let url = ClipboardStore.shared.blobURL(for: entry)
    else { return nil }
    return try? String(contentsOf: url, encoding: .utf8)
  }

  private func image(for entry: ClipboardEntry) -> NSImage? {
    guard let ext = entry.blobExtension, ext != "txt",
          let url = ClipboardStore.shared.blobURL(for: entry)
    else { return nil }
    return NSImage(contentsOf: url)
  }

  private func caption(for entry: ClipboardEntry) -> String {
    var parts: [String] = []
    if let source = entry.sourceAppName { parts.append(source) }
    if entry.pixelWidth > 0 && entry.pixelHeight > 0 {
      parts.append("\(entry.pixelWidth) × \(entry.pixelHeight)")
    } else if entry.characterCount > 0 {
      parts.append("\(entry.characterCount) characters")
    }
    return parts.joined(separator: " · ")
  }
}
