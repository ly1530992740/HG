# Weapon Framework Notes

This document records the current weapon framework and the planned follow-up work.

## Current Goal

Build a reusable weapon system where player units, AI units, towers, and later enemy units can all use the same weapon component.

The current implementation focuses on the smallest playable loop:

- Player can equip a firearm.
- Player can fire a projectile toward the mouse position.
- Projectile can damage existing AI enemies through their current `take_damage(damage, source_position)` API.
- Enemies can die through their existing health/death logic.
- Firearm has magazine ammo, reserve ammo, reload time, cooldown, and empty-ammo failure.

## Files Added

```text
weapons/
  weapon_data.gd
  weapon.gd
  firearm_weapon.gd
  projectile.gd
  projectile.tscn
  firearms/
    pistol_weapon.gd
    rifle_weapon.gd
    smg_weapon.gd
```

## Core Classes

### `WeaponData`

Resource used to configure firearm values.

Current fields:

- `weapon_name`
- `damage`
- `knockback`
- `fire_mode`
- `fire_cooldown`
- `burst_count`
- `burst_delay`
- `spread_degrees`
- `magazine_size`
- `reserve_ammo`
- `reload_time`
- `projectile_scene`
- `projectile_speed`
- `projectile_lifetime`
- `hit_groups`
- `shoot_sound`
- `reload_sound`
- `empty_sound`
- `muzzle_flash_scene`

### `Weapon`

Base class for all future weapons.

Responsibilities:

- Stores the `wielder`.
- Stores the `weapon_data`.
- Resolves the muzzle/origin position.
- Defines common API:
  - `equip(owner)`
  - `unequip()`
  - `can_attack()`
  - `try_attack(target_position)`
  - `stop_attack()`
  - `reload()`

### `FirearmWeapon`

Base class for gun-like weapons.

Responsibilities:

- Magazine ammo.
- Reserve ammo.
- Fire cooldown.
- Reloading.
- Semi-auto / auto / burst entry points.
- Projectile spawning.
- Optional muzzle flash and audio.

Important API:

```gdscript
try_attack(target_position: Vector2) -> bool
start_trigger(target_position: Vector2) -> void
update_trigger_target(target_position: Vector2) -> void
stop_attack() -> void
reload() -> bool
add_reserve_ammo(amount: int) -> void
get_total_ammo() -> int
```

Signals:

```gdscript
fired
reload_started
reload_finished
ammo_changed(magazine_ammo, reserve_ammo)
attack_failed(reason)
```

### `Projectile`

Base projectile class.

Responsibilities:

- Move in a straight line.
- Expire after lifetime.
- Detect body/area collision.
- Resolve hurtbox parent where needed.
- Apply damage through the existing project API.

Current damage priority:

```gdscript
target.take_damage(damage, global_position)
target.take_damages(damage)
```

Current default player test weapon hits:

```gdscript
["goblin", "goblinbuildings"]
```

## Player Test Integration

The current test integration is in:

```text
unit/pawn_/pawn.gd
```

When `enable_player_firearm` is true, the pawn creates:

- `WeaponMuzzle`
- `FirearmWeapon`
- default `WeaponData` if no custom data is assigned

Default controls:

- `F`: fire toward mouse position.
- `R`: reload.

The current default test weapon:

```text
Prototype Rifle
damage: 2
fire mode: semi auto
fire cooldown: 0.35
magazine size: 6
reserve ammo: 24
reload time: 1.2
projectile speed: 1300
projectile lifetime: 0.45
hit groups: goblin, goblinbuildings
```

## Child Firearm Classes

Current child classes are intentionally thin:

```text
PistolWeapon extends FirearmWeapon
RifleWeapon extends FirearmWeapon
SmgWeapon extends FirearmWeapon
```

For now, behavior differences should mostly live in `WeaponData`.

Later, child classes can override behavior only when they need truly different logic.

Examples:

- Pistol: fast draw, lower recoil, semi-auto only.
- Rifle: higher damage, longer range, lower fire rate.
- SMG: automatic fire, larger spread, larger magazine.

## Pending Work

### 1. AI Weapon Usage

Not implemented yet.

Planned design:

- AI owns the same `FirearmWeapon` component.
- AI does target selection itself.
- AI calls:

```gdscript
weapon.try_attack(target.global_position)
```

AI should not duplicate ammo, reload, cooldown, or projectile logic.

Pending AI tasks:

- Add `EnemyWeaponController` or integrate with existing enemy state machines.
- Add target selection helpers.
- Add line-of-sight/range checks.
- Add reload behavior when magazine is empty.
- Add friendly-fire/team filtering before enemy units use guns.

### 2. Team / Friendly Fire

Not implemented yet.

Current projectile filtering is group-based through `hit_groups`.

Future design:

```gdscript
func get_team_id() -> int
func is_ally(other: Node) -> bool
```

Projectile can then ask the shooter whether the target is an ally.

### 3. Real Weapon Resources

Currently, the pawn creates a default `WeaponData` in code.

Pending:

- Create `.tres` resources for:
  - pistol
  - rifle
  - smg
- Assign those resources through the inspector.
- Remove hard-coded test data once real unit scenes are wired.

### 4. UI

Not implemented yet.

Pending:

- Ammo display.
- Reload progress.
- Empty ammo feedback.
- Weapon name/icon.
- Optional crosshair.

### 5. Animation

Minimal integration only.

Pending:

- Shoot animation hook.
- Reload animation hook.
- Weapon-hold pose.
- Directional muzzle offsets for up/down/left/right animations.

### 6. Muzzle Flash and Hit Effects

The framework supports `muzzle_flash_scene`, but no dedicated firearm effects have been created.

Pending:

- Muzzle flash scene.
- Bullet impact effect.
- Optional shell casing ejection.

### 7. Sound

The framework supports shoot/reload/empty sounds.

Pending:

- Assign real audio streams to `WeaponData`.
- Tune 2D volume and attenuation.

### 8. Projectile Improvements

Current projectile is simple straight-line movement.

Potential follow-ups:

- Piercing.
- Ricochet.
- Area damage.
- Tracer visuals.
- Projectile knockback.
- Collision mask tuning.

### 9. Existing Weapon Migration

Existing bow/arrow logic is still separate.

Later options:

- Keep bows as their own system.
- Convert bow to `Weapon` + `Projectile`.
- Use `WeaponData` for arrow stats too.

Do not migrate existing bow logic until the firearm path is stable.

## Design Rule

Weapon logic should stay neutral.

The weapon should not know whether it is held by:

- player
- friendly AI
- enemy AI
- tower

The holder/controller decides target and timing.

The weapon decides whether it can fire.

The projectile decides whether a hit applies damage.
