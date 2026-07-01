import AppKit
import Foundation

struct NodeProcess {
    let pid: Int
    let ppid: Int
    let stat: String
    let command: String
    let commandName: String
    let args: String
}

func runCommand(_ executable: String, _ arguments: [String]) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    do {
        try process.run()
    } catch {
        return nil
    }

    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        return nil
    }

    return String(data: data, encoding: .utf8)
}

func parsePSLine(_ line: String) -> NodeProcess? {
    let pattern = #"^\s*(\d+)\s+(\d+)\s+(\S+)\s+(\S+)(?:\s+(.*))?$"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return nil
    }

    let range = NSRange(line.startIndex..<line.endIndex, in: line)
    guard let match = regex.firstMatch(in: line, range: range), match.numberOfRanges >= 5 else {
        return nil
    }

    func value(_ index: Int) -> String {
        guard match.range(at: index).location != NSNotFound,
              let range = Range(match.range(at: index), in: line) else {
            return ""
        }

        return String(line[range])
    }

    guard let pid = Int(value(1)), let ppid = Int(value(2)) else {
        return nil
    }

    let command = value(4)
    let commandName = (command as NSString).lastPathComponent.lowercased()

    return NodeProcess(
        pid: pid,
        ppid: ppid,
        stat: value(3),
        command: command,
        commandName: commandName,
        args: value(5).trimmingCharacters(in: .whitespacesAndNewlines)
    )
}

func listNodeProcesses() -> [NodeProcess] {
    guard let output = runCommand("/bin/ps", ["-axo", "pid=,ppid=,stat=,comm=,args="]) else {
        return []
    }

    return output
        .split(separator: "\n")
        .compactMap { parsePSLine(String($0)) }
        .filter { $0.commandName == "node" || $0.commandName == "nodejs" }
}

func killProcess(pid: Int) {
    _ = runCommand("/bin/kill", ["-TERM", String(pid)])
}

func processCwd(pid: Int) -> String? {
    guard let output = runCommand("/usr/sbin/lsof", ["-a", "-p", String(pid), "-d", "cwd", "-Fn"]) else {
        return nil
    }

    return output
        .split(separator: "\n")
        .map(String.init)
        .first { $0.hasPrefix("n") }
        .map { String($0.dropFirst()) }
}

func shellQuote(_ value: String) -> String {
    return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

func appleScriptString(_ value: String) -> String {
    return "\"" + value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"") + "\""
}

func openTerminal(at cwd: String) {
    let command = "cd \(shellQuote(cwd)); clear; pwd"
    let script = """
    tell application "Terminal"
    activate
    do script \(appleScriptString(command))
    end tell
    """

    _ = runCommand("/usr/bin/osascript", ["-e", script])
}

