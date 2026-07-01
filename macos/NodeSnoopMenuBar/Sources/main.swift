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

struct ProcessDisplay {
    let process: NodeProcess
    let cwd: String?
    let projectRoot: String?
    let projectName: String
    let framework: String
    let commandSummary: String
    let ports: [Int]

    var isLocalhostProject: Bool {
        return !ports.isEmpty
    }

    var primaryURL: String? {
        guard let port = ports.first else {
            return nil
        }

        return "http://localhost:\(port)"
    }
}

final class ProcessMenuPayload: NSObject {
    let pid: Int
    let cwd: String?
    let url: String?

    init(pid: Int, cwd: String?, url: String?) {
        self.pid = pid
        self.cwd = cwd
        self.url = url
    }
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

func processCwdsByPID(_ pids: [Int]) -> [Int: String] {
    guard !pids.isEmpty else {
        return [:]
    }

    let pidList = pids.map(String.init).joined(separator: ",")
    guard let output = runCommand("/usr/sbin/lsof", ["-nP", "-a", "-p", pidList, "-d", "cwd", "-Fpn"]) else {
        return [:]
    }

    var currentPID: Int?
    var result: [Int: String] = [:]

    for line in output.split(separator: "\n").map(String.init) {
        if line.hasPrefix("p") {
            currentPID = Int(line.dropFirst())
        } else if line.hasPrefix("n"), let pid = currentPID {
            result[pid] = String(line.dropFirst())
        }
    }

    return result
}

func portsFromLsofName(_ name: String) -> [Int] {
    let pattern = #":(\d{2,5})(?:\s|$)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return []
    }

    let range = NSRange(name.startIndex..<name.endIndex, in: name)
    return regex.matches(in: name, range: range).compactMap { match in
        guard match.numberOfRanges > 1,
              let portRange = Range(match.range(at: 1), in: name),
              let port = Int(name[portRange]),
              (1...65535).contains(port) else {
            return nil
        }

        return port
    }
}

func listeningPortsByPID() -> [Int: [Int]] {
    guard let output = runCommand("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpn"]) else {
        return [:]
    }

    var currentPID: Int?
    var result: [Int: Set<Int>] = [:]

    for line in output.split(separator: "\n").map(String.init) {
        if line.hasPrefix("p") {
            currentPID = Int(line.dropFirst())
        } else if line.hasPrefix("n"), let pid = currentPID {
            let ports = portsFromLsofName(String(line.dropFirst()))
            if !ports.isEmpty {
                result[pid, default: []].formUnion(ports)
            }
        }
    }

    return result.mapValues { Array($0).sorted() }
}

func nearestPackageRoot(from cwd: String?) -> String? {
    guard let cwd, !cwd.isEmpty else {
        return nil
    }

    let fileManager = FileManager.default
    var current = URL(fileURLWithPath: cwd).standardizedFileURL

    for _ in 0..<10 {
        let packagePath = current.appendingPathComponent("package.json").path
        if fileManager.fileExists(atPath: packagePath) {
            return current.path
        }

        let parent = current.deletingLastPathComponent()
        if parent.path == current.path {
            break
        }

        current = parent
    }

    return URL(fileURLWithPath: cwd).standardizedFileURL.path
}

func packageName(at root: String?) -> String? {
    guard let root else {
        return nil
    }

    let packageURL = URL(fileURLWithPath: root).appendingPathComponent("package.json")
    guard let data = try? Data(contentsOf: packageURL),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let name = json["name"] as? String,
          !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return nil
    }

    if let slashIndex = name.lastIndex(of: "/") {
        return String(name[name.index(after: slashIndex)...])
    }

    return name
}

func folderName(from path: String?) -> String? {
    guard let path, !path.isEmpty else {
        return nil
    }

    let name = URL(fileURLWithPath: path).lastPathComponent
    return name.isEmpty ? nil : name
}

func commandTokens(_ text: String) -> [String] {
    return text
        .split { $0 == " " || $0 == "\t" || $0 == "\n" }
        .map(String.init)
}

func commandText(for process: NodeProcess) -> String {
    return process.args.isEmpty ? process.command : process.args
}

