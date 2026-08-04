# Single-Soldier State Chart

## Contract

`SoldierStateChart3D` executes one squad directive at a time. It does not choose
the squad's tactical intent. The controller uses Godot State Charts `v0.22.5`
for root-state transitions and keeps action execution inside `Soldier3D`.

The plugin states are:

- `Dead`
- `SurvivalOverride`
- `ExecuteOrder`
- `IdleSecurity`

The transition events are `directive_received`, `directive_cleared`,
`danger_detected`, `danger_cleared_with_order`,
`danger_cleared_without_order`, and `actor_died`.

Order states cover movement, cover, attack, suppression, flank,
reconnaissance, sector defense, withdrawal, and structure use. The State Chart
does not contain squad Utility, HTN decomposition, or Scheduler policy.

## Movement Invariant

Every directive route and runtime movement target continues to use
`SquadHeatmapRoutePlanner3D`. The planner scores distance, accumulated threat,
peak threat, suppression, route exposure, cover, concealment, friendly support,
and estimated exposure time. Local steering may add a short physical detour,
but may not bypass the heatmap route or segment-clearance checks.

## Interruption And Resume

Pinned state, immediate fire, or dangerous route exposure sends
`danger_detected`. `SurvivalOverride` preserves the directive version and order
state while it selects emergency cover, a minimum-risk escape, prone
protection, a pinned wait, or bounded return fire. When danger clears, the
chart returns to `ExecuteOrder` when a directive remains, otherwise to
`IdleSecurity`. A survival interruption never emits `directive_completed`.
