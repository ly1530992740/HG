# Cocos MCP Operations

The user authorizes full editor access within this repository. Use scene, node, component, prefab, asset, project-settings, validation, preview/build, and log tools when they help the requested work. This is high-trust project access, not a read-only policy.

## Operation Discipline

- Confirm the connected editor is open on this repository and inspect the current scene/project state before mutation.
- Keep each MCP operation tied to the requested outcome. Prefer a small set of deliberate edits over broad generated edits.
- Save changed scenes/resources and inspect the resulting hierarchy, component properties, UUID/reference integrity, and validation output.
- For runtime behavior, run preview or the relevant test scene and inspect editor logs. For build-affecting changes, run the requested target build when the environment supports it.
- Record tools/checks used and actual results. MCP validation is evidence about editor/project state, not proof of pure logic branch coverage.

## Scope

Full read/write permission applies only to the local Cocos project at the repository root. It does not authorize touching paths outside the repository, deploying/publishing externally, changing Git history, committing or pushing without an explicit request, or redefining framework contracts without a framework task. Do not treat historical files in `docs/design-archive/` as live editor assets.
