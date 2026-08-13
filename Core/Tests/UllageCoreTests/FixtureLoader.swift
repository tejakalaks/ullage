import Foundation
import XCTest

enum Fixture {
    static func text(_ name: String) throws -> String {
        let url = try url(name)
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: try url(name))
    }

    private static func url(_ name: String) throws -> URL {
        let components = name.split(separator: ".")
        let base = components.dropLast().joined(separator: ".")
        let ext = String(components.last ?? "")
        if let url = Bundle.module.url(forResource: base, withExtension: ext, subdirectory: "Fixtures") {
            return url
        }
        if let url = Bundle.module.url(forResource: base, withExtension: ext) {
            return url
        }
        throw XCTSkip("Fixture \(name) is missing from the test bundle.")
    }
}
