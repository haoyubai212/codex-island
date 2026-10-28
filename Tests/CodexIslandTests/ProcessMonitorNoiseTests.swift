import XCTest
@testable import CodexIslandApp

final class ProcessMonitorNoiseTests: XCTestCase {
    func testCategorizesClaudeBeforePromptContents() {
        let commands = [
            "claude",
            "claude -p 'Use git status, curl and agy to review'",
            "/Users/haoyu/.local/bin/claude --resume session",
            "env CLAUDE_MODE=local claude -p 'npm run build'",
            "command claude --version",
            "arch -arm64 claude -p 'Find acpx commands'",
        ]
        for command in commands {
            XCTAssertEqual(ProcessMonitor.categorizeCommand(command), .claude, command)
        }
        XCTAssertEqual(ProcessMonitor.CommandCategory.claude.icon, "clawd")
    }

    func testClaudeMentionsKeepTheirCommandCategory() {
        XCTAssertEqual(ProcessMonitor.categorizeCommand("rg -n claude Sources"), .searching)
        XCTAssertEqual(ProcessMonitor.categorizeCommand("cat claude.md"), .reading)
        XCTAssertEqual(ProcessMonitor.categorizeCommand("echo claude"), .executing)
    }

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

    func testCategorizesBlenderCommandsWithCubeIcon() {
        let commands = [
            "Blender -b blender/rv-world.blend --python render.py",
            "/Applications/Blender.app/Contents/MacOS/Blender -b scene.blend",
            "blenderm render scene.blend",
            "/opt/homebrew/bin/blenderm render scene.blend",
            "env BLENDER_USER_CONFIG=/tmp Blender -b scene.blend",
            "arch -arm64 blenderm render scene.blend",
        ]

        for command in commands {
            let category = ProcessMonitor.categorizeCommand(command)
            XCTAssertEqual(category, .blender, "Expected Blender command: \(command)")
            XCTAssertEqual(category.icon, "cube.fill")
        }
    }

    func testDoesNotCategorizeBlenderTextAsBlenderCommand() {
        XCTAssertEqual(ProcessMonitor.categorizeCommand("rg -n blender Sources"), .searching)
        XCTAssertEqual(ProcessMonitor.categorizeCommand("python3 blender_render.py"), .executing)
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
            "/Users/test/.codex/plugins/cache/openai-bundled/codex-app-tools/0.1.4",
            "/Users/test/.codex/plugins/cache/openai-bundled/codex-app-tools/26.912.10001/",
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

    func testFiltersCodeReviewServerAfterWorkingDirectoryChange() {
        let nodePaths = [
            "/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node",
            "/Applications/Codex.app/Contents/Resources/cua_node/bin/node",
        ]
        for nodePath in nodePaths {
            for command in ["node ./server.mjs", "env node ./server.mjs", "node server.mjs"] {
                XCTAssertTrue(ProcessMonitor.isNoise(
                    command,
                    workingDirectory: "/Users/test/.codex/code-review-plugin/",
                    executablePath: nodePath
                ))
            }
        }
    }

    func testKeepsUserServersAndDiagnosticsNearCodeReviewDirectory() {
        let directory = "/Users/test/.codex/code-review-plugin"
        let bundledNode = "/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node"
        XCTAssertFalse(ProcessMonitor.isNoise("node ./server.mjs", workingDirectory: directory))
        XCTAssertFalse(ProcessMonitor.isNoise(
            "node ./server.mjs", workingDirectory: directory, executablePath: "/opt/homebrew/bin/node"
        ))
        for cwd in ["/Users/test/project", directory + "/examples", directory + "-other"] {
            XCTAssertFalse(ProcessMonitor.isNoise(
                "node ./server.mjs", workingDirectory: cwd, executablePath: bundledNode
            ))
        }
        for command in ["node app.js", "rg server.mjs", "echo node server.mjs"] {
            XCTAssertFalse(ProcessMonitor.isNoise(
                command, workingDirectory: directory, executablePath: bundledNode
            ))
        }
    }

    func testFiltersCodexSecurityServerUsingActualProcessArguments() {
        let node = "/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node"
        let root = "/Users/test/.codex/plugins/cache/openai-curated-remote/codex-security/"
        for entry in ["0.1.32/scripts/../mcp/server.mjs", "0.2.0/mcp/server.mjs"] {
            XCTAssertTrue(ProcessMonitor.isNoise(
                "node server.mjs --stdio",
                executablePath: node,
                processArguments: [node, root + entry, "--stdio"]
            ))
        }
        for prefix in ["node ", "env node ", "arch -arm64 node "] {
            XCTAssertTrue(ProcessMonitor.isNoise(prefix + root + "0.1.32/mcp/server.mjs --stdio"))
        }
    }

    func testKeepsOrdinaryStdioServersAndSimilarPluginPaths() {
        let node = "/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node"
        let root = "/Users/test/.codex/plugins/cache/openai-curated-remote/codex-security/"
        for script in [
            "/Users/test/project/server.mjs",
            root + "0.1.32/examples/server.mjs",
            root + "0.1.32/mcp/user-server.mjs",
            root + "0.1.32/nested/mcp/server.mjs",
            root + "../another-plugin/0.1.32/mcp/server.mjs",
        ] {
            XCTAssertFalse(ProcessMonitor.isNoise(
                "node server.mjs --stdio",
                executablePath: node,
                processArguments: [node, script, "--stdio"]
            ))
        }
        XCTAssertFalse(ProcessMonitor.isNoise("node server.mjs --stdio", executablePath: node))
        XCTAssertFalse(ProcessMonitor.isNoise(
            "node server.mjs --stdio",
            processArguments: [node, "/Users/test/project/server.mjs", root + "0.1.32/mcp/server.mjs"]
        ))
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
            XCTAssertFalse(
                ProcessMonitor.isNoise(command, workingDirectory: "/Users/test/.codex/plugins/cache/openai-bundled/codex-app-tools/0.1.4/examples"),
                "Expected nested user command to remain visible: \(command)"
            )
        }
    }

