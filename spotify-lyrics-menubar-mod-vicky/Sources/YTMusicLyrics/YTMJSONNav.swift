import Foundation

enum YTMJSONNav {
    enum PathItem {
        case key(String)
        case index(Int)
    }

    static func nav(_ root: Any?, path: [PathItem]) -> Any? {
        var current = root
        for item in path {
            switch item {
            case .key(let key):
                guard let dict = current as? [String: Any], let next = dict[key] else { return nil }
                current = next
            case .index(let index):
                guard let array = current as? [Any], array.indices.contains(index) else { return nil }
                current = array[index]
            }
        }
        return current
    }

    static func string(_ root: Any?, path: [PathItem]) -> String? {
        nav(root, path: path) as? String
    }

    static func dict(_ root: Any?, path: [PathItem]) -> [String: Any]? {
        nav(root, path: path) as? [String: Any]
    }

    static func array(_ root: Any?, path: [PathItem]) -> [Any]? {
        nav(root, path: path) as? [Any]
    }

    static func textRuns(_ root: Any?) -> String {
        guard let runs = root as? [[String: Any]] else { return "" }
        return runs.compactMap { $0["text"] as? String }.joined()
    }

    static func findObjects(in root: Any?, matching key: String) -> [[String: Any]] {
        guard let root else { return [] }
        var results: [[String: Any]] = []
        collectObjects(in: root, matching: key, into: &results)
        return results
    }

    private static func collectObjects(in value: Any, matching key: String, into results: inout [[String: Any]]) {
        if let dict = value as? [String: Any] {
            if let match = dict[key] as? [String: Any] {
                results.append(match)
            }
            for child in dict.values {
                collectObjects(in: child, matching: key, into: &results)
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectObjects(in: child, matching: key, into: &results)
            }
        }
    }
}
