# Repository Instructions

This repository is the Cocos Creator 3.8.8 project. Its root is the only active project boundary. Godot is retired; archived design documents are reference material only.

Before implementation work, read [the Cocos project skill](.agents/skills/cocos-project/SKILL.md) and the relevant references linked there. For module ownership, follow [MODULE_BOUNDARIES.md](docs/architecture/MODULE_BOUNDARIES.md).

## Hard Boundaries

- Keep all active project code, scenes, resources, tests, build settings, and project documentation inside this repository.
- Do not add Godot scripts, scenes, project configuration, editor caches, or Godot runtime dependencies.
- Treat `docs/design-archive/` as read-only historical design input. Current implementation contracts live in `docs/architecture/` and this skill.
- Do not edit generated Cocos caches or generated build output (`library/`, `temp/`, `build/`, `profiles/`, `local/`, `native/`).
- Do not change the Cocos Creator engine version, project UUID, scene serialization format, or dependency/build toolchain without an explicit framework task.
- Keep Cocos `.meta` files paired with assets and preserve UUIDs when moving or renaming assets.

## Ownership

The user owns framework direction and approves changes to module contracts, public APIs, dependency direction, root composition, test infrastructure, and build configuration. Implement requested gameplay/business behavior inside those contracts. When a request needs a framework change, explain the smallest required contract change before applying it; continue with independent business-layer work where possible.

## Completion Evidence

Every code or scene change must report its affected module, verification performed, results, and checks not run. Never describe an unexecuted test, preview, or build as passing. Keep changes and validation within this repository.
