// Awakening — macOS 메뉴바에서 시스템 휴면을 제어하는 앱.
// 전원 설정은 건드리지 않고 IOKit 전원 어서션(assertion)만 사용하므로,
// 앱을 끄거나 OFF로 두면 즉시 원래 휴면 동작으로 돌아간다.

import AppKit
import IOKit.pwr_mgt

// MARK: - 휴면 차단

/// 시스템 유휴 휴면을 막는 전원 어서션을 관리한다.
/// 디스플레이는 평소처럼 꺼지게 두고, 시스템(네트워크·프로세스)만 깨워둔다.
final class SleepBlocker {
    private var assertionID: IOPMAssertionID = 0
    private(set) var isActive = false

    func set(_ on: Bool) {
        guard on != isActive else { return }
        if on {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Awakening: 원격 작업을 위해 휴면 방지" as CFString,
                &id
            )
            if result == kIOReturnSuccess {
                assertionID = id
                isActive = true
            }
        } else {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
            isActive = false
        }
    }
}

// MARK: - claude 프로세스 감지

enum ClaudeDetector {
    /// Claude Code CLI(`claude`)가 실행 중인지 확인한다.
    static func isRunning() -> Bool {
        // comm 은 실행 파일 전체 경로를 공백까지 그대로 준다.
        // 데스크톱 앱이 띄우는 claude 는 "Application Support" 아래에 있어 args 를 공백으로 자르면 놓친다.
        let programs = psLines("comm=")
        if programs.contains(where: { basename(Substring($0)) == "claude" }) { return true }
        return psLines("args=").contains { isClaude($0) }
    }

    private static func psLines(_ format: String) -> [String] {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-axww", "-o", format]
        let pipe = Pipe()
        ps.standardOutput = pipe
        ps.standardError = FileHandle.nullDevice
        do {
            try ps.run()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()

        let output = String(decoding: data, as: UTF8.self)
        return output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// 네이티브 설치(`claude ...`)와 npm 설치(`node .../claude ...`)를 모두 잡는다.
    /// Claude 데스크톱 앱(`.../MacOS/Claude`)은 대소문자가 달라 제외된다.
    private static func isClaude(_ line: String) -> Bool {
        let args = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard let first = args.first else { return false }
        let program = basename(first)
        if program == "claude" { return true }
        if program == "node", args.count > 1 {
            let script = String(args[1])
            return basename(args[1]) == "claude" || script.contains("@anthropic-ai/claude-code")
        }
        return false
    }

    private static func basename(_ path: Substring) -> String {
        (String(path) as NSString).lastPathComponent
    }
}

// MARK: - 로그인 감시

/// 원격 작업이 끊기는 주원인인 로그인 만료를 감시한다.
/// - CLI 로그인: `claude auth status --text` 에 "Login:" 줄(만료 등)이 나오거나 로그인이 없으면 문제.
/// - 데스크톱 앱 로그인: 앱 로그의 마지막 기록이 session_stale_relogin 실패면 문제.
enum LoginWatcher {
    static func problems() -> [String] {
        var found: [String] = []
        if let cli = cliProblem() { found.append(cli) }
        if desktopNeedsRelogin() { found.append("데스크톱 앱 로그인 만료 — Claude 앱에서 다시 로그인") }
        return found
    }

    private static func cliProblem() -> String? {
        let home = NSHomeDirectory()
        let claude = home + "/.local/bin/claude"
        guard FileManager.default.isExecutableFile(atPath: claude) else { return nil }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: claude)
        p.arguments = ["auth", "status", "--text"]
        p.environment = ["HOME": home, "USER": NSUserName(), "PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()

        let out = String(decoding: data, as: UTF8.self)
        if out.contains("Not logged in") || out.contains("Login:") {
            return "CLI 로그인 만료 — 터미널에서 claude auth login"
        }
        return nil
    }

    private static func desktopNeedsRelogin() -> Bool {
        let path = NSHomeDirectory() + "/Library/Logs/Claude/main.log"
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 2_000_000 ? size - 2_000_000 : 0)
        let tail = String(decoding: handle.readDataToEndOfFile(), as: UTF8.self)

        // 다시 로그인하면 앱이 "clearing latched session_stale_relogin" 을 남긴다.
        guard let failed = tail.range(of: "session_stale_relogin", options: .backwards) else { return false }
        if let cleared = tail.range(of: "clearing latched session_stale_relogin", options: .backwards),
           cleared.lowerBound >= tail.lineRange(for: failed).lowerBound {
            return false
        }
        return true
    }
}

// MARK: - 메뉴바 앱

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum Key {
        static let manualOn = "manualOn"
        static let autoMode = "autoMode"
    }

