import Cocoa

final class MenuBarMenuDelegate: NSObject, NSMenuDelegate {
    var onWillOpen: (() -> Void)?

    func menuWillOpen(_ menu: NSMenu) {
        onWillOpen?()
    }
}
