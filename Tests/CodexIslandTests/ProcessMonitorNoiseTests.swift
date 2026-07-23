import XCTest
@testable import CodexIslandApp

final class ProcessMonitorNoiseTests: XCTestCase {
    func testFiltersShadcnMCPLaunchVariants() {
        let commands = [
            "node npx shadcn@latest mcp",
            "npm exec shadcn@latest mcp",
            "npx shadcn@latest mcp",
            "node shadcn mcp",
            "env node npx shadcn@latest mcp",
            "/usr/bin/env /opt/homebrew/bin/node /opt/homebrew/bin/npx shadcn@latest mcp",
            "arch -arm64 node npx shadcn@latest mcp",
            "  ENV   node   npx   SHADCN@latest   MCP  ",
        ]

        for command in commands {
            XCTAssertTrue(ProcessMonitor.isNoise(command), "Expected MCP noise: \(command)")
        }
    }

    func testKeepsNormalShadcnAndDiagnosticCommands() {
        let commands = [
            "npx shadcn@latest add button",
            "npx shadcn@latest view button",
            "rg -n shadcn mcp",
            "echo shadcn mcp",
            "node app.js",
            "npm run dev",
        ]

        for command in commands {
            XCTAssertFalse(ProcessMonitor.isNoise(command), "Expected user command: \(command)")
        }
    }

    func testFiltersCodexAppServerLaunchVariants() {
        let commands = [
            "codex app-server",
            "codex -c features.code_mode_host=true app-server --analytics-default-enabled",
            "/Applications/ChatGPT.app/Contents/Resources/codex -c features.code_mode_host=true app-server",
            "env codex -c model=gpt-5 app-server",
            "  CODEX   -c   features.code_mode_host=true   APP-SERVER  ",
        ]

        for command in commands {
            XCTAssertTrue(ProcessMonitor.isNoise(command), "Expected Codex host noise: \(command)")
        }
    }

    func testFiltersCodexIslandHookAndTransientHostVariants() {
        let commands = [
            "codex",
            "python3 codex_island_hook.py PreToolUse",
            "/usr/bin/python3 /Users/test/.codex-island/codex_island_hook.py PostToolUse",
            "Python codex_island_hook.py Stop",
        ]

        for command in commands {
            XCTAssertTrue(ProcessMonitor.isNoise(command), "Expected internal Codex noise: \(command)")
        }
    }

    func testKeepsNormalCodexCLIAndDiagnosticCommands() {
        let commands = [
            "codex exec fix the tests",
            "codex -c model=gpt-5 exec fix the tests",
            "codex --version",
            "rg codex app-server",
            "echo codex app-server",
        ]

        for command in commands {
            XCTAssertFalse(ProcessMonitor.isNoise(command), "Expected user command: \(command)")
        }
    }
}
