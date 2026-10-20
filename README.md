# HumiliateGod Cocos Project

This repository is now centered on the Cocos Creator 3.8.8 project. The repository root is the Cocos project root.

## Project Rules

- Read [AGENTS.md](AGENTS.md) before changing project files.
- The active project skill is [`.agents/skills/cocos-project/SKILL.md`](.agents/skills/cocos-project/SKILL.md).
- Module ownership and dependency direction are defined in [docs/architecture/MODULE_BOUNDARIES.md](docs/architecture/MODULE_BOUNDARIES.md).
- Historical game design references are in [docs/design-archive/](docs/design-archive/). They are not current implementation instructions.

## Open in Cocos Creator

Open this repository root with Cocos Creator 3.8.8. The project version is recorded in `package.json` and `settings/v2/project.json`.

The current prototype scripts and scenes are under `assets/`. Runtime logic is still being organized; do not infer that a module is fully implemented or tested from its directory name.

## Validation

The current test scenes live in `assets/scenes/tests/` and require Cocos Creator preview. They are integration smoke tests, not a complete unit-test or coverage system. Follow the active skill's verification policy and report any unavailable checks as not run.
