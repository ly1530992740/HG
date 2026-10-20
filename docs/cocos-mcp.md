# Cocos MCP Integration

The repository includes `extensions/cocos-mcp-server`, pinned to upstream commit `a5db895b3299dccd78979ca0268193e4b6ebf037` (release 1.5.4). It targets Cocos Creator 3.8.6+ and is used here with Cocos Creator 3.8.8.

## Enable

1. Open the repository root in Cocos Creator 3.8.8.
2. Open `Extension > Cocos MCP Server`.
3. Start the server on the default loopback port `3000`.
4. The repository MCP client configuration is in `.mcp.json`. Codex's project-scoped configuration is in `.codex/config.toml`; both point to `http://127.0.0.1:3000/mcp`.

The plugin is configured to listen on loopback only. Keep the full tool set enabled for this personal, non-commercial project, but follow the project skill's operation discipline: inspect current state, make an intentional change, save, validate, and record the result.

## Authority and limits

MCP may read and write Cocos scenes, nodes, components, prefabs, assets, project settings, previews, builds, validation state, and logs within this repository. Codex uses the project-scoped `default_tools_approval_mode = "auto"` setting because the user explicitly authorized full local MCP authority. It does not authorize external publishing, remote filesystem changes, Git history changes, or framework contract changes without an explicit framework task.

MCP validation proves editor/project state. It does not replace TypeScript compilation, domain unit tests, integration tests, or coverage reports.

## Licensing

The upstream README states that the plugin and derivative code are for personal/non-commercial use unless separately licensed. This project is currently treated as personal/non-commercial. Reassess the plugin before any commercial distribution.