    func testFiltersBundledUnifiedComputerUseLauncher() {
        let scriptPath = "/Users/test/.codex/plugins/cache/openai-bundled/unified-computer-use/26.901.20858/scripts/launch.mjs"
        let chatGPTNode = "/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node"
        let codexNode = "/Applications/Codex.app/Contents/Resources/cua_node/bin/node"

        XCTAssertTrue(
            ProcessMonitor.isNoise("\(chatGPTNode) \(scriptPath)"),
            "Expected the full bundled launcher command to be filtered"
        )
        XCTAssertTrue(
            ProcessMonitor.isNoise(
                "node launch.mjs",
                executablePath: chatGPTNode,
                processArguments: [chatGPTNode, scriptPath]
            ),
            "Expected the real process snapshot plus full argv to be filtered"
        )
        XCTAssertTrue(
            ProcessMonitor.isNoise("node launch.mjs", executablePath: codexNode),
            "Expected the bundled cua_node fallback to cover Codex.app when argv is unavailable"
        )
    }

    func testKeepsUserLaunchMJSCommands() {
        let chatGPTNode = "/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node"

        XCTAssertFalse(ProcessMonitor.isNoise("node launch.mjs"))
        XCTAssertFalse(
            ProcessMonitor.isNoise(
                "node /Users/test/project/launch.mjs",
                executablePath: "/opt/homebrew/bin/node"
            )
        )
        XCTAssertFalse(
            ProcessMonitor.isNoise(
                "node launch.mjs",
                executablePath: chatGPTNode,
                processArguments: [chatGPTNode, "/Users/test/project/launch.mjs"]
            ),
            "Expected full argv to keep a user script even when launched with cua_node"
        )
        XCTAssertFalse(
            ProcessMonitor.isNoise(
                "node /Users/test/.codex/plugins/cache/openai-bundled/unified-computer-use/26.901.20858/scripts/worker.mjs"
            )
        )
        XCTAssertFalse(
            ProcessMonitor.isNoise(
                "rg -n /Users/test/.codex/plugins/cache/openai-bundled/unified-computer-use/26.901.20858/scripts/launch.mjs"
            )
        )
    }

