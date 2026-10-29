import Foundation

final class ReportTransport: URLProtocol {
    static var requests = 0
    static var bodies: [Data] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        if let body = request.httpBody { Self.bodies.append(body) }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

struct CrashReportChecks {
    static func run() {
        let bundle = URL(fileURLWithPath: "/Applications/Zero-K.app")
        let engine = bundle.appendingPathComponent("Contents/MacOS/spring").path
        let system = "/usr/lib/system/libsystem_kernel.dylib"
        let mesa = bundle.appendingPathComponent("Contents/Frameworks/libgallium-26.3.dylib").path
        func report(path: String = engine, symbol: String = "MacEGLBridge::SwapBuffers()", image: String = engine, firstImage: Int = 1) -> Data {
            let images: [[String: Any]] = [
                ["path": system, "base": 100, "size": 1000, "uuid": UUID().uuidString],
                ["path": image, "base": 2000, "size": 10000, "uuid": UUID().uuidString]]
            let report: [String: Any] = ["procPath": path, "usedImages": images, "faultingThread": 0,
                "threads": [["frames": [["imageIndex": firstImage, "imageOffset": 16, "symbol": symbol],
                                        ["imageIndex": 1, "imageOffset": 32, "symbol": "MacEGLBridge::Init()"]]]],
                "bundleInfo": ["CFBundleShortVersionString": "202610.29.0"],
                "userID": "private-user", "procName": "private-name", "asi": "private-chat"]
            var bytes = Data("{\"bug_type\":\"309\"}\n".utf8)
            bytes.append(try! JSONSerialization.data(withJSONObject: report))
            return bytes
        }
        let event = CrashReporting.crashEvent(report(), bundle: bundle)!
        let encoded = String(data: try! JSONSerialization.data(withJSONObject: event), encoding: .utf8)!
        for secret in ["private-user", "private-name", "private-chat", "/Applications/", "userID", "asi"] {
            precondition(!encoded.contains(secret), "Private fields must not be copied")
        }
        precondition(CrashReporting.crashEvent(report(symbol: "SomeSimulation::Update()"), bundle: bundle) == nil,
                     "A Mac frame farther down does not attribute a simulation crash")
        precondition(CrashReporting.crashEvent(report(image: mesa), bundle: bundle) != nil)
        precondition(CrashReporting.crashEvent(report(path: "/tmp/other/spring"), bundle: bundle) == nil)
        precondition(CrashReporting.crashEvent(report(image: "/tmp/libgallium-fake.dylib"), bundle: bundle) == nil)
        precondition(CrashReporting.crashEvent(Data("not JSON".utf8), bundle: bundle) == nil)
        precondition(CrashReporting.logErrors("Lua error; [MacHDR] HDR display unavailable; using SDR").isEmpty)
        precondition(CrashReporting.logErrors("[MacEGLBridge] eglInitialize failed: /Users/private-name") == ["[MacEGLBridge] eglInitialize failed"])
        precondition(CrashReporting.logErrors("Error in Update(): LuaUI/Widgets/gui_macos_trackpad.lua:42: private chat") == ["macOS widget error: gui_macos_trackpad.lua"])
        precondition(CrashReporting.logErrors("Loading LuaUI/Widgets/gui_macos_trackpad.lua").isEmpty)
        precondition(CrashReporting.logErrors("Error in Update(): LuaUI/Widgets/gui_upstream.lua:42").isEmpty)
        precondition(CrashReporting.gameVersion("Game: Zero-K v1.13.10.0; user=private") == "Zero-K v1.13.10.0")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "org.zerok.report-test." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let config = directory.appendingPathComponent("springsettings.cfg")
        func write(_ disabled: Int) {
            try! "MacDisableAllTelemetry = \(disabled)\nMacAutomaticCrashReporting = 1\nMacAutomaticErrorReporting = 1\n".write(to: config, atomically: true, encoding: .utf8)
        }
        let transport = URLSessionConfiguration.ephemeral
        transport.protocolClasses = [ReportTransport.self]
        write(1)
        let disabled = CrashReporting(data: directory, defaults: defaults, configuration: transport)
        precondition(disabled.disabled && !disabled.automatic("MacAutomaticCrashReporting"))
        disabled.queue.sync { disabled.send(["message": "must never send"], key: "disabled") }
        precondition(ReportTransport.requests == 0)
        write(0)
        precondition(disabled.disabled, "Re-enabling requires restart")
        let enabled = CrashReporting(data: directory, defaults: defaults, configuration: transport)
        precondition(!enabled.disabled && enabled.automatic("MacAutomaticErrorReporting"))
        write(1)
        precondition(!enabled.disabled, "Disabling is latched at launch")
        enabled.queue.sync {
            enabled.send(["message": "transport verification"], key: "once")
            enabled.send(["message": "transport verification"], key: "once")
        }
        precondition(ReportTransport.requests == 1, "Successful reports are deduplicated")
        if CommandLine.arguments.contains("--live-sentry") {
            write(0)
            let live = CrashReporting(data: directory, defaults: defaults)
            live.queue.sync {
                live.send(["message": "ZkMacOS reporting verification", "level": "error",
                           "environment": "development", "tags": ["verification": "synthetic-transport-test"]], key: "live-verification")
            }
            precondition((defaults.stringArray(forKey: "MacOSReportedIncidents") ?? []).contains("live-verification"))
            print("Sentry accepted the explicitly marked synthetic verification event")
        }
        print("Crash attribution, privacy, restart-latched disable and transport checks passed")
    }
}
