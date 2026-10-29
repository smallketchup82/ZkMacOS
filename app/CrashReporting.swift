import AppKit
import Foundation

// Read Apple's reports after a crash, rather than installing another crash handler
// in the engine. Only a small, locally classified event ever leaves this machine.
final class CrashReporting {
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
    private static let logs = ["infolog.txt", "log/launcher.log", "log/engine-launch.log"]

    init(data: URL, bundle: URL = Bundle.main.bundleURL, defaults: UserDefaults = .standard,
         configuration: URLSessionConfiguration = .ephemeral) {
        self.data = data
        self.bundle = bundle
        self.defaults = defaults
        disabled = Self.configuration(data: data, key: "MacDisableAllTelemetry")
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 10
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration)
        if disabled || defaults.object(forKey: "MacOSReportsSince") == nil {
            defaults.set(Date(), forKey: "MacOSReportsSince")
        }
        baselineLogs()
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
            let alert = NSAlert()
            alert.messageText = "Send a macOS-port crash report?"
            alert.informativeText = "Zero-K crashed in a component strongly associated with this macOS port. Send a filtered technical report to the port maintainer through Sentry? It includes the app/macOS versions and crash stack, without full logs, chat, account details or replays. Sentry receives your IP address as part of the connection. Automatic Crash Reporting and Automatic Error Reporting are available in the lobby's Lobby settings."
            alert.addButton(withTitle: "Send Report")
            alert.addButton(withTitle: "Don’t Send")
            NSApplication.shared.activate(ignoringOtherApps: true)
            let consent = alert.runModal() == .alertFirstButtonReturn
            queue.async { [self] in
                if consent {
                    send(event, key: key)
                } else {
                    var declined = defaults.stringArray(forKey: "MacOSDeclinedIncidents") ?? []
                    declined.append(key)
                    defaults.set(Array(declined.suffix(1000)), forKey: "MacOSDeclinedIncidents")
                }
                prompts.leave()
            }
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
        return ["level": "fatal", "platform": "native",
                "exception": ["values": [["type": "MacOSPortCrash", "value": "Crash in " + name,
                    "mechanism": ["type": "macos_crash_report", "handled": false],
                    "stacktrace": ["frames": Array(stack.reversed())]]]],
                "debug_meta": ["images": debug], "tags": ["attribution": "macos-component-frame", "component": name],
                "release": "zkmacos@" + ((report["bundleInfo"] as? [String: Any])?["CFBundleShortVersionString"] as? String ?? "unknown")]
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
                      let bytes = try? Data(contentsOf: file), let event = Self.crashEvent(bytes, bundle: bundle) else { continue }
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
                    send(["message": error, "level": "error", "tags": ["attribution": "explicit-macos-error"]],
                         key: "error:" + error + ":" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development"))
                }
            }
            if let completion {
                prompts.notify(queue: queue) { DispatchQueue.main.async(execute: completion) }
            }
        }
    }

    func send(_ fields: [String: Any], key: String) {
        guard !disabled else { return }
        // Called on the serial queue; one event in flight to keep deduplication simple.
        var sent = defaults.stringArray(forKey: "MacOSReportedIncidents") ?? []
        let day = Int(Date().timeIntervalSince1970 / 86400)
        if defaults.integer(forKey: "MacOSReportDay") != day {
            defaults.set(day, forKey: "MacOSReportDay")
            defaults.set(0, forKey: "MacOSReportCount")
        }
        guard !sent.contains(key), defaults.integer(forKey: "MacOSReportCount") < 10 else { return }
        // Count attempts too; being offline must not cause a request every poll.
        defaults.set(defaults.integer(forKey: "MacOSReportCount") + 1, forKey: "MacOSReportCount")
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        var event: [String: Any] = ["event_id": id, "platform": "native", "timestamp": Date().timeIntervalSince1970,
            "environment": "production", "release": "zkmacos@" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"),
            "contexts": ["os": ["name": "macOS", "version": ProcessInfo.processInfo.operatingSystemVersionString],
                         "device": ["arch": "arm64"]]]
        event.merge(fields) { _, new in new }
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
              let item = try? JSONSerialization.data(withJSONObject: ["type": "event", "length": payload.count]) else { return }
        var body = header
        body.append(10); body.append(item); body.append(10); body.append(payload); body.append(10)
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
        }
    }
}
