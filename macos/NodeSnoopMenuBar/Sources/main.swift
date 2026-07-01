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
    let toolLabel: String?
    let ports: [Int]
    let inferredPorts: [Int]

    var isLocalhostProject: Bool {
        return !visiblePorts.isEmpty
    }

    var isDevelopmentTool: Bool {
        return toolLabel != nil
    }

    var primaryURL: String? {
        guard let port = visiblePorts.first else {
            return nil
        }

        return "http://localhost:\(port)"
    }

    var visiblePorts: [Int] {
        return ports.isEmpty ? inferredPorts : ports
    }

    var usesInferredPorts: Bool {
        return ports.isEmpty && !inferredPorts.isEmpty
    }
}

struct ProjectDisplay {
    let id: String
    let projectRoot: String?
    let cwd: String?
    let projectName: String
    let framework: String
    let commandSummary: String
    let toolLabel: String?
    let ports: [Int]
    let inferredPorts: [Int]
    let processes: [ProcessDisplay]

    var isLocalhostProject: Bool {
        return !visiblePorts.isEmpty && !isDevelopmentTool
    }

    var isDevelopmentTool: Bool {
        return toolLabel != nil
    }

    var primaryURL: String? {
        guard let port = visiblePorts.first else {
            return nil
        }

        return "http://localhost:\(port)"
    }

    var visiblePorts: [Int] {
        return ports.isEmpty ? inferredPorts : ports
    }

    var usesInferredPorts: Bool {
        return ports.isEmpty && !inferredPorts.isEmpty
    }

    var processCount: Int {
        return processes.count
    }

