import AppKit

/// Fit the 16 pt image exactly; no title, badge, or additional content width.
func configureWillowMenuBarButton(_ item: NSStatusItem) {
    item.length = 16
    item.button?.title = ""
    item.button?.imagePosition = .imageOnly
    item.button?.imageScaling = .scaleNone
}

/// All three curves use the same full rotor. The status button labels identify the mode.
let willowMenuBarIcon = WillowMark.image(size: 16, template: true)
