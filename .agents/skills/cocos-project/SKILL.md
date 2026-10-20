---
name: cocos-project
description: "Implement, review, test, or change architecture in this Cocos Creator 3.8.8 game project. Use for gameplay code, project scenes and resources, module boundaries, testing, Cocos MCP editor operations, or build validation."
metadata:
  version: "1.0.0"
  project: "HumiliateGod Cocos"
  engine: "Cocos Creator 3.8.8"
---

# Cocos Project Skill

This repository is the active Cocos Creator project. The user owns framework direction; the agent implements requested business behavior within agreed module contracts and participates in framework design when asked.

## Required Workflow

1. Read `AGENTS.md`, confirm the engine version from `package.json`, inspect the requested module, its callers, current worktree state, and relevant tests.
2. Classify the change as business behavior, framework/contract, scene/resource, or tooling. Keep business changes inside the owning module. For framework changes, state the contract and affected modules before editing; implement only what the request requires.
3. Map each changed behavior to unit, integration, scene, and build checks. Add or update tests with the behavior. Do not expand scope to unrelated refactors.
4. Verify the change using the strongest available project-native checks. For editor-dependent behavior, use Cocos preview/MCP where available. Record exact results and distinguish not-run checks from failures.
5. Review the final diff for boundary violations, generated files, missing `.meta` files, dependency direction, and untested changed behavior.

## Non-Negotiable Boundaries

- Repository root is the only active project. Do not recreate or depend on Godot code or project files. `docs/design-archive/` is historical context, not executable specification.
- Preserve Cocos Creator 3.8.8, project UUID, serialization conventions, and existing asset UUIDs unless the user explicitly requests a framework migration.
- Follow `docs/architecture/MODULE_BOUNDARIES.md`; do not bypass module APIs or create cross-module cycles.
- Do not claim line-by-line testing as a goal. Require behavior and branch coverage; pure domain modules target 100% statement and branch coverage. Any exception must be reported with evidence and left explicit for the user to decide.
- A test that only repeats the implementation or asserts a constant without exercising a behavior does not count as meaningful coverage.
- Never edit generated caches or build output. Do not modify unrelated user changes.

## Cocos MCP Authority

The user authorizes full read/write editor control through the configured Cocos MCP server within this repository: scenes, nodes, components, prefabs, Cocos assets, project settings, editor preview, build operations, validation, snapshots, and logs. Use the editor tools needed for the requested task, inspect the current state first, and verify/save the resulting state. This authority does not extend to files outside this repository, remote publishing, Git commits/pushes, or changing the framework contract without a framework task.

## References

- [Module boundaries](../../../docs/architecture/MODULE_BOUNDARIES.md): ownership, layers, allowed dependencies, framework contracts.
- [Coding and testing](references/coding-and-testing.md): TypeScript, deterministic logic, test tiers, coverage and verification.
- [MCP operations](references/mcp-operations.md): editor authority, operation discipline, validation evidence.
- [Scope and migration](references/scope-and-migration.md): repository boundary, Godot archive handling, current migration status.