    func testFiltersCuaREPLLauncher() {
        XCTAssertTrue(ProcessMonitor.isNoise("node cua-repl.mjs"))
        XCTAssertTrue(ProcessMonitor.isNoise("env node cua-repl.mjs"))
    }

    func testKeepsUnrelatedCuaREPLScript() {
        XCTAssertFalse(ProcessMonitor.isNoise("node /Users/test/project/cua-repl.mjs"))
        XCTAssertFalse(ProcessMonitor.isNoise("node cua-repl.js"))
    }

    func testFiltersCuaREPLWithBrowserAccessImport() {
        let loader = "/Users/test/.codex/plugins/cache/openai-bundled/unified-computer-use/26.1023.50603/require-browser-access.mjs"
        for app in ["ChatGPT", "Codex"] {
            let node = "/Applications/\(app).app/Contents/Resources/cua_node/bin/node"
            let entry = "/Applications/\(app).app/Contents/Resources/cua_node/lib/node_modules/@oai/cua-repl/bin/cua-repl.mjs"
            let variants = [
                [node, "--import", "file://" + loader, entry],
                [node, "--import=file://" + loader, entry],
                [node, "--import", loader, entry],
                [node, "--import", "file://" + loader.replacingOccurrences(of: "/test/", with: "/test%20user/"), entry],
            ]
            for argv in variants {
                // Match ProcessSnapshotter's first-five-argv, absolute-path-to-basename display.
                let display = argv.prefix(5).map {
                    $0.hasPrefix("/") ? ($0 as NSString).lastPathComponent : $0
                }.joined(separator: " ")
                XCTAssertTrue(ProcessMonitor.isNoise(
                    display, executablePath: node, processArguments: argv
                ), display)
                XCTAssertTrue(ProcessMonitor.isNoise(argv.joined(separator: " ")), display)
            }
        }
    }

    func testKeepsUserCommandsWithBrowserAccessImport() {
        let node = "/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node"
        let loader = "/Users/test/.codex/plugins/cache/openai-bundled/unified-computer-use/26.1023.50603/require-browser-access.mjs"
        let entry = "/Applications/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules/@oai/cua-repl/bin/cua-repl.mjs"
        let variants = [
            [node, "--import", "file://" + loader, "/Users/test/project/cua-repl.mjs"],
            [node, "--import", "file:///Users/test/project/require-browser-access.mjs", entry],
            [node, "--import", "file://" + loader, "/Users/test/project/cua-repl/bin/cua-repl.mjs"],
            [node, "--import", "file://" + loader.replacingOccurrences(of: "/26.1023.50603/", with: "/26.1023.50603/examples/"), entry],
            [node, "--import", "file://" + loader.replacingOccurrences(of: "require-browser-access.mjs", with: "other.mjs"), entry],
            [node, "/Users/test/project/inspect.mjs", "--import", "file://" + loader, entry],
            ["rg", "--import", "file://" + loader, entry],
        ]
        for argv in variants {
            let display = argv.prefix(5).map {
                $0.hasPrefix("/") ? ($0 as NSString).lastPathComponent : $0
            }.joined(separator: " ")
            XCTAssertFalse(ProcessMonitor.isNoise(
                display, executablePath: node, processArguments: argv
            ), display)
            XCTAssertFalse(ProcessMonitor.isNoise(argv.joined(separator: " ")), display)
        }
        XCTAssertFalse(ProcessMonitor.isNoise(
            "node --import file://" + loader + " cua-repl.mjs", executablePath: node
        ), "A collapsed entry without full argv is insufficient evidence")
        XCTAssertFalse(ProcessMonitor.isNoise(
            "node cua-repl.mjs", executablePath: node,
            processArguments: [node, "/Users/test/project/cua-repl.mjs"]
        ))
    }