func makeSpruceTreeIcon() -> NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 18))

    image.lockFocus()
    NSColor.black.setFill()

    let tree = NSBezierPath()
    tree.move(to: NSPoint(x: 9.0, y: 16.0))
    tree.line(to: NSPoint(x: 4.3, y: 10.8))
    tree.line(to: NSPoint(x: 6.5, y: 10.8))
    tree.line(to: NSPoint(x: 3.7, y: 7.2))
    tree.line(to: NSPoint(x: 6.4, y: 7.2))
    tree.line(to: NSPoint(x: 4.7, y: 4.7))
    tree.line(to: NSPoint(x: 8.0, y: 4.7))
    tree.line(to: NSPoint(x: 8.0, y: 2.7))
    tree.line(to: NSPoint(x: 10.0, y: 2.7))
    tree.line(to: NSPoint(x: 10.0, y: 4.7))
    tree.line(to: NSPoint(x: 13.3, y: 4.7))
    tree.line(to: NSPoint(x: 11.6, y: 7.2))
    tree.line(to: NSPoint(x: 14.3, y: 7.2))
    tree.line(to: NSPoint(x: 11.5, y: 10.8))
    tree.line(to: NSPoint(x: 13.7, y: 10.8))
    tree.close()
    tree.fill()

    image.unlockFocus()
    image.isTemplate = true
    return image
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let menu = NSMenu()
    private let processQueue = DispatchQueue(label: "dev.nodesnoop.processes", qos: .utility)
    private var statusItem: NSStatusItem?
    private var cachedProcesses: [NodeProcess] = []
    private var isRefreshing = false
    private var lastRefreshDate: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = makeSpruceTreeIcon()
        statusItem?.button?.imagePosition = .imageOnly
        statusItem?.button?.toolTip = "NodeSnoop"
        statusItem?.button?.setAccessibilityLabel("NodeSnoop")

        menu.delegate = self
        statusItem?.menu = menu
        renderMenu()
        refreshProcesses(force: true)
    }

    func menuWillOpen(_ menu: NSMenu) {
        renderMenu()
        refreshProcesses()
    }

    private func commandLabel(for process: NodeProcess, limit: Int = 58) -> String {
        let command = process.args.isEmpty ? process.command : process.args
        let normalized = command.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )

        return normalized.count > limit ? String(normalized.prefix(limit - 3)) + "..." : normalized
    }

    private func processTitle(for process: NodeProcess) -> String {
        return "PID \(process.pid) - \(commandLabel(for: process))"
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title.uppercased(), action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: title.uppercased(),
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func processCountTitle(_ count: Int, refreshing: Bool = false) -> String {
        if refreshing && count == 0 {
            return "Refreshing process list..."
        }

        if count == 0 {
            return "No Node.js processes running"
        }

        let title = "\(count) Node.js process\(count == 1 ? "" : "es") running"
        return refreshing ? "\(title) - refreshing" : title
    }

    private func shouldRefresh() -> Bool {
        guard let lastRefreshDate else {
            return true
        }

        return Date().timeIntervalSince(lastRefreshDate) > 2
    }

    private func refreshProcesses(force: Bool = false) {
        guard force || shouldRefresh() else {
            return
        }

        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        renderMenu()

        processQueue.async { [weak self] in
            let processes = listNodeProcesses().sorted { $0.pid < $1.pid }

            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                self.cachedProcesses = processes
                self.lastRefreshDate = Date()
                self.isRefreshing = false
                self.renderMenu()
            }
        }
    }

    private func renderMenu() {
        menu.removeAllItems()
        let processes = cachedProcesses

        let header = disabledItem("NodeSnoop")
        header.image = makeSpruceTreeIcon()
        menu.addItem(header)
        menu.addItem(disabledItem(processCountTitle(processes.count, refreshing: isRefreshing)))
        statusItem?.button?.toolTip = "NodeSnoop - \(processCountTitle(processes.count))"
        menu.addItem(NSMenuItem.separator())

        menu.addItem(sectionHeader("Processes"))
        if processes.isEmpty && isRefreshing {
            menu.addItem(disabledItem("Refreshing..."))
        } else if processes.isEmpty {
            menu.addItem(disabledItem("No running Node.js processes"))
        } else {
            for process in processes {
                let item = NSMenuItem(title: processTitle(for: process), action: nil, keyEquivalent: "")
                let submenu = NSMenu()

                submenu.addItem(disabledItem("PID \(process.pid)"))
                submenu.addItem(disabledItem("Parent PID \(process.ppid) - Status \(process.stat)"))
                submenu.addItem(NSMenuItem.separator())

                let openItem = NSMenuItem(title: "Open Terminal at Working Directory", action: #selector(openProcessTerminal(_:)), keyEquivalent: "")
                openItem.target = self
                openItem.representedObject = process.pid
                submenu.addItem(openItem)

                let copyItem = NSMenuItem(title: "Copy PID", action: #selector(copyProcessPID(_:)), keyEquivalent: "")
                copyItem.target = self
                copyItem.representedObject = process.pid
                submenu.addItem(copyItem)

                submenu.addItem(NSMenuItem.separator())

                let killItem = NSMenuItem(title: "Kill Process", action: #selector(killMenuItemProcess(_:)), keyEquivalent: "")
                killItem.target = self
                killItem.representedObject = process.pid
                submenu.addItem(killItem)

                item.submenu = submenu
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(sectionHeader("Bulk Actions"))

        let killAllItem = NSMenuItem(title: "Kill All Node.js Processes", action: #selector(killAllProcesses(_:)), keyEquivalent: "")
        killAllItem.target = self
        killAllItem.isEnabled = !processes.isEmpty
        menu.addItem(killAllItem)

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refresh(_:)), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(sectionHeader("Application"))

        let quitItem = NSMenuItem(title: "Quit NodeSnoop", action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func openProcessTerminal(_ sender: NSMenuItem) {
        guard let pid = sender.representedObject as? Int else {
            return
        }

        processQueue.async {
            guard let cwd = processCwd(pid: pid) else {
                DispatchQueue.main.async {
                    NSSound.beep()
                }
                return
            }

            openTerminal(at: cwd)
        }
    }

    @objc private func copyProcessPID(_ sender: NSMenuItem) {
        guard let pid = sender.representedObject as? Int else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(pid), forType: .string)
    }

    @objc private func killMenuItemProcess(_ sender: NSMenuItem) {
        guard let pid = sender.representedObject as? Int else {
            return
        }

        cachedProcesses.removeAll { $0.pid == pid }
        renderMenu()

        processQueue.async { [weak self] in
            killProcess(pid: pid)

            DispatchQueue.main.async {
                self?.refreshProcesses(force: true)
            }
        }
    }

    @objc private func killAllProcesses(_ sender: NSMenuItem) {
        let pids = cachedProcesses.map { $0.pid }
        cachedProcesses = []
        renderMenu()

        processQueue.async { [weak self] in
            for pid in pids {
                killProcess(pid: pid)
            }

            DispatchQueue.main.async {
                self?.refreshProcesses(force: true)
            }
        }
    }

    @objc private func refresh(_ sender: NSMenuItem) {
        refreshProcesses(force: true)
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
