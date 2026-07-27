# Squad AI Framework

This document tracks the implemented squad, tactical, suppression, and psychological systems, plus the remaining GOAP decomposition work.

## Implemented Foundation

```text
ai/squad/
  squad_order.gd
  squad_blackboard.gd
  squad_member.gd
  squad_coordinator.gd
```

### SquadOrder

A versioned command object. Current command types:

```text
HOLD
TAKE_COVER
SUPPRESS
FOCUS_FIRE
ADVANCE
RETREAT
STAY_HIDDEN
```

An order can contain:

- issuer
- target and target position
- assigned cover
- priority
- expiration time
- optional recipients; an empty list means broadcast to the whole squad

### SquadBlackboard

Shared squad facts and signals:

- member list
- current leader
- latest order and order version for debugging
- active broadcast order plus member-specific orders
- shared target
- ally/player counts
- force ratio
- initial squad strength and casualties
- leader alive state

### SquadMember

Reusable component created by `GoblinBase`.

- registers with a coordinator that has the same `squad_id`
- receives broadcast or member-specific orders
- displays `LEADER` or `MEMBER` overhead
- mirrors order facts into a GOAP world state when a `GoapAgent` is present

### SquadCoordinator

- discovers members by `squad_id`
- randomly elects a leader after registration
- elects a replacement after leader death
- publishes broadcast or member-specific orders
- owns the shared blackboard

The firearm test scene currently has three `GoblinShooter` instances and one coordinator.

## Implemented Module 1: Tactical Posture

Force-ratio policy lives in a separate evaluator:

```text
SquadTacticalEvaluator
  input: blackboard facts and recent combat events
  output: ASSAULT, BALANCED, DEFENSIVE, ROUT
```

Current hysteresis thresholds:

- enter `ASSAULT` only when effective force ratio is at least `4.0`; leave below `3.2`
- enter `DEFENSIVE` below `0.9`; leave above `1.1`
- use `BALANCED` between those states

Hysteresis and a posture cooldown are required so one death does not make the leader switch orders every frame.

The posture selects which orders the leader may issue. It should not move soldiers directly.

## Implemented Module 2: Individual Will

Keep baseline personality separate from mutable combat state.

```text
WillProfile (mostly stable)
  INDOCTRINATED
  REGULAR
  TIMID

MentalState (changes during combat)
  ZEALOUS
  STEADY
  AFRAID
  RECOVERING
  BROKEN
  SURRENDERED
```

The profile supplies weights such as obedience, self-preservation, courage, and surrender tendency. The mental state applies temporary modifiers.

`AFRAID` is latched for a profile-adjusted minimum duration. Recovery requires low morale pressure, valid cover, low suppression, and several uninterrupted seconds without a threat. It then enters `RECOVERING` before returning to a stable state. Minor near misses cannot bounce a recovering soldier directly between `AFRAID` and `STEADY`; damage and ally death remain severe shocks.

GOAP integration must change both layers:

- Goal priority decides whether obeying, surviving, fleeing, or surrendering is selected.
- Action cost decides how that selected goal is achieved.

Changing only action cost cannot implement obedience because this GOAP plugin chooses the highest-priority valid Goal before comparing action plans.

## Implemented Module 3: Suppression And Morale

Fast tactical suppression and slow morale pressure are separate systems.

`SuppressionComponent` receives near misses, cover impacts, damage, and ally deaths. It decays quickly and controls short-term accuracy, waiting, blind fire, and whether a soldier is pinned. Its levels are `CALM`, `ALERT`, `PINNED`, and `OVERWHELMED`.

`WillComponent` receives smaller, slower morale impulses plus persistent context such as health, force ratio, casualties, leader survival, and cover. It controls stable mental state and GOAP goal priorities.

Suggested pressure inputs:

- personally damaged
- bullet near miss
- focused fire duration
- nearby ally death
- leader death
- force ratio
- time isolated from allies
- time safely in cover
- time without player aggression

Suppression may change rapidly because it represents immediate incoming fire. Mental state deliberately changes slowly and uses entry holds, minimum durations, recovery conditions, and an intermediate recovery state.

Do not permanently rewrite `WillProfile` during a short fight. If permanent conditioning is desired later, store it as progression data outside the moment-to-moment mental state.

## GOAP Decomposition Still Required

The current implementation executes each squad order through a reusable `SquadCommandAction`, while its movement, cover stance, peek timing, and firearm behavior are still performed procedurally by `GoblinShooter`. This is functional, but it limits the planner to choosing commands instead of composing detailed firefight plans.

Goals:

```text
ObeySquadOrderGoal
PreserveLifeGoal
EngageEnemyGoal
FleeGoal
SurrenderGoal
```

Actions:

```text
MoveToCoverAction
StayHiddenAction
BlindFireAction
PreciseFireAction
SuppressTargetAction
AdvanceAction
RetreatAction
FleeAction
SurrenderAction
```

Recommended implementation order:

1. Split `SquadCommandAction` into atomic cover and firearm actions without changing squad orders.
2. Add cover-validity loss and `RelocateCoverAction`.
3. Add explicit burst/ammunition facts so GOAP can chain `Reload`, `WaitInCover`, and `AttackFromCover`.
4. Add flee and surrender only after navigation destinations and surrender gameplay consequences are defined.

## Implemented Module 4: Finite Perception And Ambush ROE

The firearm AI no longer selects tactical targets directly from global groups. Global groups are now only a perception broad phase.

```text
PerceptionComponent
  -> CombatContact memory
  -> delayed SquadCoordinator report
  -> AMBUSH or COMBAT contact phase
  -> role-specific squad orders
  -> GOAP execution
  -> RulesOfEngagement weapon gate
```

Implemented perception rules:

- Visual acquisition requires range, field of view, line of sight, and accumulated detection time.
- `initial_facing_direction` defines the first observation sector; movement updates facing afterward.
- Gunshots create hearing stimuli and reveal a hostile shooter with lower-confidence contact memory.
- Contacts store last-known position, age, confidence, current visibility, stimulus type, and estimated enemy awareness.
- `AlertComponent` is cognitive state, independent from the test scene's locked morale: `UNAWARE`, `SUSPICIOUS`, `SEARCHING`, `OBSERVING`, `CONTACT`, `COMBAT`.
- A confirmed contact is reported after a randomized communication delay. A report is discarded if its observer dies before delivery.
- Squad strength estimates count known contacts, not every hostile node in the scene.

Implemented ambush rules:

- An apparently unaware target starts `AMBUSH_SETUP` under `WEAPONS_HOLD`.
- `AMBUSH_POSITION` assigns role-dependent standoff distances: marksmen and machine gunners stay behind riflemen, while shotgunners and scouts close farther forward.
- The squad opens fire when at least 70 percent are ready, the target becomes aware, a squad member is threatened, danger-close is reached, or the setup times out.
- Opening fire changes ROE to `WEAPONS_FREE` and transitions into the existing suppression-and-flank plan.
- `WEAPONS_TIGHT` is available for future identification-sensitive scenarios. It only permits fire on a currently visible contact.
- `WEAPONS_FREE` still requires current visibility for normal fire. An explicit `SUPPRESS` order may fire at remembered contact position.

Implemented search rules:

- A squad in `SEARCH` no longer remains on `HOLD`. The coordinator periodically publishes member-specific `SEARCH_AREA` destinations.
- Search movement leaves stale cover and advances toward the last reported contact position. Without a previous contact, the squad searches along its current facing direction.
- Search formation keeps marksmen and machine gunners behind riflemen while shotgunners and scouts form the forward screen.
- Search remains under `WEAPONS_HOLD`; confirmed contact must still pass through delayed reporting before ambush or direct-combat ROE is selected.
- The firearm test scene keeps the wide `0.32` zoom but moves its battle camera with the player.
- The current firearm test scenario is deterministic: Alpha faces and searches east, while Bravo faces east with search movement disabled. This creates a repeatable rear-contact ambush instead of a symmetric face-to-face detection race.

Still deferred:

- vision-sector visualization and editor tuning tools
- uncertain target classification and friendly/civilian identification
- search patterns around stale last-known positions
- radio range, jamming, message relay, and command latency by distance
- exposure-scored paths and cover-aware ambush position queries
- coordinated multi-target contact tracks instead of sharing a live target actor reference
- incapacitation, casualty recovery, and medical behavior

## Current Firefight Rules