    var pids: [Int] {
        return processes.map { $0.process.pid }
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

final class ProjectMenuPayload: NSObject {
    let pids: [Int]
    let cwd: String?
    let url: String?

    init(pids: [Int], cwd: String?, url: String?) {
        self.pids = pids
        self.cwd = cwd
        self.url = url
    }
}

enum OpenAtLoginStatus {
    case disabled
    case enabled
    case differentAppCopy
}

let loginAgentLabel = "dev.nodesnoop.menubar.login-item"
let loginAgentFileName = "\(loginAgentLabel).plist"

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

func listProcesses() -> [NodeProcess] {
    guard let output = runCommand("/bin/ps", ["-axo", "pid=,ppid=,stat=,comm=,args="]) else {
        return []
    }

    return output
        .split(separator: "\n")
        .compactMap { parsePSLine(String($0)) }
}

func listNodeProcesses() -> [NodeProcess] {
    return listProcesses()
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

func childrenByParent(from processes: [NodeProcess]) -> [Int: [Int]] {
    var result: [Int: [Int]] = [:]

    for process in processes {
        result[process.ppid, default: []].append(process.pid)
    }

    return result
}

func descendantPIDs(of pid: Int, childrenByParent: [Int: [Int]]) -> Set<Int> {
    var result: Set<Int> = []
    var stack = childrenByParent[pid] ?? []

    while let childPID = stack.popLast() {
        guard !result.contains(childPID) else {
            continue
        }

        result.insert(childPID)
        stack.append(contentsOf: childrenByParent[childPID] ?? [])
    }

    return result
}

func detectedPorts(for pid: Int, childrenByParent: [Int: [Int]], listeningPorts: [Int: [Int]]) -> [Int] {
    var relatedPIDs = descendantPIDs(of: pid, childrenByParent: childrenByParent)
    relatedPIDs.insert(pid)

    return Array(Set(relatedPIDs.flatMap { listeningPorts[$0] ?? [] })).sorted()
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

func validPort(_ value: String) -> Int? {
    guard let port = Int(value), (1...65535).contains(port) else {
        return nil
    }

    return port
}

func explicitPortsFromCommand(_ text: String) -> [Int] {
    let tokens = commandTokens(text)
    var ports: Set<Int> = []

    for (index, token) in tokens.enumerated() {
        if token == "--port" || token == "-p" {
            if index + 1 < tokens.count, let port = validPort(tokens[index + 1]) {
                ports.insert(port)
            }
        } else if token.hasPrefix("--port=") {
            if let port = validPort(String(token.dropFirst("--port=".count))) {
                ports.insert(port)
            }
        } else if token.hasPrefix("-p"), token.count > 2 {
            if let port = validPort(String(token.dropFirst(2))) {
                ports.insert(port)
            }
        } else if token.hasPrefix("PORT=") {
            if let port = validPort(String(token.dropFirst("PORT=".count))) {
                ports.insert(port)
            }
        }
    }

    return Array(ports).sorted()
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

func knownToolLabel(for process: NodeProcess, commandSummary: String) -> String? {
    let text = "\(process.command) \(commandText(for: process)) \(commandSummary)".lowercased()
    let tokens = commandTokens(text).map { ($0 as NSString).lastPathComponent.lowercased() }

    func containsToken(_ needle: String) -> Bool {
        return tokens.contains(needle) || tokens.contains("\(needle).js") || tokens.contains("\(needle).cjs")
    }

    if text.contains("claude-code") {
        return "Claude Code"
    }

    if containsToken("claude") || text.contains("/claude/") {
        return "Claude"
    }

    if containsToken("codex") || text.contains("/codex/") {
        return "Codex"
    }

    if text.contains("typescript-language-server") {
        return "TypeScript LS"
    }

    if containsToken("tsserver") || text.contains("tsserver.js") {
        return "tsserver"
    }

    if containsToken("eslint") || text.contains("eslint.js") {
        return "ESLint"
    }

    if containsToken("prettier") || text.contains("prettier/index") {
        return "Prettier"
    }

    if text.contains("visual studio code") || text.contains("/vscode/") || text.contains(".vscode") {
        return "VS Code"
    }

    if containsToken("cursor") || text.contains("/cursor/") {
        return "Cursor"
    }

    return nil
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

func inferredDefaultPorts(for process: NodeProcess, framework: String, commandSummary: String, knownPorts: [Int]) -> [Int] {
    guard knownPorts.isEmpty else {
        return []
    }

    let text = "\(commandText(for: process)) \(commandSummary)".lowercased()

    if framework == "Next.js", text.contains("dev") {
        return [3000]
    }

    if framework == "Vite", text.contains("vite") {
        return [5173]
    }

    if framework == "Astro", text.contains("astro") {
        return [4321]
    }

    if framework == "Nuxt", text.contains("nuxt") {
        return [3000]
    }

    if framework == "Remix", text.contains("remix") {
        return [3000]
    }

    if framework == "Webpack", text.contains("serve") {
        return [8080]
    }

    return []
}

func buildProcessDisplays() -> [ProcessDisplay] {
    let allProcesses = listProcesses()
    let processes = allProcesses
        .filter { $0.commandName == "node" || $0.commandName == "nodejs" }
        .sorted { $0.pid < $1.pid }
    let pids = processes.map { $0.pid }
    let cwds = processCwdsByPID(pids)
    let listeningPorts = listeningPortsByPID()
    let childMap = childrenByParent(from: allProcesses)

    return processes.map { process in
        let cwd = cwds[process.pid]
        let root = nearestPackageRoot(from: cwd)
        let projectName = packageName(at: root)
            ?? folderName(from: root)
            ?? folderName(from: cwd)
            ?? process.commandName
        let detectedProcessPorts = detectedPorts(for: process.pid, childrenByParent: childMap, listeningPorts: listeningPorts)
        let summary = commandSummary(for: process)
        let toolLabel = knownToolLabel(for: process, commandSummary: summary)
        let explicitPorts = explicitPortsFromCommand(commandText(for: process))
        let processPorts = Array(Set(detectedProcessPorts + explicitPorts)).sorted()
        let framework = toolLabel ?? frameworkLabel(for: process, commandSummary: summary, hasPorts: !processPorts.isEmpty)
        let inferredPorts = toolLabel == nil
            ? inferredDefaultPorts(for: process, framework: framework, commandSummary: summary, knownPorts: processPorts)
            : []

        return ProcessDisplay(
            process: process,
            cwd: cwd,
            projectRoot: root,
            projectName: projectName,
            framework: framework,
            commandSummary: summary,
            toolLabel: toolLabel,
            ports: processPorts,
            inferredPorts: inferredPorts
        )
    }
}

func processCountText(_ count: Int) -> String {
    return "\(count) Node process\(count == 1 ? "" : "es")"
}

func preferredFramework(from processes: [ProcessDisplay]) -> String {
    if let toolLabel = processes.first(where: { $0.toolLabel != nil })?.toolLabel {
        return toolLabel
    }

    let priority = ["Next.js", "Vite", "Astro", "Remix", "Nuxt", "Webpack", "Local server", "npm script", "Nodemon", "Node"]
    let frameworks = Set(processes.map { $0.framework })

    for framework in priority where frameworks.contains(framework) {
        return framework
    }

    return processes.first?.framework ?? "Node"
}

func preferredCommandSummary(from processes: [ProcessDisplay]) -> String {
    let summaries = processes.map { $0.commandSummary }
    let uniqueSummaries = Array(Set(summaries)).sorted()

    if uniqueSummaries.count == 1, let summary = uniqueSummaries.first {
        return summary
    }

    let priorityPrefixes = ["npm run", "pnpm", "yarn", "next", "vite", "astro", "remix", "nuxt", "tsx", "nodemon"]
    for prefix in priorityPrefixes {
        if let summary = summaries.first(where: { $0.lowercased().hasPrefix(prefix) }) {
            return summary
        }
    }

    return processes.first?.commandSummary ?? "node"
}

func buildProjectDisplays() -> [ProjectDisplay] {
    let processDisplays = buildProcessDisplays()
    var grouped: [String: [ProcessDisplay]] = [:]

    for process in processDisplays {
        let baseKey = process.projectRoot ?? process.cwd ?? "pid:\(process.process.pid)"
        let key = process.toolLabel.map { "tool:\($0):\(baseKey)" } ?? baseKey
        grouped[key, default: []].append(process)
    }

    return grouped.map { key, group in
        let processes = group.sorted { $0.process.pid < $1.process.pid }
        let first = processes[0]
        let ports = Array(Set(processes.flatMap { $0.ports })).sorted()
        let inferredPorts = ports.isEmpty ? Array(Set(processes.flatMap { $0.inferredPorts })).sorted() : []
        let toolLabel = first.toolLabel

        return ProjectDisplay(
            id: key,
            projectRoot: first.projectRoot,
            cwd: first.projectRoot ?? first.cwd,
            projectName: first.projectName,
            framework: preferredFramework(from: processes),
            commandSummary: preferredCommandSummary(from: processes),
            toolLabel: toolLabel,
            ports: ports,
            inferredPorts: inferredPorts,
            processes: processes
        )
    }
}

func loginAgentURL() -> URL {
    return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library")
        .appendingPathComponent("LaunchAgents")
        .appendingPathComponent(loginAgentFileName)
}

func currentAppBundlePath() -> String {
    return Bundle.main.bundleURL.standardizedFileURL.path
}

func loginAgentAppPath() -> String? {
    let url = loginAgentURL()
    guard let data = try? Data(contentsOf: url),
          let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
          let arguments = plist["ProgramArguments"] as? [String],
          let appPath = arguments.last else {
        return nil
    }

    return URL(fileURLWithPath: appPath).standardizedFileURL.path
}

func openAtLoginStatus() -> OpenAtLoginStatus {
    guard let appPath = loginAgentAppPath() else {
        return .disabled
    }

    return appPath == currentAppBundlePath() ? .enabled : .differentAppCopy
}

func setOpenAtLoginEnabled(_ enabled: Bool) throws {
    let fileManager = FileManager.default
    let url = loginAgentURL()

    if !enabled {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        return
    }

    let launchAgentsURL = url.deletingLastPathComponent()
    try fileManager.createDirectory(at: launchAgentsURL, withIntermediateDirectories: true)

    let plist: [String: Any] = [
        "Label": loginAgentLabel,
        "ProgramArguments": [
            "/usr/bin/open",
            "-g",
            currentAppBundlePath()
        ],
        "RunAtLoad": true,
        "KeepAlive": false,
        "LimitLoadToSessionType": "Aqua"
    ]

    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: url, options: .atomic)
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
    private var cachedProjects: [ProjectDisplay] = []
    private var isRefreshing = false
    private var lastRefreshDate: Date?
    private var openAtLoginMessage: String?

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

    private func portSummary(for ports: [Int], limit: Int = 3) -> String {
        let visiblePorts = ports.prefix(limit).map { ":\($0)" }
        let suffix = ports.count > limit ? ", ..." : ""
        return visiblePorts.joined(separator: ", ") + suffix
    }

    private func rowTitle(for project: ProjectDisplay) -> String {
        let projectName = clipped(project.projectName, limit: 34)
        let count = processCountText(project.processCount)

        if project.isDevelopmentTool {
            let tool = project.toolLabel ?? project.framework
            return "\(tool)  \(projectName)  \(count)"
        }

        if project.isLocalhostProject {
            let localPrefix = project.usesInferredPorts ? "LIKELY" : "LOCAL"
            let local = "\(localPrefix) \(portSummary(for: project.visiblePorts))"
            return "\(projectName)  \(local)  \(project.framework)  \(count)"
        }

        let command = clipped(project.commandSummary, limit: 18)
        return "\(projectName)  \(command)  \(count)"
    }

    private func processRowTitle(for process: ProcessDisplay) -> String {
        let command = clipped(process.commandSummary, limit: 24)
        return "PID \(process.process.pid)  \(command)"
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

    private func projectCountTitle(_ projectCount: Int, processCount: Int, localCount: Int = 0, toolCount: Int = 0, refreshing: Bool = false) -> String {
        if refreshing && processCount == 0 {
            return "Refreshing process list..."
        }

        if processCount == 0 {
            return "No Node.js processes running"
        }

        let projectTitle = "\(projectCount) project\(projectCount == 1 ? "" : "s")"
        let nodeTitle = "\(processCount) Node process\(processCount == 1 ? "" : "es")"
        let localTitle = "\(localCount) localhost project\(localCount == 1 ? "" : "s")"
        let toolTitle = "\(toolCount) tool\(toolCount == 1 ? "" : "s")"
        let extras = [
            localCount > 0 ? localTitle : nil,
            toolCount > 0 ? toolTitle : nil
        ].compactMap { $0 }
        let title = ([projectTitle, nodeTitle] + extras).joined(separator: ", ")
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
            let projects = buildProjectDisplays().sorted {
                if $0.isLocalhostProject != $1.isLocalhostProject {
                    return $0.isLocalhostProject && !$1.isLocalhostProject
                }

                let nameComparison = $0.projectName.localizedCaseInsensitiveCompare($1.projectName)
                if nameComparison != .orderedSame {
                    return nameComparison == .orderedAscending
                }

                return ($0.pids.first ?? 0) < ($1.pids.first ?? 0)
            }

            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                self.cachedProjects = projects
                self.lastRefreshDate = Date()
                self.isRefreshing = false
                self.renderMenu()
            }
        }
    }

    private func renderMenu() {
        menu.removeAllItems()
        let projects = cachedProjects
        let appProjects = projects.filter { !$0.isDevelopmentTool }
        let localhostProjects = projects.filter { $0.isLocalhostProject }
        let toolProjects = projects.filter { $0.isDevelopmentTool }
        let otherProjects = appProjects.filter { !$0.isLocalhostProject }
        let processCount = projects.reduce(0) { $0 + $1.processCount }

        let header = disabledItem("NodeSnoop")
        header.image = makeSpruceTreeIcon()
        menu.addItem(header)
        menu.addItem(disabledItem(projectCountTitle(appProjects.count, processCount: processCount, localCount: localhostProjects.count, toolCount: toolProjects.count, refreshing: isRefreshing)))
        statusItem?.button?.toolTip = "NodeSnoop - \(projectCountTitle(appProjects.count, processCount: processCount, localCount: localhostProjects.count, toolCount: toolProjects.count))"
        menu.addItem(NSMenuItem.separator())

        if projects.isEmpty && isRefreshing {
            menu.addItem(sectionHeader("Projects"))
            menu.addItem(disabledItem("Refreshing..."))
        } else if projects.isEmpty {
            menu.addItem(sectionHeader("Projects"))
            menu.addItem(disabledItem("No running Node.js processes"))
        } else {
            if !localhostProjects.isEmpty {
                menu.addItem(sectionHeader("Localhost Projects"))
                for project in localhostProjects {
                    menu.addItem(projectMenuItem(for: project))
                }
            }

            if !localhostProjects.isEmpty && !otherProjects.isEmpty {
                menu.addItem(NSMenuItem.separator())
            }

            if !otherProjects.isEmpty {
                menu.addItem(sectionHeader("Other Projects"))
                for project in otherProjects {
                    menu.addItem(projectMenuItem(for: project))
                }
            }

            if !toolProjects.isEmpty {
                if !localhostProjects.isEmpty || !otherProjects.isEmpty {
                    menu.addItem(NSMenuItem.separator())
                }

                menu.addItem(sectionHeader("Development Tools"))
                for project in toolProjects {
                    menu.addItem(projectMenuItem(for: project))
                }
            }
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(sectionHeader("Bulk Actions"))

        let killAllItem = NSMenuItem(title: "Kill All Node.js Processes", action: #selector(killAllProcesses(_:)), keyEquivalent: "")
        killAllItem.target = self
        killAllItem.isEnabled = !projects.isEmpty
        menu.addItem(killAllItem)

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refresh(_:)), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(sectionHeader("Application"))

        let loginStatus = openAtLoginStatus()
        let openAtLoginItem = NSMenuItem(title: openAtLoginTitle(for: loginStatus), action: #selector(toggleOpenAtLogin(_:)), keyEquivalent: "")
        openAtLoginItem.target = self
        switch loginStatus {
        case .enabled:
            openAtLoginItem.state = .on
        case .differentAppCopy:
            openAtLoginItem.state = .mixed
        case .disabled:
            openAtLoginItem.state = .off
        }
        menu.addItem(openAtLoginItem)

        if let openAtLoginMessage {
            menu.addItem(disabledItem(openAtLoginMessage))
        }

        let quitItem = NSMenuItem(title: "Quit NodeSnoop", action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func openAtLoginTitle(for status: OpenAtLoginStatus) -> String {
        switch status {
        case .disabled, .enabled:
            return "Open at Login"
        case .differentAppCopy:
            return "Open at Login (Different Copy)"
        }
    }

    private func payload(for project: ProjectDisplay) -> ProjectMenuPayload {
        return ProjectMenuPayload(
            pids: project.pids,
            cwd: project.cwd,
            url: project.primaryURL
        )
    }

    private func payload(for process: ProcessDisplay) -> ProcessMenuPayload {
        return ProcessMenuPayload(
            pid: process.process.pid,
            cwd: process.projectRoot ?? process.cwd,
            url: process.primaryURL
        )
    }

    private func projectMenuItem(for project: ProjectDisplay) -> NSMenuItem {
        let item = NSMenuItem(title: rowTitle(for: project), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let itemPayload = payload(for: project)

        submenu.addItem(disabledItem(project.projectName))

        if project.isDevelopmentTool {
            submenu.addItem(disabledItem(project.toolLabel ?? project.framework))
        } else if project.isLocalhostProject {
            let localTitle = project.usesInferredPorts ? "Likely localhost" : "Localhost"
            submenu.addItem(disabledItem("\(localTitle) \(portSummary(for: project.visiblePorts))"))
        } else {
            submenu.addItem(disabledItem("No detected localhost port"))
        }

        submenu.addItem(disabledItem("\(project.framework) - \(project.commandSummary)"))
        submenu.addItem(disabledItem(processCountText(project.processCount)))

        if let cwd = project.cwd {
            submenu.addItem(disabledItem(clipped(tildePath(cwd), limit: 72)))
        }

        submenu.addItem(NSMenuItem.separator())

        if project.primaryURL != nil {
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

        let copyPIDsItem = NSMenuItem(title: "Copy Process IDs", action: #selector(copyProjectPIDs(_:)), keyEquivalent: "")
        copyPIDsItem.target = self
        copyPIDsItem.representedObject = itemPayload
        submenu.addItem(copyPIDsItem)

        submenu.addItem(NSMenuItem.separator())

        let stopTitle = project.isDevelopmentTool ? "Stop Tool Processes" : "Stop Project"
        let stopItem = NSMenuItem(title: stopTitle, action: #selector(stopProject(_:)), keyEquivalent: "")
        stopItem.target = self
        stopItem.representedObject = itemPayload
        submenu.addItem(stopItem)

        submenu.addItem(NSMenuItem.separator())
        submenu.addItem(sectionHeader("Processes"))

        for process in project.processes {
            submenu.addItem(processDetailMenuItem(for: process))
        }

        item.submenu = submenu
        item.toolTip = project.cwd.map(tildePath) ?? project.projectName
        return item
    }

    private func processDetailMenuItem(for process: ProcessDisplay) -> NSMenuItem {
        let item = NSMenuItem(title: processRowTitle(for: process), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let itemPayload = payload(for: process)

        submenu.addItem(disabledItem("PID \(process.process.pid)"))
        submenu.addItem(disabledItem("Parent PID \(process.process.ppid) - Status \(process.process.stat)"))
        submenu.addItem(disabledItem(clipped(normalized(commandText(for: process.process)), limit: 78)))
        submenu.addItem(NSMenuItem.separator())

        let copyItem = NSMenuItem(title: "Copy PID", action: #selector(copyProcessPID(_:)), keyEquivalent: "")
        copyItem.target = self
        copyItem.representedObject = itemPayload
        submenu.addItem(copyItem)

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
        let urlString: String?
        if let projectPayload = sender.representedObject as? ProjectMenuPayload {
            urlString = projectPayload.url
        } else if let processPayload = sender.representedObject as? ProcessMenuPayload {
            urlString = processPayload.url
        } else {
            urlString = nil
        }

        guard let urlString,
              let url = URL(string: urlString) else {
            NSSound.beep()
            return
        }

        NSWorkspace.shared.open(url)
    }

    @objc private func openProcessTerminal(_ sender: NSMenuItem) {
        let pid: Int?
        let cachedCwd: String?

        if let projectPayload = sender.representedObject as? ProjectMenuPayload {
            pid = projectPayload.pids.first
            cachedCwd = projectPayload.cwd
        } else if let processPayload = sender.representedObject as? ProcessMenuPayload {
            pid = processPayload.pid
            cachedCwd = processPayload.cwd
        } else {
            pid = nil
            cachedCwd = nil
        }

        guard let pid else {
            NSSound.beep()
            return
        }

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
        let url: String?
        if let projectPayload = sender.representedObject as? ProjectMenuPayload {
            url = projectPayload.url
        } else if let processPayload = sender.representedObject as? ProcessMenuPayload {
            url = processPayload.url
        } else {
            url = nil
        }

        guard let url else {
            return
        }

        copyToPasteboard(url)
    }

    @objc private func copyProjectPath(_ sender: NSMenuItem) {
        let cwd: String?
        if let projectPayload = sender.representedObject as? ProjectMenuPayload {
            cwd = projectPayload.cwd
        } else if let processPayload = sender.representedObject as? ProcessMenuPayload {
            cwd = processPayload.cwd
        } else {
            cwd = nil
        }

        guard let cwd else {
            return
        }

        copyToPasteboard(cwd)
    }

    @objc private func copyProjectPIDs(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? ProjectMenuPayload else {
            return
        }

        copyToPasteboard(payload.pids.map(String.init).joined(separator: " "))
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
        cachedProjects = cachedProjects.compactMap { project in
            let remainingProcesses = project.processes.filter { $0.process.pid != pid }
            if remainingProcesses.isEmpty {
                return nil
            }

            let remainingPorts = Array(Set(remainingProcesses.flatMap { $0.ports })).sorted()
            let remainingInferredPorts = remainingPorts.isEmpty
                ? Array(Set(remainingProcesses.flatMap { $0.inferredPorts })).sorted()
                : []
            return ProjectDisplay(
                id: project.id,
                projectRoot: project.projectRoot,
                cwd: project.cwd,
                projectName: project.projectName,
                framework: preferredFramework(from: remainingProcesses),
                commandSummary: preferredCommandSummary(from: remainingProcesses),
                toolLabel: project.toolLabel,
                ports: remainingPorts,
                inferredPorts: remainingInferredPorts,
                processes: remainingProcesses
            )
        }
        renderMenu()

        processQueue.async { [weak self] in
            killProcess(pid: pid)

            DispatchQueue.main.async {
                self?.refreshProcesses(force: true)
            }
        }
    }

    @objc private func stopProject(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? ProjectMenuPayload else {
            return
        }

        let pids = payload.pids
        cachedProjects.removeAll { project in
            !Set(project.pids).isDisjoint(with: pids)
        }
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

    @objc private func killAllProcesses(_ sender: NSMenuItem) {
        let pids = cachedProjects.flatMap { $0.pids }
        cachedProjects = []
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

    @objc private func toggleOpenAtLogin(_ sender: NSMenuItem) {
        let status = openAtLoginStatus()

        do {
            switch status {
            case .enabled:
                try setOpenAtLoginEnabled(false)
                openAtLoginMessage = nil
            case .disabled, .differentAppCopy:
                try setOpenAtLoginEnabled(true)
                openAtLoginMessage = nil
            }
        } catch {
            NSSound.beep()
            openAtLoginMessage = "Open at Login failed: \(error.localizedDescription)"
        }

        renderMenu()
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