func nextNonOptionToken(after index: Int, in tokens: [String]) -> String? {
    var currentIndex = index + 1
    while currentIndex < tokens.count {
        let token = tokens[currentIndex]
        if !token.hasPrefix("-") {
            return token
        }

        currentIndex += 1
    }

    return nil
}

func npmScriptLabel(prefix: String, tokens: [String]) -> String? {
    let lowerTokens = tokens.map { $0.lowercased() }
    if let runIndex = lowerTokens.firstIndex(of: "run"),
       let script = nextNonOptionToken(after: runIndex, in: tokens) {
        return "\(prefix) run \(script)"
    }

    if let script = tokens.dropFirst().first(where: { !$0.hasPrefix("-") && !$0.contains(".js") }) {
        return "\(prefix) \(script)"
    }

    return nil
}

func commandSummary(for process: NodeProcess) -> String {
    let text = commandText(for: process)
    let tokens = commandTokens(text)
    let lowerText = text.lowercased()
    let lowerTokens = tokens.map { $0.lowercased() }

    if lowerTokens.contains(where: { $0.contains("npm-cli.js") || ($0 as NSString).lastPathComponent == "npm" }) {
        return npmScriptLabel(prefix: "npm", tokens: tokens) ?? "npm"
    }

    if lowerTokens.contains(where: { $0.contains("pnpm.cjs") || ($0 as NSString).lastPathComponent == "pnpm" }) {
        return npmScriptLabel(prefix: "pnpm", tokens: tokens) ?? "pnpm"
    }

    if lowerTokens.contains(where: { $0.contains("yarn.js") || ($0 as NSString).lastPathComponent == "yarn" }) {
        return npmScriptLabel(prefix: "yarn", tokens: tokens) ?? "yarn"
    }

    if lowerText.contains("next") {
        return lowerText.contains("dev") ? "next dev" : "next"
    }

    if lowerText.contains("vite") {
        return "vite"
    }

    if lowerText.contains("astro") {
        return "astro"
    }

    if lowerText.contains("remix") {
        return "remix"
    }

    if lowerText.contains("nuxt") {
        return "nuxt"
    }

    if lowerText.contains("webpack") {
        return "webpack"
    }

    if lowerText.contains("nodemon") {
        return "nodemon"
    }

    if lowerText.contains("tsx") {
        return "tsx"
    }

    return process.commandName
}

func frameworkLabel(for process: NodeProcess, commandSummary: String, hasPorts: Bool) -> String {
    let text = commandText(for: process).lowercased()

    if text.contains("next") {
        return "Next.js"
    }

    if text.contains("vite") {
        return "Vite"
    }

    if text.contains("astro") {
        return "Astro"
    }

    if text.contains("remix") {
        return "Remix"
    }

    if text.contains("nuxt") {
        return "Nuxt"
    }

    if text.contains("webpack") {
        return "Webpack"
    }

    if text.contains("nodemon") {
        return "Nodemon"
    }

    if commandSummary.hasPrefix("npm") || commandSummary.hasPrefix("pnpm") || commandSummary.hasPrefix("yarn") {
        return "npm script"
    }

    return hasPorts ? "Local server" : "Node"
}

