# Scope and Migration

## Active Boundary

The repository root is the Cocos Creator 3.8.8 project root. Active code belongs under `assets/scripts/`; scenes and prefabs belong under `assets/scenes/` and `assets/prefabs/`; Cocos resources belong under `assets/`; project settings stay under `settings/`; architecture and operational documentation stay under `docs/`.

Do not add Godot runtime code, Godot scenes/resources, `project.godot`, Godot editor configuration, or Godot dependencies. Do not use Godot implementation documents as current API instructions.

## Historical Design

`docs/design-archive/` contains selected game design material retained from the retired Godot project. It can inform gameplay intent, terminology, and unresolved design questions. Its file paths, class names, implementation status, code snippets, engine assumptions, and acceptance commands are historical and must not be copied into Cocos implementation plans without revalidation.

## Current Status

The project is in the design and architecture bootstrap phase. Existing files under `assets/scripts/CodeBackUp/` are legacy source material only; they are not production modules and must not be treated as the current implementation. No target module should be inferred from that material. New production code may begin only after the user approves the relevant `TARGET` `assets/scripts/MODULE_MAP.md` files and must follow `docs/architecture/MODULE_BOUNDARIES.md`. The current tests are not a complete unit-test harness, and automated 100% domain coverage has not been established.
