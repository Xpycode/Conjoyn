import AppKit

/// Drop-in Help menu for AppKit apps.
///
/// ```swift
/// func applicationDidFinishLaunching(_ note: Notification) {
///     AppKitHelpMenu.install(into: NSApp.mainMenu, content: MyHelp.content, appName: "MyApp")
/// }
/// ```
@MainActor
public enum AppKitHelpMenu {

    /// Build a Help `NSMenu` item wired to open the shared help window.
    ///
    /// - Parameters:
    ///   - content: Host-supplied help content.
    ///   - appName: Labels the item ("<appName> Help"); falls back to the
    ///     content's window title when nil.
    /// - Returns: An `NSMenuItem` carrying a populated Help submenu. Assign it
    ///   to `NSApplication.helpMenu` or insert it into the main menu.
    public static func makeHelpMenuItem(content: HelpContent, appName: String? = nil) -> NSMenuItem {
        let title = appName.map { "\($0) Help" } ?? content.windowTitle

        let submenu = NSMenu(title: "Help")
        let action = HelpMenuAction(content: content)
        let item = NSMenuItem(title: title, action: #selector(HelpMenuAction.openHelp), keyEquivalent: "?")
        item.keyEquivalentModifierMask = [.command]
        item.target = action
        item.representedObject = action // retain the action target for the menu's lifetime
        submenu.addItem(item)

        let menuItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        menuItem.submenu = submenu
        return menuItem
    }

    /// Install (or replace) the Help menu on the given main menu, and register
    /// it as `NSApplication.helpMenu` so it lands in the standard position.
    ///
    /// - Parameter mainMenu: Usually `NSApp.mainMenu`. No-op if nil.
    public static func install(into mainMenu: NSMenu?, content: HelpContent, appName: String? = nil) {
        guard let mainMenu else { return }

        // Remove any existing item registered as the help menu to avoid dupes.
        if let existing = NSApp.helpMenu?.supermenu == mainMenu ? NSApp.helpMenu : nil,
           let supermenu = existing.supermenu,
           let parentItem = supermenu.items.first(where: { $0.submenu === existing }) {
            supermenu.removeItem(parentItem)
        }

        let menuItem = makeHelpMenuItem(content: content, appName: appName)
        mainMenu.addItem(menuItem)
        NSApp.helpMenu = menuItem.submenu
    }
}

/// Target object bridging an `NSMenuItem` action to `HelpWindowController`.
/// Held alive via the menu item's `representedObject`.
@MainActor
final class HelpMenuAction: NSObject {
    private let content: HelpContent

    init(content: HelpContent) {
        self.content = content
        super.init()
    }

    @objc func openHelp() {
        HelpWindowController.showHelp(content: content)
    }
}
