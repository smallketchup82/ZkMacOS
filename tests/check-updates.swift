import Foundation

struct UpdateChecks {
    static func run() {
        func check(_ tag: String, current: String = "202610.27.0", draft: Bool = false,
                   prerelease: Bool = false, expected: Bool) {
            let data = try! JSONSerialization.data(withJSONObject: [
                "tag_name": tag, "draft": draft, "prerelease": prerelease,
            ])
            let result = availableUpdate(data, currentVersion: current)
            precondition(result == (expected ? tag : nil), "Unexpected update for \(current) -> \(tag)")
        }

        check("202610.27.1", expected: true)
        check("202610.27.10", current: "202610.27.9", expected: true)
        check("202611.01.0", expected: true)
        check("202701.01.0", current: "202612.31.9", expected: true)
        check("v202610.28.0", current: "v202610.27.0", expected: true)
        check("202610.27.0", expected: false)
        check("202610.26.9", expected: false)
        check("202610.27.9", current: "202610.27.10", expected: false)
        check("202610.28.0", draft: true, expected: false)
        check("202610.28.0", prerelease: true, expected: false)
        for invalid in ["", "202610.28", "202610..0", "202610.28.0-beta", "202610.28.-1",
                        "202610.28.0.1", "release", "999999999999999999999.1.0"] {
            check(invalid, expected: false)
            check("202610.28.0", current: invalid, expected: false)
        }
        check("202610.28.0", current: "0.1.0", expected: true)
        for invalid in ["", "not json", "{}", "{\"tag_name\":\"202610.28.0\"}"] {
            precondition(availableUpdate(Data(invalid.utf8), currentVersion: "202610.27.0") == nil)
        }
        print("Update version and release checks passed")
    }
}
