# Cocos Module Boundaries

This document defines the target framework contract for business-layer work. It does not claim that every current prototype script already follows the contract. Framework refactors and test-runner implementation are separate tasks; do not silently mix them into feature requests.

## Layers

| Layer | Owns | May depend on | Must not own |
|---|---|---|---|
| Domain | Rules, state transitions, validation, deterministic calculations, domain events | Domain types and explicitly injected ports | Cocos scene graph, rendering, input, global time/randomness, asset loading |
| Application | Use cases and orchestration across domain modules; transaction boundaries | Domain modules and ports | Rendering details or direct editor APIs |
| Cocos adapters | `Component` lifecycle, input translation, Node/Prefab/asset integration, engine events, scheduling | Application/domain APIs and Cocos `cc` APIs | Duplicated business rules or hidden cross-module state mutation |
| Presentation | HUD, feedback, visual adapters, animation/rendering | Read-only view data and presentation ports | Owning authoritative gameplay state or payment/damage rules |
| Composition root | Construct modules, connect ports/events, own scene-level lifetime | All lower layers | Becoming a second implementation of module behavior |

Allowed dependency flow: `Presentation -> Application -> Domain`; Cocos adapters translate between the engine and application/domain interfaces; the composition root can depend on all layers. Domain modules must not import Cocos `cc` or depend on another domain module unless that dependency is explicitly listed below. Cross-domain coordination belongs in Application.

## Domain Ownership

- **Core:** authoritative game/session state, resource ledger, population, day/wave state, and domain event contracts. No gameplay system may bypass its public state operations.
- **Combat:** damage, health, weapons, ballistics, suppression, soldier state, and combat registry. It emits outcomes; it does not directly update economy, HUD, or scene assets.
- **Survival:** inventory, construction, durability, population/work, economy, shop, pickups, stealing, and ally rules. Resource transactions go through Core-owned ledger APIs.
- **AI:** perception snapshots, memory, threat evaluation, utility, planning, role/task assignment, and state transitions. It consumes combat/domain interfaces and emits directives; it does not mutate Cocos nodes directly.
- **Player and Enemy:** engine-facing actor adapters that translate input/scene lifecycle to application commands and domain outcomes. Their files must not become an alternate owner of Combat or Core rules.
- **Resource and Build:** scene adapters for world interactions and production visualization. Gather/build/payment rules belong to the domain/application APIs they call.
- **Wave:** application orchestration for day progression and encounter creation. Spawned scene actors are created through an injected factory/port.
- **HUD:** read-only presentation of state/events and player feedback.
- **Playtest and Tests:** test/demo composition only. They may assemble modules but production modules must not import them.
- **Core/GameRoot and SurvivalDirector:** composition roots. They may wire modules and lifetimes; they should not own reusable business rules.

## Contracts

- One authoritative owner per piece of state. Mutations happen through that owner's API and preserve invariants atomically.
- Cross-module communication uses explicit APIs, application use cases, or typed events. Event listeners must have a defined lifetime and be detached when their owner is disposed/destroyed.
- Avoid cycles. If two modules need each other, move coordination to Application or define a narrow port owned by the caller.
- Keep domain decisions deterministic. Inject random/time/scheduling services at the application boundary.
- Public APIs return typed outcomes for expected failure conditions; do not hide failure behind `any`, silent fallback, or partially applied mutations.
- Scene serialization, Cocos component registration, `.meta` UUIDs, and prefab/scene references are framework-owned integration contracts.

## Change Classification

Business requests may add behavior inside an existing module contract and tests. A change is framework-level if it changes a layer's ownership, a public module API, dependency direction, authoritative state, composition root, event/lifetime contract, project engine/toolchain configuration, or test/coverage infrastructure. For framework work, document the affected contracts and migration path before editing, then verify callers and tests across all affected modules.

## Current Gap

The current prototype mixes some pure rules and Cocos `cc` types in the same modules, and tests are scene-driven. Future framework work should extract deterministic domain logic and establish an automated runner before enforcing coverage gates. Until then, report coverage and editor validation limits accurately.
