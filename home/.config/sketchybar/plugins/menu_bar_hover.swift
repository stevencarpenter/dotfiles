import AppKit
import CoreGraphics
import Darwin
import Foundation

/// MenuBarAgent retains an invisible click-catching window on macOS 27.
/// The Window Server menu window is onscreen only while the native menu is shown.
/// NSMenu.menuBarVisible() reported false even with the menu visible in live probes.
func nativeMenuVisible(in windows: [[String: Any]]) -> Bool {
    windows.contains { window in
        window[kCGWindowOwnerName as String] as? String == "Window Server"
            && window[kCGWindowLayer as String] as? Int == Int(CGWindowLevelForKey(.mainMenuWindow))
            && window[kCGWindowIsOnscreen as String] as? Bool == true
    }
}

if CommandLine.arguments.dropFirst() == ["--self-test"] {
    let menu: [String: Any] = [
        kCGWindowOwnerName as String: "Window Server",
        kCGWindowLayer as String: Int(CGWindowLevelForKey(.mainMenuWindow)),
        kCGWindowIsOnscreen as String: true,
    ]
    var hiddenMenu = menu
    hiddenMenu[kCGWindowIsOnscreen as String] = false
    var invisibleAgent = menu
    invisibleAgent[kCGWindowOwnerName as String] = "MenuBarAgent"
    var customBar = menu
    customBar[kCGWindowOwnerName as String] = "sketchybar"
    var ordinaryWindow = menu
    ordinaryWindow[kCGWindowLayer as String] = 0
    precondition(!nativeMenuVisible(in: [hiddenMenu, invisibleAgent, customBar, ordinaryWindow]))
    precondition(nativeMenuVisible(in: [invisibleAgent, menu, customBar]))
    precondition(!nativeMenuVisible(in: []))
    print("native menu visibility detection passed")
    exit(0)
}

guard CommandLine.arguments.count == 4,
      let barPID = Int32(CommandLine.arguments[2]), barPID > 0
else {
    fputs("usage: sketchybar-menu-hover <sketchybar-path> <sketchybar-pid> <launch-lock>\n", stderr)
    exit(1)
}

let sketchybar = URL(fileURLWithPath: CommandLine.arguments[1])
var lastHidden: Bool?

func setHidden(_ hidden: Bool) {
    guard hidden != lastHidden else { return }
    let command = Process()
    command.executableURL = sketchybar
    var arguments: [String]
    if hidden {
        arguments = ["--set", "/.*/", "popup.drawing=off"]
    } else {
        // workspace.1 is already first. This no-op reorder raises existing windows
        // above MenuBarAgent, preserving tab clicks without resetting topmost.
        // This ordering side effect needs live click verification after upgrades.
        // Measured return fell from about 730 ms with a reset to 370 ms here.
        arguments = ["--bar", "hidden=off", "--reorder", "workspace.1"]
    }
    if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        // Six frames give a 100 ms slide in either direction; preserve Reduce Motion.
        arguments += ["--animate", "sin", "6"]
    }
    // The configured bar is 37 points tall. Sliding it offscreen avoids instant toggles.
    arguments += ["--bar", "y_offset=\(hidden ? -50 : 0)"]
    command.arguments = arguments
    do {
        try command.run()
        command.waitUntilExit()
        if command.terminationStatus == 0 {
            lastHidden = hidden
        }
    } catch {
        fputs("menu-bar-hover: \(error)\n", stderr)
    }
}

/// Restore SketchyBar on normal shutdown, including a configuration reload.
var signals: [DispatchSourceSignal] = []
for number in [SIGTERM, SIGINT] {
    signal(number, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
    source.setEventHandler {
        setHidden(false)
        exit(0)
    }
    source.resume()
    signals.append(source)
}

let timer = DispatchSource.makeTimerSource(queue: .main)
// No documented SketchyBar event reports native menu visibility. Polling every
// 50 ms bounds detection delay; launch CLI commands only on visibility changes.
timer.schedule(deadline: .now(), repeating: .milliseconds(50), leeway: .milliseconds(5))
timer.setEventHandler {
    // A stopped SketchyBar must not leave an orphan poller or launch CLI retries.
    guard kill(barPID, 0) == 0 else { exit(0) }
    guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                   kCGNullWindowID) as? [[String: Any]]
    else { return }
    // ponytail: hide all bars together; use per-display visibility if independent monitors are needed.
    setHidden(nativeMenuVisible(in: windows))
}

timer.resume()
guard unlink(CommandLine.arguments[3]) == 0 else {
    perror("menu-bar-hover: release launch lock")
    exit(1)
}
dispatchMain()