    func testFiltersCodexSandboxWorkers() {
        XCTAssertTrue(ProcessMonitor.isNoise("node --experimental-vm-modules kernel.js --session-id abc"))
        XCTAssertTrue(ProcessMonitor.isNoise("node --experimental-vm-modules trusted-worker.js /Users/test/project"))
    }

    func testKeepsUnrelatedExperimentalNodeScripts() {
        XCTAssertFalse(ProcessMonitor.isNoise("node --experimental-vm-modules test-worker.js"))
        XCTAssertFalse(ProcessMonitor.isNoise("node kernel.js"))
    }

    func testFiltersBundledArtifactTemplatePickerServer() {
        let chatGPTNode = "/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node"
        let chatGPTScript = "/Applications/ChatGPT.app/Contents/Resources/artifact-template-picker/server.mjs"
        let codexNode = "/Applications/Codex.app/Contents/Resources/cua_node/bin/node"
        let codexScript = "/Applications/Codex.app/Contents/Resources/artifact-template-picker/server.mjs"

        XCTAssertTrue(
            ProcessMonitor.isNoise(chatGPTNode + " " + chatGPTScript),
            "Expected the full ChatGPT artifact template picker command to be filtered"
        )
        XCTAssertTrue(
            ProcessMonitor.isNoise(
                "node server.mjs",
                executablePath: chatGPTNode,
                processArguments: [chatGPTNode, chatGPTScript]
            ),
            "Expected the real process snapshot plus full argv to be filtered"
        )
        XCTAssertTrue(
            ProcessMonitor.isNoise(codexNode + " " + codexScript),
            "Expected the Codex.app bundled variant to be filtered"
        )
        XCTAssertTrue(
            ProcessMonitor.isNoise("node server.mjs", executablePath: chatGPTNode),
            "Expected bundled cua_node fallback when argv is unavailable"
        )
    }

    func testKeepsUserServerMJSCommandsWithProcessArguments() {
        let chatGPTNode = "/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node"

        XCTAssertFalse(ProcessMonitor.isNoise("node server.mjs"))
        XCTAssertFalse(
            ProcessMonitor.isNoise(
                "node /Users/test/project/server.mjs",
                executablePath: "/opt/homebrew/bin/node"
            )
        )
        XCTAssertFalse(
            ProcessMonitor.isNoise(
                "node server.mjs",
                executablePath: chatGPTNode,
                processArguments: [chatGPTNode, "/Users/test/project/server.mjs"]
            ),
            "Expected full argv to keep a user server even when launched with cua_node"
        )
        XCTAssertFalse(
            ProcessMonitor.isNoise(
                "node /Users/test/project/artifact-template-picker/server.mjs"
            )
        )
        XCTAssertFalse(
            ProcessMonitor.isNoise(
                "rg -n /Applications/ChatGPT.app/Contents/Resources/artifact-template-picker/server.mjs"
            )
        )
    }

    func testFiltersChatCutMCPServer() {
        let executablePath = "/Applications/ChatCut.app/Contents/MacOS/ChatCut"
        let fullCommand = "\(executablePath) /Applications/ChatCut.app/Contents/Resources/app.asar/out/main/mcp/server.js"

        XCTAssertTrue(ProcessMonitor.isNoise(fullCommand))
        XCTAssertTrue(
            ProcessMonitor.isNoise("ChatCut server.js", executablePath: executablePath),
            "Expected the process snapshot's two-token ChatCut MCP form to be filtered"
        )
        XCTAssertTrue(
            ProcessMonitor.isNoise("ChatCut server.js"),
            "Expected two-token ChatCut server.js to be filtered when executablePath is nil"
        )
    }

    func testKeepsUnrelatedServerJSCommands() {
        XCTAssertFalse(ProcessMonitor.isNoise("node server.js"))
        XCTAssertFalse(
            ProcessMonitor.isNoise(
                "ChatCut server.js",
                executablePath: "/Users/test/bin/ChatCut"
            )
        )
        XCTAssertFalse(
            ProcessMonitor.isNoise(
                "ChatCut project.chatcut",
                executablePath: "/Applications/ChatCut.app/Contents/MacOS/ChatCut"
            )
        )
    }
}
