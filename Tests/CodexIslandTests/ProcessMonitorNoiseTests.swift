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
}
