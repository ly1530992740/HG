# 3D Squad AI Framework

This document describes the active 3D combat architecture. The superseded 2D
firearm, cover, survival, and squad implementations were removed in July 2026.

## Responsibility Boundaries

```text
SoldierPerceptionComponent3D
  -> delayed contact report
  -> SquadBeliefState3D
  -> SquadDecisionSnapshot3D
  -> SquadInfluenceMap3D
  -> SquadUtilityEvaluator3D
  -> SquadHtnPlanner3D
  -> SquadTaskScheduler3D
  -> SquadDirectiveDispatcher3D
  -> Soldier GOAP
  -> movement, cover, weapon fire cycle, and damage
```

- Perception owns visible and audible evidence. It does not select squad plans.
- Belief owns only reports received by one squad. It is not a global battlefield view.
- The decision snapshot freezes squad members, known contacts, mission state, and fire superiority for one decision.
- The influence map scores only believed threats, authored terrain, cover, and mission pressure.
- Utility ranks legal tactical intents. HTN selects a method and decomposes it into parallel or dependent tasks.
- The scheduler owns task lifecycle; the dispatcher translates tasks into soldier directives.
- Qwen remains an optional experiment only. Formal combat prefabs and defense waves keep it disabled.
- The task graph expresses parallel suppression, reconnaissance, movement, and synchronized attack.
- Individual GOAP handles immediate survival, contact response, weapon recovery, and assigned directives.
- Weapon and suppression components own shot-to-shot combat timing and effects.

## Mission Configuration

`SquadCoordinator3D` supports two map-authored missions:

- `CAPTURE_AND_HOLD`: approach a target area, clear known hostiles, then defend it.
- `ELIMINATE_AND_RETURN`: clear the configured area, then return to the squad origin.

Scenes may assign `mission_target_path` to a `Marker3D`. Runtime spawners use
`set_runtime_mission_target()` before the squad enters combat. A mission limits
legal movement without granting knowledge of unseen enemies.

## Combat Rhythm

`WeaponFireCycle3D` is shared by every `Soldier3D` firearm role. It owns:

- weapon-data aim and reload duration
- target-transfer delay
- bounded automatic bursts
- intra-burst shot interval
- post-burst recovery
- machine-gun setup time and directional fire arc
- setup cancellation after movement

Typical profiles:

| Family | Burst | Special behavior |
| --- | ---: | --- |
| Bolt rifle | 1 | Bolt/recovery delay between shots |
| SMG | 3-7 | Short recovery between bursts |
| LMG | 6-12 | Setup time, limited arc, long recovery |
| Pistol | 1-2 | Fast target transfer |
| Shotgun | 1 | Long recovery and short effective range |

This produces an observable cycle:

```text
CONTACT -> REACT -> COVER -> ACQUIRE -> AIM/SETUP
        -> FIRE BURST -> RECOVER/RELOAD -> REASSESS
```

## Suppression

Suppression is personal; squad fire state is aggregated separately.

- Near misses add suppression with distance falloff.
- LMGs create the widest and strongest suppression corridor.
- Rounds striking `TacticalCover3D` suppress soldiers reserved on its protected side.
- Directionally valid cover reduces near-miss pressure and accelerates recovery.
- Flanked cover does not receive the protected recovery rate.
- `SUPPRESSED` reduces movement and increases spread.
- `PINNED` forces a prone posture and prevents movement and normal firing.
- Cover never scales damage after a hit. A blocked round misses; a penetrating hit deals normal location damage.

## Fire Superiority

`FireSuperiorityAssessment3D` consumes only facts available to the squad:

- known enemy count
- living member roles
- personal suppression and pinned ratio
- available loaded shooters
- current cover occupancy

It outputs `WINNING`, `CONTESTED`, `LOSING`, or `PINNED`. A losing or pinned
squad may select `RECOVER_IN_COVER`, which holds fire briefly and then forces a
new tactical evaluation. The normal evaluation interval is 2.5 seconds; contact,
casualty, mission, and belief changes can request an immediate evaluation.

