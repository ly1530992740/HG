# Scope and Migration

## Active Boundary

The repository root is the Cocos Creator 3.8.8 project root. Active code belongs under `assets/scripts/`; scenes and prefabs belong under `assets/scenes/` and `assets/prefabs/`; Cocos resources belong under `assets/`; project settings stay under `settings/`; architecture and operational documentation stay under `docs/`.

Do not add Godot runtime code, Godot scenes/resources, `project.godot`, Godot editor configuration, or Godot dependencies. Do not use Godot implementation documents as current API instructions.

## Historical Design

`docs/design-archive/` contains selected game design material retained from the retired Godot project. It can inform gameplay intent, terminology, and unresolved design questions. Its file paths, class names, implementation status, code snippets, engine assumptions, and acceptance commands are historical and must not be copied into Cocos implementation plans without revalidation.

## Current Status

The repository has prototype Cocos gameplay modules and editor-run test scenes. Module names do not imply production readiness. The current tests are not a complete unit-test harness, and automated 100% domain coverage has not been established. Treat the boundaries in `docs/architecture/MODULE_BOUNDARIES.md` as the target contract; identify existing code that crosses them rather than silently expanding those exceptions.
