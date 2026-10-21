# Coding and Testing Rules

## Code Organization

- Put reusable rules and state transitions in the owning domain module. Keep Cocos `Component` lifecycle, `Node`, rendering, input, and asset access at engine-facing boundaries.
- Public module APIs must express intent and own their invariants. Callers must not mutate another module's internal collections or fields to bypass its API.
- Extract shared behavior only when it has a clear owner and at least two real callers. Do not create generic utility modules as a dumping ground.
- Inject time, randomness, and external effects into domain logic. Avoid direct `Date.now`, `Math.random`, timers, editor globals, or scene traversal in deterministic domain rules.
- Keep imports flowing in the direction documented in `docs/architecture/MODULE_BOUNDARIES.md`. Avoid `any`; if an engine or serialization boundary requires it, isolate and validate it there.

## Test Tiers

- **Unit tests:** each pure domain module has its own tests for every public operation, state transition, invalid input, boundary, and event contract. Pure domain modules target 100% statement and branch coverage.
- **Integration tests:** verify behavior across module contracts, including resource transactions, combat outcomes, AI decisions, and system orchestration where applicable.
- **Scene tests:** verify Cocos lifecycle, serialized references, input/UI wiring, scene transitions, prefab behavior, and editor-only interactions.
- **Build checks:** verify the configured Cocos project and target platform when a change affects engine APIs, scenes/resources, settings, or build behavior.

## Test Impact Mapping

Before editing code, list the affected modules and map each behavior to the required test tiers. A test plan that names only a test file is incomplete; it must identify the module contracts being exercised.

For example, a new damage component may affect Combat, Player, and Enemy:

1. Unit tests verify Combat damage rules, health transitions, invalid damage, death, and result events.
2. Integration tests verify that Player attack output reaches Enemy damage handling, and that Enemy attack output reaches Player damage handling through the approved contracts.
3. A temporary scene test creates a player and an enemy, triggers an attack automatically, and asserts the runtime hit and health result through Cocos components and scene wiring.
4. Build checks apply when the feature adds or changes scenes, prefabs, resources, settings, or other build inputs.

The scene test is required evidence for engine behavior; a TypeScript test or type check cannot replace it.

## Temporary Verification Artifacts

Use temporary scenes and scripts when they are the shortest reliable way to verify runtime behavior. Mark them as temporary in the change plan and record every created path. After the verification passes, remove the one-off scene, script, prefab, resource, and related `.meta` files, then inspect the diff for orphaned references. Keep reusable fixtures, test roots, test helpers, and permanent regression tests. If verification fails, keep the temporary artifacts until diagnosis and rerun are complete.

Coverage is measured on production domain logic, not test code, generated files, Cocos engine internals, or serialization glue. Do not exclude a domain branch merely to make a report green. When a branch cannot be exercised or measured, report it as a gap; do not claim full coverage. A test runner and coverage gate are not yet established in this repository, so do not claim the 100% target is met until the tooling exists and produces a report.

## Verification

- Prefer reproducible commands and deterministic fixtures. Include the exact command and result in the completion report.
- Run focused module tests first, then relevant integration/scene tests, type checks, and build checks according to the change.
- For random or time-sensitive behavior, use seeded/fake inputs and test boundary values.
- When Cocos Editor or MCP is unavailable, state which editor checks were not run and why. A TypeScript check alone does not prove scene serialization or runtime behavior.
- Never turn a failed check into a pass by weakening assertions or excluding changed code.
