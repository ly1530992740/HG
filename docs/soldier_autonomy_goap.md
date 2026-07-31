# Single-Soldier Autonomous GOAP

## Scope

This layer follows the useful F.E.A.R. pattern: personal working memory, forward
A* planning, contextual tactical positions, runtime action validation, and
interruptible execution. In normal squad combat the leader directive remains the
GOAP Goal. Immediate danger repairs the Action chain inside that Goal instead of
replacing the ordered objective.

Priority order:

| Goal | Priority | Purpose |
| --- | ---: | --- |
| Squad directive | Dynamic | Execute the current leader order and insert legal safety Actions when threatened. |
| `SURVIVE_THREAT` | Fallback | Obtain protection only when no directive exists. |
| `RESTORE_WEAPON` | Fallback | Reload an empty weapon while idle and safe. |
| `MAINTAIN_SECURITY` | Fallback | Observe the assigned facing while idle. |

## Behavior Contract

1. Visual contact alone never makes an unordered soldier crawl, chase, or open fire.
2. A hit or severe near miss inserts nearby threat-facing cover before the current directive continues.
3. With no usable cover, severe open-ground danger inserts prone and wait; lesser danger inserts knee and wait.
4. Emergency cover search reaches 15 meters.
5. Friendly sounds are ignored and radio reports remain uncertain personal knowledge.
6. Without a directive, the soldier only maintains security or restores its weapon.
7. Autonomous plans contain no directive movement or target-chase Action.
8. Cover posture is separate from ordinary stance: pinned soldiers hide behind occupied cover, while crouch and prone remain open-ground postures only.
9. Occupied cover has two poses: hidden and exposed standing. A soldier must expose to aim or fire, then retracts after a weapon-specific randomized firing window and replans `AIM -> ENGAGE`; suppression shortens the window, while low-pressure automatic fire may rarely continue until the magazine is empty. Blind fire remains unavailable.

## Verification Cases

| ID | Input | Expected result |
| --- | --- | --- |
| 1 | No directive, no threat | Select `MAINTAIN_SECURITY`; only `GUARD_SECTOR`; no firing. |
| 2 | Friendly gunshot | Ignore it; no hostile threat memory. |
| 3 | Visual hostile without an order | Stay standing; report and guard; do not fire or chase. |
| 4 | Severe threat and valid cover within 15 m | Keep the Directive Goal and insert `SEEK_COVER`. |
| 5 | Severe open-ground threat without cover | Insert and execute `DROP_PRONE`, then wait. |
| 6 | Nonsevere danger during movement | Insert `TAKE_KNEE` and `WAIT_FOR_OPENING`; preserve ordered movement. |
| 7 | Radio-only contact | Retain reduced-confidence memory; do not investigate or fire without an order. |
| 8 | Empty weapon while idle | Select `RESTORE_WEAPON` and `RELOAD_SAFE`. |
| 9 | `PRONE` requested while in cover | Clamp to `CROUCH`. |
| 10 | Covered soldier aims | Stand before aim completion. |
| 11 | Covered soldier is crouched | Reject normal fire and disabled blind-fire GOAP. |
| 12 | Covered engagement ends | Return to `CROUCH`. |
| 13 | Two soldiers reserve one cover | Receive distinct slots. |
| 14 | World precondition changes after planning | Invalidate stale Action and replan. |

## F.E.A.R.-Style Supporting Systems

- Facts retain source, position, confidence, direct-observation status, timestamps, and expiry.
- Squad reports enter personal memory at reduced confidence and never grant visual targeting.
- Equal-relevance arbitration keeps the current goal to prevent action thrashing.
- Interrupt priority and action interruptibility protect critical transitions.
- The planner falls back to the next relevant goal when a higher goal has no valid plan.
- Actions validate live preconditions before and during execution and replan on invalidation.
- Tactical cover slots are scored and reserved so agents do not select the same opportunity.

Run the focused test with:

```powershell
& 'C:\Users\15309\Desktop\Godot_v4.7-stable_win64.exe' `
  --headless --path 'D:\project\HG' `
  --log-file 'D:\project\HG\.codex-soldier-autonomy-test.log' `
  'res://tests/3d_battles/automated/soldier_autonomy_goap_test.tscn'
```