## Replanning Contract

- Gunshots and near misses change local soldier Actions only.
- Damage repairs the current HTN plan without changing its Utility intent.
- Casualties, mission-state changes, a new defensive attack axis, and completed reconnaissance permit full Utility reconsideration.
- A tactic is not replaced by normal perception churn. Persistent `READY` tasks remain active and only unlock dependencies.
- A standalone fix-and-suppress phase is time-bounded. Suppression duration belongs to the directive, so reloads do not restart it.
- Contacts backed by a destroyed scene object are removed from living-enemy estimates; location-only reports remain valid uncertain contacts.

## Active Tactical Candidates

- `MISSION_MOVE`
- `HOLD_OBJECTIVE`
- `CONTACT_COVER`
- `RECOVER_IN_COVER`
- `DEFEND_CONTACT`
- `RECON_SPLIT`
- `SUPPRESS_AND_FLANK`
- `ESTABLISH_BASE_OF_FIRE`
- `FIX_AND_SUPPRESS`
- `BOUNDING_ADVANCE`
- `DIRECT_ASSAULT`
- `AMBUSH`
- `COUNTER_FLANK`
- `REPOSITION`
- `BREAK_CONTACT`
- `FALLBACK_DEFENSE`
- `SEARCH_LAST_CONTACT`
- `CONSOLIDATE`

Long-running tactics are compiled into tasks. Suppression and movement may run
in parallel, while synchronized attack waits for its dependencies. Unknown
flank routes block bounding advance until reconnaissance is complete. A bound
is limited to five meters rather than sending its maneuver element directly to
the final objective.

## Individual GOAP

Autonomous goals:

- `SURVIVE_THREAT`
- `RESPOND_TO_CONTACT`
- `RESTORE_WEAPON`
- `MAINTAIN_SECURITY`

Directive GOAP composes movement, cover entry, target acquisition, approach,
aim, reload, engagement, guard, and observation. A pinned soldier cannot bypass
the suppression rules through either autonomous or directive actions.

Cover posture is a runtime invariant:

- occupied cover uses hidden and exposed-standing poses instead of ordinary crouch/prone
- ordinary `CROUCH` and `PRONE` requests are rejected while cover is occupied
- hidden covered soldiers cannot aim or fire; weapon-specific randomized firing windows may contain one shot, several shots, or rarely a low-pressure magazine dump
- suppression shortens the current exposure budget; an exhausted budget, empty magazine, or pinned state retracts the soldier and clears aim for the next GOAP cycle
- blind-fire implementation remains reserved and is not currently selectable

## Formal 3D Enemy Configuration

All scenes under `Prefab/Enemy3D`:

- instantiate `ai3d/soldier_3d.tscn`
- use `SquadCoordinator3D`
- enable `use_advanced_tactics`
- disable Qwen and use deterministic tactical selection

`SquadWaveSpawner3D` also forces advanced tactics for custom wave squads and
injects the current map objective. Test-only standalone soldiers are weapon or
damage fixtures and are not formal enemy squads.

## Deferred Work

- explicit smoke deployment and smoke-aware line of sight
- destructible cover and negative-cover terrain
- deployable machine-gun tripod visuals and setup animation
- navigation-mesh pathfinding for arbitrary authored obstacle fields
- blind-fire animation, muzzle origin, spread, and GOAP enablement
- suppression visualization and machine-gun arc debug rendering
- per-limb movement and aim penalties in the 3D injury component
- measured weapon-profile balancing from repeated battle simulations

## Verification

- `SOLDIER_AUTONOMY_GOAP_PASS cases=14`
- `SQUAD_TACTICAL_PIPELINE_PASS cases=30`
- limited-intelligence case study: 10/10 runs completed both route observations and issued the right-grass `SUPPRESS_AND_FLANK`
- COH combat rhythm, battle soak, survival wave, and full 3D migration tests pass
