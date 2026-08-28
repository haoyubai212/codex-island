import XCTest
@testable import CodexIslandApp

final class ProcessMonitorNoiseTests: XCTestCase {
    func testCategorizesAgyLikeAcpxCollaboration() {
        let commands = [
            "agy -p Resume the same camper RV job",
            "/opt/homebrew/bin/agy -p Build the model",
            "env AGY_MODE=turbo agy -p Continue",
            "arch -arm64 agy -p Continue",
            "  AGY   -p   Continue  ",
        ]

        for command in commands {
            let category = ProcessMonitor.categorizeCommand(command)
            XCTAssertEqual(category, .collaboration, "Expected AGY collaboration command: \(command)")
            XCTAssertEqual(category.icon, "person.2.fill")
        }

        XCTAssertEqual(ProcessMonitor.categorizeCommand("acpx exec review"), .collaboration)
    }

    func testDoesNotCategorizeAgyTextAsCollaboration() {
        XCTAssertEqual(ProcessMonitor.categorizeCommand("rg -n agy Sources"), .searching)
        XCTAssertEqual(ProcessMonitor.categorizeCommand("echo agy"), .executing)
    }

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

    func testFiltersSplineMCPLaunchVariants() {
        let commands = [
            "Spline spline-mcp.cjs",
            "/Applications/Spline.app/Contents/MacOS/Spline /Applications/Spline.app/Contents/Resources/spline-mcp.cjs",
            "env /Applications/Spline.app/Contents/MacOS/Spline /Applications/Spline.app/Contents/Resources/spline-mcp.cjs",
            "arch -arm64 /Applications/Spline.app/Contents/MacOS/Spline /Applications/Spline.app/Contents/Resources/spline-mcp.cjs",
            "  SPLINE   /Applications/Spline.app/Contents/Resources/SPLINE-MCP.CJS  ",
        ]

        for command in commands {
            XCTAssertTrue(ProcessMonitor.isNoise(command), "Expected Spline MCP noise: \(command)")
        }
    }

    func testKeepsNormalSplineAndDiagnosticCommands() {
        let commands = [
            "Spline",
            "/Applications/Spline.app/Contents/MacOS/Spline project.spline",
            "open -a Spline project.spline",
            "rg spline-mcp.cjs",
            "echo Spline spline-mcp.cjs",
            "node spline-preview.cjs",
        ]

        for command in commands {
            XCTAssertFalse(ProcessMonitor.isNoise(command), "Expected user command: \(command)")
        }
    }

    func testFiltersOfficialBlenderMCPLaunchChain() {
        let commands = [
            "/opt/homebrew/bin/uvx --from git+https://projects.blender.org/lab/blender_mcp.git#subdirectory=mcp --with mcp[cli]<2 blender-mcp",
            "/opt/homebrew/bin/uv tool uvx --from git+https://projects.blender.org/lab/blender_mcp.git#subdirectory=mcp --with mcp[cli]<2 blender-mcp",
            // ProcessSnapshotter.commandString(of:) 的真实 5-token 截断形态。
            "uv tool uvx --from git+https://projects.blender.org/lab/blender_mcp.git#subdirectory=mcp",
            "uvx --from git+https://projects.blender.org/lab/blender_mcp.git#subdirectory=mcp",
            "env uvx --from git+https://projects.blender.org/lab/blender_mcp.git#subdirectory=mcp blender-mcp",
            "arch -arm64 uv tool uvx --from git+https://projects.blender.org/lab/blender_mcp.git#subdirectory=mcp blender-mcp",
            "/Users/test/.cache/uv/archive-v0/test/bin/python /Users/test/.cache/uv/archive-v0/test/bin/blender-mcp",
            "/Users/test/.cache/uv/archive-v0/test/bin/blender-mcp",
        ]

        for command in commands {
            XCTAssertTrue(ProcessMonitor.isNoise(command), "Expected Blender MCP noise: \(command)")
        }
    }

    func testKeepsNormalUVPythonAndBlenderDiagnostics() {
        let commands = [
            "uvx ruff check .",
            "uv tool install ruff",
            "uvx --from git+https://example.com/tools.git blender-helper",
            "uv tool uvx --from git+https://example.com/tools.git",
            "uv tool install --from git+https://projects.blender.org/lab/blender_mcp.git#subdirectory=mcp",
            "python blender-preview.py",
            "rg blender-mcp",
            "echo uv tool uvx blender-mcp",
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

    func testFiltersBundledCodexAppToolsServer() {
        let workingDirectories = [
            "/Applications/ChatGPT.app/Contents/Resources/plugins/openai-bundled/plugins/codex-app-tools",
            "/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/codex-app-tools",
        ]
        let commands = [
            "node ./server.mjs",
            "/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node ./server.mjs",
            "NODE server.mjs",
        ]

        for workingDirectory in workingDirectories {
            for command in commands {
                XCTAssertTrue(
                    ProcessMonitor.isNoise(command, workingDirectory: workingDirectory),
                    "Expected bundled Codex app tools noise: \(command) in \(workingDirectory)"
                )
            }
        }
    }

    func testKeepsUserNodeServerCommands() {
        let commands = [
            "node ./server.mjs",
            "/opt/homebrew/bin/node ./server.mjs",
            "node server.mjs --port 3000",
        ]

        for command in commands {
            XCTAssertFalse(ProcessMonitor.isNoise(command), "Expected user command without cwd: \(command)")
            XCTAssertFalse(
                ProcessMonitor.isNoise(command, workingDirectory: "/Users/test/project"),
                "Expected user project command: \(command)"
            )
            XCTAssertFalse(
                ProcessMonitor.isNoise(command, workingDirectory: "/Users/test/plugins/openai-bundled/plugins/codex-app-tools"),
                "Expected non-app-bundle command: \(command)"
            )
        }
    }
}
