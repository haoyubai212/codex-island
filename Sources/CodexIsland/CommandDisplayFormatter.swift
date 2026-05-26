import Foundation

enum CommandDisplayFormatter {
    static func displayName(_ command: String, limit: Int = 40) -> String {
        let clean = normalize(command)
        guard !clean.isEmpty else { return "执行命令" }
        if clean.count <= limit { return clean }
        return String(clean.prefix(limit)) + "..."
    }

    static func compactName(_ command: String, limit: Int = 14) -> String {
        let clean = normalize(command)
        let tokens = clean.split(separator: " ", maxSplits: 10).map(String.init)
        guard !tokens.isEmpty else { return clean }

        if clean.lowercased().contains("google chrome") || clean.lowercased().contains("chrome-cdp") {
            return "Chrome"
        }
        if tokens.first?.lowercased() == "agent-browser" {
            var foundCdp = false
            for token in tokens.dropFirst() {
                if token == "--cdp" { foundCdp = true; continue }
                if foundCdp && token.allSatisfy({ $0.isNumber }) { continue }
                if foundCdp || !token.hasPrefix("-") {
                    return token
                }
            }
            return "browse"
        }

        let result = tokens.prefix(2).joined(separator: " ")
        return result.count > limit ? String(result.prefix(limit)) : result
    }

    private static func normalize(_ command: String) -> String {
        var clean = command
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)

        let wrappers = [
            "/bin/zsh -lc ", "/bin/zsh -c ",
            "/bin/bash -lc ", "/bin/bash -c ",
            "/bin/sh -lc ", "/bin/sh -c ",
            "zsh -lc ", "zsh -c ",
            "bash -lc ", "bash -c ",
            "sh -lc ", "sh -c ",
            "env ", "arch "
        ]
        for wrapper in wrappers where clean.hasPrefix(wrapper) {
            clean = String(clean.dropFirst(wrapper.count))
        }

        if clean.contains("brew.sh") {
            clean = clean.replacingOccurrences(of: "bash -p ", with: "")
            clean = clean.replacingOccurrences(of: "brew.sh", with: "brew")
        }

        return abbreviateHome(in: clean)
    }

    private static func abbreviateHome(in text: String) -> String {
        let home = NSHomeDirectory()
        guard !home.isEmpty else { return text }
        return text
            .replacingOccurrences(of: home, with: "~")
            .replacingOccurrences(of: home.replacingOccurrences(of: " ", with: "\\ "), with: "~")
    }
}
