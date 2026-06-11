import SwiftUI

/// Drop-in Help menu for SwiftUI apps.
///
/// Replaces the default Help menu group with a single "<App> Help" item
/// (⌘?) that opens the shared help window.
///
/// ```swift
/// @main
/// struct MyApp: App {
///     var body: some Scene {
///         WindowGroup { ContentView() }
///             .commands {
///                 HelpMenuCommands(content: MyHelp.content, appName: "MyApp")
///             }
///     }
/// }
/// ```
public struct HelpMenuCommands: Commands {
    private let content: HelpContent
    private let title: String

    /// - Parameters:
    ///   - content: Host-supplied help content.
    ///   - appName: Used to label the menu item ("<appName> Help"). When nil,
    ///     falls back to the content's window title.
    public init(content: HelpContent, appName: String? = nil) {
        self.content = content
        if let appName {
            self.title = "\(appName) Help"
        } else {
            self.title = content.windowTitle
        }
    }

    public var body: some Commands {
        CommandGroup(replacing: .help) {
            Button(title) {
                HelpWindowController.showHelp(content: content)
            }
            // "?" = Shift+/ on US keyboards; SwiftUI's "?" literal is unreliable.
            // Registering "/" with .command + .shift is the robust equivalent.
            .keyboardShortcut("/", modifiers: [.command, .shift])
        }
    }
}