func buildProcessDisplays() -> [ProcessDisplay] {
    let processes = listNodeProcesses().sorted { $0.pid < $1.pid }
    let pids = processes.map { $0.pid }
    let cwds = processCwdsByPID(pids)
    let ports = listeningPortsByPID()

    return processes.map { process in
        let cwd = cwds[process.pid]
        let root = nearestPackageRoot(from: cwd)
        let projectName = packageName(at: root)
            ?? folderName(from: root)
            ?? folderName(from: cwd)
            ?? process.commandName
        let processPorts = ports[process.pid] ?? []
        let summary = commandSummary(for: process)

        return ProcessDisplay(
            process: process,
            cwd: cwd,
            projectRoot: root,
            projectName: projectName,
            framework: frameworkLabel(for: process, commandSummary: summary, hasPorts: !processPorts.isEmpty),
            commandSummary: summary,
            ports: processPorts
        )
    }
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
    private var cachedProcesses: [ProcessDisplay] = []
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

    private func clipped(_ value: String, limit: Int) -> String {
        if value.count <= limit {
            return value
        }

        return String(value.prefix(max(0, limit - 3))) + "..."
    }

    private func normalized(_ value: String) -> String {
        return value.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
    }

    private func tildePath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home {
            return "~"
        }

        if path.hasPrefix(home + "/") {
            return "~" + String(path.dropFirst(home.count))
        }

        return path
    }

    private func portSummary(for process: ProcessDisplay, limit: Int = 3) -> String {
        let visiblePorts = process.ports.prefix(limit).map { ":\($0)" }
        let suffix = process.ports.count > limit ? ", ..." : ""
        return visiblePorts.joined(separator: ", ") + suffix
    }

    private func rowTitle(for process: ProcessDisplay) -> String {
        let project = clipped(process.projectName, limit: 30)
        let pid = "PID \(process.process.pid)"

        if process.isLocalhostProject {
            let local = "LOCAL \(portSummary(for: process))"
            return "\(project)  \(local)  \(process.framework)  \(pid)"
        }

        let command = clipped(process.commandSummary, limit: 18)
        return "\(project)  \(command)  \(pid)"
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

    private func processCountTitle(_ count: Int, localCount: Int = 0, refreshing: Bool = false) -> String {
        if refreshing && count == 0 {
            return "Refreshing process list..."
        }

        if count == 0 {
            return "No Node.js processes running"
        }

        let processTitle = "\(count) Node.js process\(count == 1 ? "" : "es")"
        let localTitle = "\(localCount) localhost process\(localCount == 1 ? "" : "es")"
        let title = localCount > 0 ? "\(processTitle), \(localTitle)" : "\(processTitle) running"
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
            let processes = buildProcessDisplays().sorted {
                if $0.isLocalhostProject != $1.isLocalhostProject {
                    return $0.isLocalhostProject && !$1.isLocalhostProject
                }

                let nameComparison = $0.projectName.localizedCaseInsensitiveCompare($1.projectName)
                if nameComparison != .orderedSame {
                    return nameComparison == .orderedAscending
                }

                return $0.process.pid < $1.process.pid
            }

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
        let localhostProcesses = processes.filter { $0.isLocalhostProject }
        let otherProcesses = processes.filter { !$0.isLocalhostProject }

        let header = disabledItem("NodeSnoop")
        header.image = makeSpruceTreeIcon()
        menu.addItem(header)
        menu.addItem(disabledItem(processCountTitle(processes.count, localCount: localhostProcesses.count, refreshing: isRefreshing)))
        statusItem?.button?.toolTip = "NodeSnoop - \(processCountTitle(processes.count, localCount: localhostProcesses.count))"
        menu.addItem(NSMenuItem.separator())

        if processes.isEmpty && isRefreshing {
            menu.addItem(sectionHeader("Processes"))
            menu.addItem(disabledItem("Refreshing..."))
        } else if processes.isEmpty {
            menu.addItem(sectionHeader("Processes"))
            menu.addItem(disabledItem("No running Node.js processes"))
        } else {
            if !localhostProcesses.isEmpty {
                menu.addItem(sectionHeader("Localhost Projects"))
                for process in localhostProcesses {
                    menu.addItem(processMenuItem(for: process))
                }
            }

            if !localhostProcesses.isEmpty && !otherProcesses.isEmpty {
                menu.addItem(NSMenuItem.separator())
            }

            if !otherProcesses.isEmpty {
                menu.addItem(sectionHeader("Other Node Processes"))
                for process in otherProcesses {
                    menu.addItem(processMenuItem(for: process))
                }
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

    private func payload(for process: ProcessDisplay) -> ProcessMenuPayload {
        return ProcessMenuPayload(
            pid: process.process.pid,
            cwd: process.projectRoot ?? process.cwd,
            url: process.primaryURL
        )
    }

    private func processMenuItem(for process: ProcessDisplay) -> NSMenuItem {
        let item = NSMenuItem(title: rowTitle(for: process), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let itemPayload = payload(for: process)

        submenu.addItem(disabledItem(process.projectName))

        if process.isLocalhostProject {
            submenu.addItem(disabledItem("Localhost \(portSummary(for: process))"))
        }

        submenu.addItem(disabledItem("\(process.framework) - \(process.commandSummary)"))

        if let cwd = process.projectRoot ?? process.cwd {
            submenu.addItem(disabledItem(clipped(tildePath(cwd), limit: 72)))
        }

        submenu.addItem(disabledItem("PID \(process.process.pid) - Parent \(process.process.ppid) - Status \(process.process.stat)"))
        submenu.addItem(NSMenuItem.separator())

        if process.primaryURL != nil {
            let openLocalhostItem = NSMenuItem(title: "Open Localhost", action: #selector(openLocalhost(_:)), keyEquivalent: "")
            openLocalhostItem.target = self
            openLocalhostItem.representedObject = itemPayload
            submenu.addItem(openLocalhostItem)

            let copyURLItem = NSMenuItem(title: "Copy Localhost URL", action: #selector(copyLocalhostURL(_:)), keyEquivalent: "")
            copyURLItem.target = self
            copyURLItem.representedObject = itemPayload
            submenu.addItem(copyURLItem)
        }

        if itemPayload.cwd != nil {
            let openItem = NSMenuItem(title: "Open Terminal at Project", action: #selector(openProcessTerminal(_:)), keyEquivalent: "")
            openItem.target = self
            openItem.representedObject = itemPayload
            submenu.addItem(openItem)

            let copyPathItem = NSMenuItem(title: "Copy Project Path", action: #selector(copyProjectPath(_:)), keyEquivalent: "")
            copyPathItem.target = self
            copyPathItem.representedObject = itemPayload
            submenu.addItem(copyPathItem)
        }

        let copyItem = NSMenuItem(title: "Copy PID", action: #selector(copyProcessPID(_:)), keyEquivalent: "")
        copyItem.target = self
        copyItem.representedObject = itemPayload
        submenu.addItem(copyItem)

        submenu.addItem(NSMenuItem.separator())

        let killItem = NSMenuItem(title: "Kill Process", action: #selector(killMenuItemProcess(_:)), keyEquivalent: "")
        killItem.target = self
        killItem.representedObject = itemPayload
        submenu.addItem(killItem)

        item.submenu = submenu
        item.toolTip = normalized(commandText(for: process.process))
        return item
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    @objc private func openLocalhost(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? ProcessMenuPayload,
              let urlString = payload.url,
              let url = URL(string: urlString) else {
            NSSound.beep()
            return
        }

        NSWorkspace.shared.open(url)
    }

    @objc private func openProcessTerminal(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? ProcessMenuPayload else {
            return
        }

        let pid = payload.pid
        let cachedCwd = payload.cwd

        processQueue.async {
            guard let cwd = cachedCwd ?? processCwd(pid: pid) else {
                DispatchQueue.main.async {
                    NSSound.beep()
                }
                return
            }

            openTerminal(at: cwd)
        }
    }

    @objc private func copyLocalhostURL(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? ProcessMenuPayload,
              let url = payload.url else {
            return
        }

        copyToPasteboard(url)
    }

    @objc private func copyProjectPath(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? ProcessMenuPayload,
              let cwd = payload.cwd else {
            return
        }

        copyToPasteboard(cwd)
    }

    @objc private func copyProcessPID(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? ProcessMenuPayload else {
            return
        }

        copyToPasteboard(String(payload.pid))
    }

    @objc private func killMenuItemProcess(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? ProcessMenuPayload else {
            return
        }

        let pid = payload.pid
        cachedProcesses.removeAll { $0.process.pid == pid }
        renderMenu()

        processQueue.async { [weak self] in
            killProcess(pid: pid)

            DispatchQueue.main.async {
                self?.refreshProcesses(force: true)
            }
        }
    }

    @objc private func killAllProcesses(_ sender: NSMenuItem) {
        let pids = cachedProcesses.map { $0.process.pid }
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
