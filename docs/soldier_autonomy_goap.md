# Single-Soldier Autonomous GOAP

## Scope

This layer handles immediate individual reactions. It does not replace squad
planning and it never generates pursuit. Squad directives remain the source of
movement, assault, flank, suppression, and assigned-target behavior.

Priority order:

| Goal | Priority | Purpose |
| --- | ---: | --- |
| `SURVIVE_THREAT` | 300 | Interrupt unsafe activity and obtain protection. |
| `RESPOND_TO_CONTACT` | 180 | Without an active order, identify and briefly answer a contact. |
| `RESTORE_WEAPON` | 130 | Reload an empty weapon when immediate survival is stable. |
| Squad directive | 100 | Execute the current leader order. |
| `MAINTAIN_SECURITY` | 10 | Observe the assigned facing while idle. |

## Behavior Contract

1. A nearby hostile shot, near miss, hit, or visible hostile starts one response cycle.
2. The soldier uses nearby threat-facing cover when available; otherwise it goes prone.
3. Once protected, an existing squad directive resumes immediately.
4. Without a directive, a confirmed visible target is acquired, aimed at, and engaged for a short window.
5. An unseen sound causes orientation and sector scanning, never blind targeted fire.
6. An empty magazine inserts reload before return fire.
7. Repeated perception updates for the same active contact do not restart the response cycle.
8. Autonomous plans contain no `APPROACH_TARGET`; the soldier does not chase without an order.

## Verification Cases

| ID | Input | Expected result |
| --- | --- | --- |
| 1 | No directive, no threat | Select `MAINTAIN_SECURITY`; only `GUARD_SECTOR`; no firing. |
| 2 | Friendly gunshot | Ignore it; no hostile threat memory. |
| 3 | Nearby hostile gunshot | Set immediate threat and open one response cycle. |
| 4 | Immediate threat and nearby valid cover | Plan `SEEK_COVER`, not `DROP_PRONE`. |
| 5 | Immediate threat and no cover | Plan and execute `DROP_PRONE`. |
| 6 | Hit while a squad directive is active | `SURVIVE_THREAT` interrupts priority-100 directive. |
| 7 | Soldier becomes protected | Existing squad directive becomes active again. |
| 8 | Protected soldier sees an in-range hostile | Plan acquire, aim, and short return fire. |
| 9 | Case 8 with empty magazine and reserve ammunition | Insert `RELOAD_COVERED` before return fire. |
| 10 | Unseen threat sector | Orient and scan; no return-fire action. |
| 11 | Same visible contact is scanned repeatedly | Completed response remains complete; no endless autonomous fire loop. |
| 12 | Visible hostile outside weapon range | Scan and wait; no directive movement or autonomous chase. |

Run the focused test with:

```powershell
& 'C:\Users\15309\Desktop\Godot_v4.7-stable_win64.exe' `
  --headless --path 'D:\project\HG' `
  --log-file 'D:\project\HG\.codex-soldier-autonomy-test.log' `
  'res://tests/3d_battles/soldier_autonomy_goap_test.tscn'
```