    private let defaults = UserDefaults.standard
    private let blocker = SleepBlocker()
    private var statusItem: NSStatusItem!
    private var timer: Timer?

    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let manualItem = NSMenuItem(title: "수동으로 깨어있기", action: #selector(toggleManual), keyEquivalent: "")
    private let autoItem = NSMenuItem(title: "claude 실행 중일 때 자동 유지", action: #selector(toggleAuto), keyEquivalent: "")

    private let loginLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var loginTimer: Timer?
    private var loginProblems: [String] = []

    private var claudeRunning = false

    private var manualOn: Bool {
        get { defaults.bool(forKey: Key.manualOn) }
        set { defaults.set(newValue, forKey: Key.manualOn) }
    }

    private var autoMode: Bool {
        get { defaults.bool(forKey: Key.autoMode) }
        set { defaults.set(newValue, forKey: Key.autoMode) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: [Key.manualOn: false, Key.autoMode: true])

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let menu = NSMenu()
        statusLine.isEnabled = false
        manualItem.target = self
        autoItem.target = self
        loginLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(loginLine)
        menu.addItem(.separator())
        menu.addItem(manualItem)
        menu.addItem(autoItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        timer = Timer.scheduledTimer(timeInterval: 5, target: self, selector: #selector(poll), userInfo: nil, repeats: true)
        poll()

        // 로그인 확인은 claude 를 띄우므로 10분마다만 한다.
        loginTimer = Timer.scheduledTimer(timeInterval: 600, target: self, selector: #selector(checkLogin), userInfo: nil, repeats: true)
        checkLogin()
    }

    @objc private func checkLogin() {
        DispatchQueue.global(qos: .utility).async {
            let problems = LoginWatcher.problems()
            DispatchQueue.main.async {
                let newOnes = problems.filter { !self.loginProblems.contains($0) }
                self.loginProblems = problems
                if !newOnes.isEmpty { self.alert(newOnes) }
                self.apply()
            }
        }
    }

    /// 새로 생긴 로그인 문제를 알림 센터에 띄운다(실행 권한 없이 쓰려고 osascript 사용).
    private func alert(_ problems: [String]) {
        let text = problems.joined(separator: " / ").replacingOccurrences(of: "\"", with: "'")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "display notification \"\(text)\" with title \"Awakening: 원격 작업이 끊길 수 있음\" sound name \"Basso\""]
        try? p.run()
    }

    func applicationWillTerminate(_ notification: Notification) {
        blocker.set(false)
    }

    @objc private func poll() {
        claudeRunning = autoMode && ClaudeDetector.isRunning()
        apply()
    }

    @objc private func toggleManual() {
        manualOn.toggle()
        apply()
    }

    @objc private func toggleAuto() {
        autoMode.toggle()
        poll()
    }

    private func apply() {
        let awake = manualOn || claudeRunning
        blocker.set(awake)

        manualItem.state = manualOn ? .on : .off
        autoItem.state = autoMode ? .on : .off

        if manualOn {
            statusLine.title = "깨어있음 — 수동"
        } else if claudeRunning {
            statusLine.title = "깨어있음 — claude 실행 중"
        } else if autoMode {
            statusLine.title = "휴면 허용 — claude 대기 중"
        } else {
            statusLine.title = "휴면 허용"
        }

        if loginProblems.isEmpty {
            loginLine.title = "로그인 정상"
        } else {
            loginLine.title = "⚠ " + loginProblems.joined(separator: "\n⚠ ")
        }

        let symbol = !loginProblems.isEmpty ? "exclamationmark.triangle.fill"
            : blocker.isActive ? "sun.max.fill" : "moon.zzz"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: statusLine.title)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = "Awakening: \(statusLine.title)"
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
