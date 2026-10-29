import AppKit
import Foundation

// Read Apple's reports after a crash, rather than installing another crash handler
// in the engine. Only a small, locally classified event ever leaves this machine.
final class CrashReporting {
    #if ZKMACOS_RELEASE_REPORTING
    static let releaseBuild = true
    #else
    static let releaseBuild = false
    #endif
    static let dsn = "https://98da4a770fee05a7a1aa6502e809ba60@o4507833886834688.ingest.us.sentry.io/4512337894899712"
    static let endpoint = URL(string: "https://o4507833886834688.ingest.us.sentry.io/api/4512337894899712/envelope/")!
    let data: URL
    let bundle: URL
    let defaults: UserDefaults
    let disabled: Bool
    let queue = DispatchQueue(label: "org.zerok.macos.reports", qos: .utility)
    private let session: URLSession
    private let prompts = DispatchGroup()
    private var logOffsets: [String: UInt64] = [:]
    private var previousLogs: [String: Data] = [:]
    private var previousLogDates: [String: Date] = [:]
    private let launchedAt = Date()
    private var manualReportOpen = false
    private static let logs = ["infolog.txt", "log/launcher.log", "log/engine-launch.log"]

    init(data: URL, bundle: URL = Bundle.main.bundleURL, defaults: UserDefaults = .standard,
         configuration: URLSessionConfiguration = .ephemeral) {
        self.data = data
        self.bundle = bundle
        self.defaults = defaults
        disabled = !Self.releaseBuild || Self.configuration(data: data, key: "MacDisableAllTelemetry")
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 10
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration)
        if disabled || !defaults.bool(forKey: "MacOSLastBuildWasRelease") || defaults.object(forKey: "MacOSReportsSince") == nil {
            defaults.set(Date(), forKey: "MacOSReportsSince")
        }
        defaults.set(Self.releaseBuild, forKey: "MacOSLastBuildWasRelease")
        baselineLogs()
        try? FileManager.default.removeItem(at: data.appendingPathComponent("macos-report-screenshot"))
        if !disabled {
            for name in Self.logs {
                let file = data.appendingPathComponent(name)
                if let bytes = boundedFile(file) {
                    previousLogs[name] = bytes
                    previousLogDates[name] = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                }
            }
        }
    }

    private func baselineLogs() {
        for name in Self.logs {
            let attributes = try? FileManager.default.attributesOfItem(atPath: data.appendingPathComponent(name).path)
            logOffsets[name] = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
        }
    }

    func automatic(_ key: String) -> Bool {
        !disabled && Self.configuration(data: data, key: key)
    }

    private static func configuration(data: URL, key: String) -> Bool {
        let text = (try? String(contentsOf: data.appendingPathComponent("springsettings.cfg"), encoding: .utf8)) ?? ""
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 && parts[0] == key { return parts[1] == "1" }
        }
        return false
    }

    private func prompt(_ event: [String: Any], key: String) {
        guard !disabled else { return }
        prompts.enter()
        DispatchQueue.main.async { [self] in
            compose(event: event, key: key, crash: true) { [self] in prompts.leave() }
        }
    }

    static let knownErrors = [
        "[MacEGLBridge] could not load Mesa libEGL",
        "[MacEGLBridge] eglCreatePbufferSurface",
        "[MacEGLBridge] SDL_CreateRenderer failed",
        "[MacRetina] could not create scene framebuffer",
        "[MacEGLBridge] eglGetPlatformDisplayEXT(surfaceless) failed",
        "[MacEGLBridge] eglInitialize failed",
        "[MacEGLBridge] eglChooseConfig failed",
        "[MacEGLBridge] eglMakeCurrent failed",
        "[MacEGLBridge] could not enable required VSync"
    ]

    static func logErrors(_ text: String) -> [String] {
        // Return constants, never the original line (which may contain user paths).
        var errors = knownErrors.filter { text.contains($0) }
        let widgets = ["gui_macos_display.lua", "gui_macos_trackpad.lua", "gui_macos_announcement.lua"]
        for line in text.split(separator: "\n") where line.contains("Error in ") || line.contains("Lua error:") {
            for widget in widgets where line.contains("/" + widget) {
                let error = "macOS widget error: " + widget
                if !errors.contains(error) { errors.append(error) }
            }
        }
        return errors
    }

    static func gameVersion(_ text: String) -> String? {
        guard let range = text.range(of: #"Zero-K v[0-9]+(?:\.[0-9]+){1,5}"#, options: .regularExpression) else { return nil }
        return String(text[range])
    }

    static func crashEvent(_ bytes: Data, bundle: URL) -> [String: Any]? {
        guard let text = String(data: bytes, encoding: .utf8), let newline = text.firstIndex(of: "\n"),
              let header = try? JSONSerialization.jsonObject(with: Data(text[..<newline].utf8)) as? [String: Any],
              header["bug_type"] as? String == "309",
              let report = try? JSONSerialization.jsonObject(with: Data(text[text.index(after: newline)...].utf8)) as? [String: Any],
              let path = report["procPath"] as? String,
              let images = report["usedImages"] as? [[String: Any]],
              let threads = report["threads"] as? [[String: Any]],
              let fault = report["faultingThread"] as? Int, threads.indices.contains(fault),
              let frames = threads[fault]["frames"] as? [[String: Any]] else { return nil }
        let contents = bundle.resolvingSymlinksInPath().appendingPathComponent("Contents").path + "/"
        guard path == contents + "MacOS/spring" || path == contents + "MacOS/Zero-K" else { return nil }
        // The first non-system frame must implicate our launcher, macOS bridge,
        // or bundled translation stack. A Mac frame farther down is not evidence.
        let candidate = frames.prefix(12).first { frame in
            guard let index = frame["imageIndex"] as? Int, images.indices.contains(index),
                  let imagePath = images[index]["path"] as? String else { return true }
            return !imagePath.hasPrefix("/usr/lib/") && !imagePath.hasPrefix("/System/")
        }
        guard let candidate, let index = candidate["imageIndex"] as? Int, images.indices.contains(index),
              let imagePath = images[index]["path"] as? String, imagePath.hasPrefix(contents) else { return nil }
        let name = URL(fileURLWithPath: imagePath).lastPathComponent
        let symbol = candidate["symbol"] as? String ?? ""
        let ownSymbols = ["MacEGLBridge::", "MacMetalFX::", "MacDisplayLink::", "MacHDR::"]
        let translation = name == "libEGL.1.dylib" || name == "libvulkan_kosmickrisp.dylib"
            || (name.hasPrefix("libgallium-") && name.hasSuffix(".dylib"))
        guard translation || (name == "Zero-K" && path == contents + "MacOS/Zero-K")
            || (name == "spring" && ownSymbols.contains(where: symbol.hasPrefix)) else { return nil }

        var stack: [[String: Any]] = []
        var debug: [[String: Any]] = []
        for frame in frames.prefix(64) {
            guard let i = frame["imageIndex"] as? Int, images.indices.contains(i),
                  let base = images[i]["base"] as? UInt64, let offset = frame["imageOffset"] as? UInt64,
                  offset <= UInt64.max - base, let imagePath = images[i]["path"] as? String,
                  imagePath.hasPrefix(contents) || imagePath.hasPrefix("/System/") || imagePath.hasPrefix("/usr/lib/") else { continue }
            let file = URL(fileURLWithPath: imagePath).lastPathComponent
            var entry: [String: Any] = ["instruction_addr": String(format: "0x%llx", base + offset),
                                        "image_addr": String(format: "0x%llx", base), "package": file,
                                        "in_app": imagePath.hasPrefix(contents)]
            if let function = frame["symbol"] as? String { entry["function"] = String(function.prefix(512)) }
            stack.append(entry)
            if let uuid = images[i]["uuid"] as? String, UUID(uuidString: uuid) != nil,
               !debug.contains(where: { $0["debug_id"] as? String == uuid }) {
                debug.append(["type": "macho", "debug_id": uuid, "code_file": file,
                              "image_addr": String(format: "0x%llx", base), "image_size": images[i]["size"] ?? 0,
                              "arch": "arm64"])
            }
        }
        guard !stack.isEmpty else { return nil }
        var result: [String: Any] = ["level": "fatal", "platform": "native",
                "exception": ["values": [["type": "MacOSPortCrash", "value": "Crash in " + name,
                    "mechanism": ["type": "macos_crash_report", "handled": false],
                    "stacktrace": ["frames": Array(stack.reversed())]]]],
                "debug_meta": ["images": debug], "tags": ["attribution": "macos-component-frame", "component": name],
                "release": "zkmacos@" + ((report["bundleInfo"] as? [String: Any])?["CFBundleShortVersionString"] as? String ?? "unknown")]
        if let captured = report["captureTime"] as? String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS Z"
            if let date = formatter.date(from: captured) { result["timestamp"] = date.timeIntervalSince1970 }
        }
        return result
    }

    func scan(allowPrompt: Bool = false, completion: (() -> Void)? = nil) {
        guard !disabled else {
            if let completion { DispatchQueue.main.async(execute: completion) }
            return
        }
        queue.async { [self] in
            let since = max(defaults.object(forKey: "MacOSReportsSince") as? Date ?? Date(), Date().addingTimeInterval(-7 * 86400))
            let reports = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports")
            let files = (try? FileManager.default.contentsOfDirectory(at: reports,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
            for file in files where file.pathExtension == "ips" && (file.lastPathComponent.hasPrefix("spring-") || file.lastPathComponent.hasPrefix("Zero-K-")) {
                guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                      let date = values.contentModificationDate, date >= since,
                      let size = values.fileSize, size < 8_000_000,
                      let bytes = try? Data(contentsOf: file), var event = Self.crashEvent(bytes, bundle: bundle) else { continue }
                if event["timestamp"] == nil { event["timestamp"] = date.timeIntervalSince1970 }
                guard (event["timestamp"] as? Double ?? 0) >= since.timeIntervalSince1970 else { continue }
                let key = file.lastPathComponent
                guard !(defaults.stringArray(forKey: "MacOSDeclinedIncidents") ?? []).contains(key) else { continue }
                if automatic("MacAutomaticCrashReporting") {
                    send(event, key: key)
                } else if allowPrompt {
                    var asked = defaults.stringArray(forKey: "MacOSAskedIncidents") ?? []
                    let sent = defaults.stringArray(forKey: "MacOSReportedIncidents") ?? []
                    if !asked.contains(key) && !sent.contains(key) {
                        asked.append(key)
                        defaults.set(Array(asked.suffix(1000)), forKey: "MacOSAskedIncidents")
                        prompt(event, key: key)
                        break
                    }
                }
            }
            // Read a bounded tail; only allowlisted constants are transmitted.
            for name in Self.logs {
                let file = data.appendingPathComponent(name)
                guard let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      date >= since, let handle = try? FileHandle(forReadingFrom: file) else { continue }
                defer { try? handle.close() }
                guard let length = try? handle.seekToEnd() else { continue }
                let previous = logOffsets[name] ?? length
                let start = previous > length ? 0 : previous
                try? handle.seek(toOffset: max(start, length > 1_000_000 ? length - 1_000_000 : 0))
                logOffsets[name] = length
                let text = (try? handle.readToEnd()).flatMap { String(data: $0, encoding: .utf8) } ?? ""
                if let version = Self.gameVersion(text) { defaults.set(version, forKey: "MacOSReportGameVersion") }
                guard automatic("MacAutomaticErrorReporting") else { continue }
                for error in Self.logErrors(text) {
                    var fields: [String: Any] = ["message": error, "level": "error", "tags": ["attribution": "explicit-macos-error"]]
                    if let line = text.split(separator: "\n").first(where: { $0.contains(error) }),
                       let range = line.range(of: #"\[f=\s*\d+\]"#, options: .regularExpression),
                       let frame = Double(line[range].filter(\.isNumber)) {
                        fields["contexts"] = ["failure": ["frame": frame, "game_seconds": frame / 30]]
                    }
                    send(fields,
                         key: "error:" + error + ":" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development"))
                }
            }
            if let completion {
                prompts.notify(queue: queue) { DispatchQueue.main.async(execute: completion) }
            }
        }
    }

    @discardableResult
    func send(_ fields: [String: Any], key: String, selection: Set<String>? = nil, prepared: ReportFiles? = nil) -> String? {
        guard !disabled else { return nil }
        // Called on the serial queue; one event in flight to keep deduplication simple.
        var sent = defaults.stringArray(forKey: "MacOSReportedIncidents") ?? []
        let day = Int(Date().timeIntervalSince1970 / 86400)
        if defaults.integer(forKey: "MacOSReportDay") != day {
            defaults.set(day, forKey: "MacOSReportDay")
            defaults.set(0, forKey: "MacOSReportCount")
        }
        guard !sent.contains(key), defaults.integer(forKey: "MacOSReportCount") < 10 else { return nil }
        // Count attempts too; being offline must not cause a request every poll.
        defaults.set(defaults.integer(forKey: "MacOSReportCount") + 1, forKey: "MacOSReportCount")
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        var event: [String: Any] = ["event_id": id, "platform": "native", "timestamp": Date().timeIntervalSince1970,
            "environment": "production", "release": "zkmacos@" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"),
            "contexts": ["os": ["name": "macOS", "version": ProcessInfo.processInfo.operatingSystemVersionString],
                         "device": ["arch": "arm64"]]]
        event.merge(fields) { _, new in new }
        let incident = Date(timeIntervalSince1970: event["timestamp"] as? Double ?? Date().timeIntervalSince1970)
        if prepared == nil && (selection ?? attachmentDefaults()).contains("Screenshot") && fields["level"] as? String != "fatal" {
            try? Data().write(to: data.appendingPathComponent("macos-report-screenshot"), options: .atomic)
            Thread.sleep(forTimeInterval: 2)
            try? FileManager.default.removeItem(at: data.appendingPathComponent("macos-report-screenshot"))
        }
        let files = prepared ?? reportFiles(selection ?? attachmentDefaults(), incident: incident)
        var contexts = event["contexts"] as? [String: Any] ?? [:]
        if let game = files.match { contexts["match"] = game.filter { $0.key != "replay" } }
        contexts["attachments"] = ["included": files.bytes.keys.sorted().joined(separator: ", "), "notes": files.notes.joined(separator: "; ")]
        event["contexts"] = contexts
        // An explicit non-routable address also prevents Sentry from inferring
        // location from the transport IP. No real user identity is included.
        event["user"] = ["ip_address": "0.0.0.0"]
        if let bytes = try? Data(contentsOf: bundle.appendingPathComponent("Contents/Resources/port-build.json")),
           let build = try? JSONSerialization.jsonObject(with: bytes) as? [String: String] {
            var contexts = event["contexts"] as? [String: Any] ?? [:]
            contexts["port_build"] = build
            event["contexts"] = contexts
        }
        if let gameVersion = defaults.string(forKey: "MacOSReportGameVersion") {
            var contexts = event["contexts"] as? [String: Any] ?? [:]
            contexts["game"] = ["version": gameVersion]
            event["contexts"] = contexts
        }
        guard let payload = try? JSONSerialization.data(withJSONObject: event),
              let header = try? JSONSerialization.data(withJSONObject: ["event_id": id, "dsn": Self.dsn]),
              let item = try? JSONSerialization.data(withJSONObject: ["type": "event", "length": payload.count]) else { return nil }
        var body = header
        body.append(10); body.append(item); body.append(10); body.append(payload); body.append(10)
        for (name, bytes) in files.bytes.sorted(by: { $0.key < $1.key }) {
            guard let attachment = try? JSONSerialization.data(withJSONObject: ["type": "attachment", "length": bytes.count, "filename": name]) else { continue }
            body.append(attachment); body.append(10); body.append(bytes); body.append(10)
        }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-sentry-envelope", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let done = DispatchSemaphore(value: 0)
        var success = false
        session.dataTask(with: request) { _, response, _ in
            success = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            done.signal()
        }.resume()
        done.wait()
        if success {
            sent.append(key)
            defaults.set(Array(sent.suffix(1000)), forKey: "MacOSReportedIncidents")
            return id
        }
        return nil
    }
}

struct ReportFiles {
    var bytes: [String: Data] = [:]
    var notes: [String] = []
    var match: [String: Any]?
}

extension CrashReporting {
    static let attachmentOptions = [("Replay", "Replay and game timestamp"), ("Logs", "Full logs"),
                                    ("Screenshot", "Engine screenshot"), ("Configuration", "Configuration data")]

    func attachmentDefaults() -> Set<String> {
        Set(Self.attachmentOptions.map(\.0).filter { Self.configuration(data: data, key: "MacReport" + $0) })
    }

    private func boundedFile(_ file: URL) -> Data? {
        let path = file.resolvingSymlinksInPath().path
        guard path.hasPrefix(data.resolvingSymlinksInPath().path + "/"),
              let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true, let size = values.fileSize, size <= 20_000_000 else { return nil }
        return try? Data(contentsOf: file)
    }

    func gameContext(incident: Date) -> [String: Any]? {
        guard let bytes = boundedFile(data.appendingPathComponent("macos-report-game.json")),
              let context = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let observed = context["observed_at"] as? Double,
              abs(observed - incident.timeIntervalSince1970) <= 15 else { return nil }
        var result: [String: Any] = [:]
        for key in ["game", "version", "map", "game_id", "replay"] {
            if let value = context[key] as? String { result[key] = String(value.prefix(512)) }
        }
        for key in ["frame", "observed_at", "started_at"] {
            if let value = context[key] as? Double, value.isFinite, value >= 0 { result[key] = value }
        }
        if let frame = result["frame"] as? Double { result["game_seconds"] = frame / 30 }
        return result
    }

    static func sanitizedConfiguration(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, item) in dictionary {
                let lower = key.lowercased()
                if ["password", "passwd", "token", "secret", "account", "user", "login", "email", "chat", "friend", "cookie", "credential", "address", "path", "directory"].contains(where: lower.contains) { continue }
                result[key] = sanitizedConfiguration(item)
            }
            return result
        }
        if let array = value as? [Any] { return array.map(sanitizedConfiguration) }
        if let string = value as? String {
            if string.contains("/Users/") || string.contains("/home/") || string.contains("://") { return "[redacted]" }
        }
        return value
    }

    func reportFiles(_ selection: Set<String>, incident: Date, context: [String: Any]? = nil, screenshotAfter: Date? = nil) -> ReportFiles {
        var files = ReportFiles()
        let context = context ?? gameContext(incident: incident)
        files.match = context
        if selection.contains("Replay") {
            if let replay = context?["replay"] as? String {
                let file = replay.hasPrefix("/") ? URL(fileURLWithPath: replay) : data.appendingPathComponent(replay)
                let directory = data.appendingPathComponent("demos").resolvingSymlinksInPath().path + "/"
                if ["sdf", "sdfz"].contains(file.pathExtension.lowercased()), file.resolvingSymlinksInPath().path.hasPrefix(directory), let bytes = boundedFile(file), !bytes.isEmpty {
                    files.bytes["replay." + file.pathExtension] = bytes
                } else { files.notes.append("Replay unavailable or over 20 MB; hard crashes may not save a replay") }
            } else { files.notes.append("No replay confidently associated with this incident") }
        }
        if selection.contains("Logs") {
            for name in Self.logs {
                let matched = previousLogDates[name].map { abs($0.timeIntervalSince(incident)) <= 60 } ?? false
                let bytes = incident < launchedAt ? (matched ? previousLogs[name] : nil) : boundedFile(data.appendingPathComponent(name))
                if let bytes { files.bytes[name.replacingOccurrences(of: "/", with: "-")] = bytes }
                else { files.notes.append(name + " unavailable, not matched to this incident, or over 20 MB") }
            }
        }
        if selection.contains("Screenshot") {
            let screenshots = data.appendingPathComponent("screenshots")
            let candidates = (try? FileManager.default.contentsOfDirectory(at: screenshots, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            let start = screenshotAfter?.timeIntervalSince1970 ?? context?["started_at"] as? Double ?? incident.timeIntervalSince1970 - 5
            let end = screenshotAfter == nil ? incident.addingTimeInterval(5) : Date().addingTimeInterval(5)
            let image = candidates.filter { ["png", "jpg", "jpeg"].contains($0.pathExtension.lowercased()) }.compactMap { file -> (URL, Date)? in
                guard let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      date.timeIntervalSince1970 >= start, date <= end else { return nil }
                return (file, date)
            }.sorted { $0.1 > $1.1 }.first
            if let image, let bytes = boundedFile(image.0) {
                files.bytes["engine-screenshot." + image.0.pathExtension] = bytes
                files.notes.append("Screenshot captured at " + ISO8601DateFormatter().string(from: image.1))
            }
            else { files.notes.append("No matching engine screenshot; fresh capture is unavailable after a crash") }
        }
        if selection.contains("Configuration") {
            if let bytes = boundedFile(data.appendingPathComponent("springsettings.cfg")), let text = String(data: bytes, encoding: .utf8) {
                var values: [String: String] = [:]
                for line in text.split(separator: "\n") {
                    let pair = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    if pair.count == 2 { values[pair[0]] = pair[1] }
                }
                files.bytes["springsettings-sanitized.json"] = try? JSONSerialization.data(withJSONObject: Self.sanitizedConfiguration(values), options: [.prettyPrinted, .sortedKeys])
            }
            if let bytes = boundedFile(data.appendingPathComponent("macos-report-lobby.json")), let json = try? JSONSerialization.jsonObject(with: bytes) {
                files.bytes["lobby-settings-sanitized.json"] = try? JSONSerialization.data(withJSONObject: Self.sanitizedConfiguration(json), options: [.prettyPrinted, .sortedKeys])
            } else { files.notes.append("Lobby preference export unavailable") }
        }
        var size = 0
        for name in files.bytes.keys.sorted() {
            size += files.bytes[name]!.count
            if size > 50_000_000 { files.bytes.removeValue(forKey: name); files.notes.append(name + " omitted: 50 MB total limit") }
        }
        return files
    }

    func pollManualRequest() {
        guard !manualReportOpen else { return }
        let request = data.appendingPathComponent("macos-report-request")
        guard FileManager.default.fileExists(atPath: request.path) else { return }
        try? FileManager.default.removeItem(at: request)
        manualReportOpen = true
        compose(event: ["message": "User-submitted ZkMacOS bug report", "level": "info"], key: UUID().uuidString, crash: false) { self.manualReportOpen = false }
    }

    private func compose(event: [String: Any], key: String, crash: Bool, completion: @escaping () -> Void = {}) {
        let incident = Date(timeIntervalSince1970: event["timestamp"] as? Double ?? Date().timeIntervalSince1970)
        let match = gameContext(incident: incident)
        let alert = NSAlert()
        alert.messageText = crash ? "Send a macOS-port crash report?" : "Report a Bug"
        alert.informativeText = disabled
            ? (Self.releaseBuild ? "Telemetry is disabled for this run. No Sentry upload is possible. You can still open a prefilled GitHub issue. Restart after changing Disable All Telemetry to re-enable uploads." : "This is a development build. Sentry uploads and crash-report prompts are disabled. You can still open a GitHub issue with local build details.")
            : "Choose optional attachments for this report. These choices do not change your saved settings. Logs, replays and screenshots may contain names, chat or other private information. Configuration exports remove sensitive keys; review the files before sending. You will review the exact upload next. Sentry receives your connection IP; the report uses an anonymized IP value."
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 116))
        let initial = attachmentDefaults()
        var boxes: [(String, NSButton)] = []
        for (index, option) in Self.attachmentOptions.enumerated() {
            let box = NSButton(checkboxWithTitle: option.1, target: nil, action: nil)
            box.frame = NSRect(x: 0, y: 90 - index * 28, width: 420, height: 24)
            box.state = initial.contains(option.0) ? .on : .off
            box.isEnabled = !disabled
            view.addSubview(box); boxes.append((option.0, box))
        }
        alert.accessoryView = view
        if !disabled { alert.addButton(withTitle: crash ? "Review Report" : "Review Upload & Open Issue") }
        if !crash { alert.addButton(withTitle: "Open GitHub Only") }
        alert.addButton(withTitle: crash ? "Don’t Send" : "Cancel")
        NSApplication.shared.activate(ignoringOtherApps: true)
        let answer = alert.runModal()
        if !crash && answer == (disabled ? .alertFirstButtonReturn : .alertSecondButtonReturn) {
            openIssue(incident: incident, id: nil, notes: "No diagnostics uploaded.", match: match); completion(); return
        }
        guard !disabled, answer == .alertFirstButtonReturn else {
            if crash {
                queue.async { [self] in
                    var declined = defaults.stringArray(forKey: "MacOSDeclinedIncidents") ?? []
                    declined.append(key); defaults.set(Array(declined.suffix(1000)), forKey: "MacOSDeclinedIncidents")
                    completion()
                }
            } else { completion() }
            return
        }
        let selection = Set(boxes.filter { $0.1.state == .on }.map(\.0))
        let screenshotAfter = !crash && selection.contains("Screenshot") ? Date() : nil
        if !crash && selection.contains("Screenshot") {
            try? Data().write(to: data.appendingPathComponent("macos-report-screenshot"), options: .atomic)
        }
        queue.asyncAfter(deadline: .now() + (!crash && selection.contains("Screenshot") ? 2 : 0)) { [self] in
            try? FileManager.default.removeItem(at: data.appendingPathComponent("macos-report-screenshot"))
            let files = reportFiles(selection, incident: incident, context: match, screenshotAfter: screenshotAfter)
            DispatchQueue.main.async { [self] in
                let review = NSAlert()
                review.messageText = "Review report attachments"
                let listing = files.bytes.keys.sorted().map { "\($0): \(files.bytes[$0]!.count) bytes" }.joined(separator: "\n")
                review.informativeText = "\(listing.isEmpty ? "No attachments." : listing)\n\n\(files.notes.joined(separator: "\n"))\n\nOnly the files listed above will be uploaded to Sentry with the technical event. GitHub receives environment details and the report ID when you open the issue."
                review.addButton(withTitle: "Upload")
                review.addButton(withTitle: "Cancel")
                // A local review folder is kept until the dialog closes.
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                for (name, bytes) in files.bytes { try? bytes.write(to: folder.appendingPathComponent(name)) }
                // NSAlert supports an additional action without dismissing the report.
                review.addButton(withTitle: "Inspect Files…")
                var choice = review.runModal()
                while choice == .alertThirdButtonReturn {
                    NSWorkspace.shared.open(folder)
                    choice = review.runModal()
                }
                try? FileManager.default.removeItem(at: folder)
                guard choice == .alertFirstButtonReturn else { completion(); return }
                queue.async { [self] in
                    let id = send(event, key: key, selection: selection, prepared: files)
                    DispatchQueue.main.async { [self] in
                        if !crash { openIssue(incident: incident, id: id, notes: id == nil ? "Upload failed or was rate limited; no successful upload was confirmed." : files.bytes.keys.sorted().joined(separator: ", "), match: match) }
                        if id == nil {
                            let failure = NSAlert(); failure.messageText = "Report upload was not confirmed"
                            failure.informativeText = "Sentry may be unavailable, or the daily limit was reached. You can report the problem on GitHub and attach files there yourself."
                            failure.runModal()
                        }
                        completion()
                    }
                }
            }
        }
    }

    func issueURL(incident: Date, id: String?, notes: String, match: [String: Any]? = nil) -> URL {
        var environment = "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\nArchitecture: arm64"
        if let bytes = try? Data(contentsOf: bundle.appendingPathComponent("Contents/Resources/port-build.json")),
           let build = try? JSONSerialization.jsonObject(with: bytes) as? [String: String] {
            environment += "\n" + build.keys.sorted().map { "\($0): \(build[$0]!)" }.joined(separator: "\n")
        }
        if let game = match ?? gameContext(incident: incident) {
            environment += "\n" + ["game", "version", "map", "game_id", "frame", "game_seconds"].compactMap { key in game[key].map { "\(key): \($0)" } }.joined(separator: "\n")
        }
        var url = URLComponents(string: "https://github.com/smallketchup82/ZkMacOS/issues/new")!
        url.queryItems = [URLQueryItem(name: "template", value: "bug-report.yml"), URLQueryItem(name: "environment", value: environment),
            URLQueryItem(name: "files", value: (id.map { "Sentry report ID: \($0)\n" } ?? "") + notes)]
        return url.url!
    }

    private func openIssue(incident: Date, id: String?, notes: String, match: [String: Any]? = nil) {
        NSWorkspace.shared.open(issueURL(incident: incident, id: id, notes: notes, match: match))
    }
}
