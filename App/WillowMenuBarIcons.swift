import AppKit

func configureWillowMenuBarButton(_ item: NSStatusItem) {
    item.button?.title = ""
    item.button?.imagePosition = .imageOnly
    item.button?.imageScaling = .scaleNone
}

let willowMenuBarIcon = WillowMark.image(height: WillowMark.size.height)