- The engagement clock starts only after a delayed contact report reaches the squad. Local detection before transmission does not become squad knowledge.
- A compromised or gunshot-revealed first contact broadcasts `TAKE_COVER`. An unaware target instead starts role-based `AMBUSH_POSITION` orders under `WEAPONS_HOLD`.
- After direct contact, `initial_cover_duration` (currently 8 seconds) prevents `ADVANCE`. Exposed members keep receiving `TAKE_COVER`; once a member is safely covered, the coordinator may assign that member to suppress while the others finish moving.
- After the opening cover phase, `ASSAULT` is reserved for at least a 4:1 effective advantage and only has a configurable chance (`assault_charge_chance`, currently 22 percent per order interval) to broadcast `ADVANCE`.
- `BALANCED` and `DEFENSIVE` postures prioritize cover before suppression or focused fire.
- Shooters stop moving once a target is inside firearm range unless an explicit `ADVANCE` or `RETREAT` order is active.
- Focus-fire and suppression actions enter valid cover before firing. Cover reservations prefer a wall side opposite the current threat.
- Cover protection is binary: the wall either blocks the projectile or the projectile passes and deals normal hit-location damage. Cover never scales damage after a hit.
- Near misses, cover impacts, and wounds build fast suppression. High suppression increases spread and favors waiting or blind fire.
- Precision fire uses short randomized peek windows separated by concealed intervals. Threat responses are re-evaluated while fire continues rather than being randomly fixed for an entire command.
- Cover slots allow limited movement along the wall without allowing actors to leave their reserved space.
- Projectile hits use weighted locations: head and heart are fatal, arm wounds increase spread, and leg wounds reduce movement speed.
- Firearm-test players are invulnerable so enemy behavior can be observed continuously.
- The player crosshair follows the mouse and expands with weapon spread, blind-fire spread, and injury modifiers.
- Each shooter carries a reusable `FirearmWeapon` and `MeleeWeapon`. `CloseCombatGoal` may interrupt firearm orders inside `melee_trigger_distance`, executes `MeleeEngageAction`, and returns to the firearm after distance opens.
# 双队交战与阵营

- `GoblinBase.combat_team` 是可复用的阵营标识，所有战斗单位加入 `combatant` 组。
- `GoblinBase.can_damage_target()` 是目标选择、弹丸、近战和压制判定的统一友军过滤入口。
- `can_target_players` 可让测试小队忽略玩家观察者；普通敌人默认仍会攻击玩家。
- `SquadCoordinator` 按敌对战斗单位而非固定的 `player` 组统计兵力、计算态势并选择共享目标。
- 同一场景可放置多个不同 `squad_id` 的协调器；各协调器只注册本小队成员，独立选举队长和发布命令。
- `tests/firearm_test/firearm_test_scene.tscn` 现包含 `alpha` 蓝队与 `bravo` 红队各八人，双方共享同一套枪手、GOAP、掩体、心理和受伤系统。

## 兵种与混合战术

测试战场现为 `8v8`，每队固定编成：

```text
3 Rifleman
1 Marksman
1 Machine Gunner
2 Shotgunner
1 Pistol Scout
```

所有兵种复用 `GoblinShooter`，通过 `SquadCombatRole.Type` 创建不同的武器子类、射程和移动偏好。每名 AI 仍会创建 `MeleeWeapon` 和 `MeleeEngageAction`，敌人进入近距离后可以统一切换近战武器。

角色职责：

- `Machine Gunner`: 优先执行 `SUPPRESS`，形成火力基点或撤退后卫。
- `Marksman`: 优先执行 `OVERWATCH`，留在后排掩体进行精确射击。
- `Shotgunner`: 在压制火力建立后执行左右侧翼机动，进入近距离作战。
- `Pistol Scout`: 高机动侧翼与侦察角色，不承担持续压制。
- `Rifleman`: 通过 `FOCUS_FIRE` 固定敌人；缺少机枪时可临时担任压制手。

当前采用分层决策，而不是让单兵 GOAP 规划整场战斗：

```text
SquadCoordinator tactical evaluation
  -> CONTACT_TO_COVER / SUPPRESS_AND_FLANK / HOLD_DEFENSIVE_LINE / COVERING_RETREAT
  -> role-specific orders and tactical positions
  -> individual GOAP action planning
  -> cover movement, overwatch, suppression, flank, retreat, or melee
```

`FLANK_LEFT`、`FLANK_RIGHT` 和 `RETREAT` 命令会携带 `target_position`。协调器根据敌我中心线、垂直侧翼方向、兵种交战距离和通道序号生成不同目标点，因此侧翼成员不会继续直线追逐同一个目标。

测试场景启用 `lock_steady_morale`：个人心理永远保持 `STEADY`，但受伤、压制、掩体判断和基于伤亡/兵力比的小队撤退仍然有效。正式敌人默认不锁定心理状态。

### 后续战术位置升级

当前侧翼点属于几何编队点。进一步提高真实性时，应引入战术位置查询与评分：

- 路径是否可达以及路径暴露时间
- 对目标的视线、射程带和射击角
- 掩体方向与掩体剩余槽位
- 敌方机枪火力扇区和近期弹道密度
- 队友拥挤、交叉火力和友军射线
- 侧翼通道是否已经被敌人封锁
