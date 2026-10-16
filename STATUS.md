# Project status

Owner: Claude Code. This file records what the code actually does and how each claim was checked. The rules and design decisions live in `CLAUDE.md` (owned by the designer and Claude Chat). Claude Code updates this file in every task that changes anything listed here and shows its diff in the report. Claude Chat reads it but does not edit it; report mismatches to Claude Code instead.

Last synced with code commit: `1c148c6`. Update this line whenever this file changes.

## Status (as of 2026-10-16, verify against the code)
Three levels of evidence are used below:
- **Verified**: the user ran it in Godot.
- **Headless**: Claude Code ran it with the Godot executable and reported it (167 scripts, scenes and resources load (163 before Task I); the world scene runs 600 frames without errors; 108 logic checks passed in Task I (81 after Task H, 63 after Task G, 54 after Task F). The 38 in earlier reports was a miscount; Task E counted 36).
- **Written**: not run.

Task letters used below map to commits: Task D = `c1cbdff`, Task E = `814f2ce`, Tasks F and G = `63afff2` (one commit), Task H = `43fe19e`, Task I = uncommitted at the time of writing (commit hash to be added).

Verified:
- Burn and Chill, triggered with B / C, apply and are removed on expiry. Burn tick damage and ramp (checked before the ramp retune).
- Run persistence through the F3 player respawn only. Room transitions are not implemented, so a real room change is untested.

Headless:
- Impact-burst mechanism (Task I, uncommitted): an `ON_HIT` burst gives a neighbor in range `damage_fraction` of the hit, leaves a neighbor out of range and the primary target alone, and runs one frame after `take_hit` returns. An `ON_CRIT` burst fires only on a crit and uses the crit hit's final damage. Bursts do not recurse (each neighbor is hit once, with `is_burst` true and no bursts), never crit and carry no statuses. `per_enemy_bonus` and its cap, a missing `AOE_RADIUS` (no burst, one warning), the ledger resolver (dedup by `burst_id`, no leak to another slot), the cast-time fill and `payload.duplicate` all check out. A burst also ran correctly when `take_hit` was called from a real physics callback (a projectile's `area_entered`), with no space-state error. Not run: `effect_scene` spawning (the test bursts have none), any visual, and play in the editor.
- Burn ticks, ramp (0.10 / 0.5, read from `burn.tres`), refresh, expiry and death cleanup (the logic test was re-run after the hand edit, Task E). Chill slow and tag removal. Refcounted tags. Caveat on Burn expiry: the logic test's check named "burn run to expiry" ended in `or true` and could never fail. It was in the repo from `814f2ce` (2026-10-15) until `09b3456` (2026-10-16), when it became a real assertion (effect list empty and `BURNING` released). Real Burn expiry checks first appeared with Task F (`63afff2`, 2026-10-15: "burn lasted exactly" and "refreshed burn expires"), so the Task E claim of Burn expiry rested only on the vacuous check.
- Fire levels 1 to 3 (Task F): duration 3.0 / 6.0 / 9.0 s, ramp cap 0.6 / 0.7 / 0.8, multiplier 1.3 at 3.0 s at level 1 and 1.8 at 8.0 s at level 3. A cast without Fire carries no status. A duration-0 application does nothing. A refresh takes the latest ramp cap bonus.
- Fire and Frost statuses carried on payloads.
- The Overclock offer appears as the only forced card and does not repeat. Overclock cap changes.
- The pending-level write-through.

Written (needs a hand check): B and C key presses (B now uses a 3.0 s `debug_duration_bonus`), the draft screens (including the reworked Fire card) (offer, level-up, infusion), a bolt hit applying a status to an enemy, and a room transition with queued drafts.

Build state of the design decisions in `CLAUDE.md` (moved here from the Combat design decisions section, which now states decisions only):
- **Two stats on every ability:** decided Oct 15, built for Arcane Bolt only (`BASE_DAMAGE` 1.0, `DOT_DAMAGE` 0.15). No other ability exists yet.
- **Fire deals no damage itself:** built and checked Headless in Task F (`63afff2`). `STATUS_RAMP_CAP` is `Stat.Type` 19. Level 1 gives 3.0 s and a 0.1 cap bonus, level 3 gives 9.0 s and 0.3 (cap 0.8).
- **Burn ramp:** the designer edited `burn.tres` to 0.10 / 0.5 by hand on 2026-10-15; until then the shipped file was 0.25 / 1.0. The logic test passes with the new values (Task E, `814f2ce`, Headless).
- **Indirect infusion scalings** (`damage_scale`, impact burst): decided, not built (see Not implemented). The cap on summed indirect bonuses is undecided.
- **`AOE_RADIUS`:** projectile and orbit hitboxes read it (Task G, `63afff2`, Headless). Area geometries read it for their reach too (Task H, Headless; see Done).
- **Balance workbook:** `effective_dps_hit_vs_dot.xlsx` (its name was dropped from `CLAUDE.md`).

Done:
- Core-stat invalidation, slot range, allocation-free modifier totals.
- `StatModifier.Type.MULTIPLICATIVE`; `Stat.Type.DOT_DAMAGE` / `STATUS_DURATION`.
- Infusion stat payloads: Fire STATUS_DURATION and STATUS_RAMP_CAP (Task F; it was a flat DOT_DAMAGE), Frost COOLDOWN, Wind PROJECTILE_MOVEMENT_SPEED, Earth AOE_RADIUS, Lightning CRIT_CHANCE. Arcane Bolt crit baseline (5% / 1.5x).
- Status tags `BURNING`, `CHILLED`, `FROZEN`; refcounted temporary tags. Status effect system (`StatusEffect`, `StatusEffectInstance`, `StatusEffectComponent`) routed by `Entity`. `HealthComponent.take_dot_damage`. `CombatPayload` carries `status_effects_to_apply` and the DoT and duration snapshots.
- Infusion-to-status hook: `UpgradeDefinition.status_effect_payload`, resolved through the ledger at cast time. (Confirm the exact method names against the code.)
- `AbilityData.structural_tags` replaces an ability's base tags in `swap_runtime_strategies` (`TagComponent.set_base_tags`).
- Evolution gating (`has_reached_soft_cap_milestone`, `is_offer_eligible`, `meets_recipe`, `evaluate_evolution_recipes`), `UpgradeDefinition.evolves_from` and `recipe_requirements`, `PayloadType.ABILITY_OVERCLOCK`, `UpgradeChoice.is_forced_offer`, forced offer drafts, and the generic Overclock card.
- Infusion cards are filtered to elements some ability can accept; an empty draft is skipped with a warning.
- Arcane Bolt `structural_tags` = `[METAMAGIC, PROJECTILE]` (Task E, Headless: its runtime base tags read back as both; provisional, tags will eventually decide which global upgrades apply). Its base stats: BASE_DAMAGE 1.0, COOLDOWN 1.0, CRIT_CHANCE 0.05, CRIT_MULTIPLIER 1.5, DURATION 3.0, AOE_RADIUS 10.0 (was 5.0 before Task G), QUERY_RADIUS 300, PROJECTILE_MOVEMENT_SPEED 500, PROJECTILE_AMOUNT 1, DOT_DAMAGE 0.15, STATUS_DURATION 0.0, STATUS_RAMP_CAP 0.0.
- The `[STAT FLAGGED DIRTY]` print in `StatsContainer` is removed. The headless scripts are in `tools/headless/` (Task E, committed and pushed in `814f2ce`).
- Projectile hitbox follows `AOE_RADIUS` (Task G, `63afff2`, Headless): `CombatVolume` reads the stat before setting the circle and falls back to `DEFAULT_COLLISION_RADIUS` 10.0 with a one-time warning when the stat is 0 or missing. Arcane Bolt's `AOE_RADIUS` base is 10.0, and Earth levels 1 to 3 give 11, 12 and 13. The sprite is not scaled. Any ability using Straight or MouseAim projectiles or the orbiting ring needs key 9 in its profile.
- Area geometries read `AOE_RADIUS` for their reach (Task H, `43fe19e`, Headless: import scan, world run, load check 163 / 0, logic test 81 PASS). `GeometryDriver._get_area_radius(stats, fallback)` returns the stat, or the fallback with a one-time warning when it is missing or 0. `AreaGeometry` and `RadialPulseGeometry` override `get_query_shape` with an `AOE_RADIUS` circle (fallback `QUERY_RADIUS`, or 200 with no stats), and converging vortex inherits it. Linear sweep uses it as the wedge length (fallback `strike_length` 120). Fissure uses it as the first strike radius (fallback `starting_radius` 30) and keeps `distance_step` 70 and `expansion_rate_per_step` 15. Chain link and the projectile geometries still return `QUERY_RADIUS` circles. With Earth level 1 a 200-radius pulse is 220. The logic test checks fissure reach with real physics queries against placed bats, so `run` in `logic_test.gd` is now a coroutine and `runner.gd` awaits it from `_run_test`. The old exports remain as fallbacks. No area ability is authored yet; any future area profile needs key 9.
- Shared impact-burst mechanism (Task I, uncommitted, Headless: import scan, world run, load check 167 / 0, logic test 108 PASS). No card carries a burst yet, so nothing happens in play. New in `components/ability/bursts/`: `BurstShape` (abstract, finds targets only), `CircleBurstShape` (radius `AOE_RADIUS * radius_multiplier`, one warning per run when the stat is missing or 0, skips non-hurtboxes, player hurtboxes and the excluded primary), `ImpactBurstDefinition` (`burst_id`, `trigger` `ON_HIT` / `ON_CRIT`, `shape`, `damage_fraction`, `per_enemy_bonus`, `per_enemy_bonus_cap`, optional `effect_scene`) and `ImpactBurst.run` (all rules: duplicates the payload, scales `final_damage` by `damage_fraction * (1 + min(per_enemy_bonus * caught, cap))`, turns crit off, replaces statuses and bursts with empty arrays, sets `is_burst`, then hits each target through its hurtbox). `CombatPayload` gained `impact_bursts`, `is_burst` and `is_critical_hit` (the crit roll was not recorded on the payload before; `generate_hit_payload` now sets it). `UpgradeDefinition.impact_burst_payload`, `RunLedgerComponent.get_impact_bursts` and `StatsContainer.get_impact_bursts` mirror the status resolver. `HurtboxComponent.take_hit` emits `hit_received` as before, then, only if the payload has bursts and `is_burst` is false, captures the hurtbox position, instance id and `World2D` and runs each qualifying burst deferred. The `effect_scene` is added to the current scene (or the root) at the burst origin, only when the burst hit at least one target. Level gating (open item 33) is not built.
- Task F (`63afff2`, Headless: import scan, world run, load check 163 / 0, logic test 54 PASS): `Stat.Type.STATUS_RAMP_CAP` = 19; `UpgradeDefinition.additional_stat_modifiers` (the ledger's `get_modifier_totals` loops the primary payload and then the extras through `_modifier_contribution`, and `StatsContainer` invalidation flags every stat any of a card's modifiers targets); `CombatPayload.status_ramp_cap_snapshot`; `StatusEffectInstance.ramp_cap_bonus`; `apply_effect(effect, dot_damage, duration_bonus, ramp_cap_bonus := 0.0)` (`Entity` passes the fourth argument); `burn.tres` `base_duration` 0.0; `inf_fire_upgrade_def.tres` carries the two flat modifiers; Arcane Bolt profile `DOT_DAMAGE` 0.15 and `STATUS_RAMP_CAP` 0.0 (key 19); `debug_status_trigger.gd` default `debug_duration_bonus` 3.0, because B would otherwise apply nothing.
- Level-up drafts (`generate_selection_pool`) skip every infusion definition unconditionally, and the `HealthComponent.take_damage` print is removed (Task D, `c1cbdff`, Headless: 163 loads, world 600 frames, logic checks, identical before and after).
- `RunState.pending_draft_levels`, written through by `UpgradeManager`.

Not implemented:
- Lightning `CRIT_MULTIPLIER` is not authored. A card can now carry it through `additional_stat_modifiers` (Task F).
- Pierce does not exist: `CombatVolume._on_collision_detected` frees the volume on every hit. `OrbitingShard` shares it, so orbit shards vanish after one hit (looks unintended).
- Impact bursts are built as a mechanism only (Task I). Earth's explosion and Lightning's overload are not authored (no card carries a burst), level gating of burst cards (open item 33) is not built, and nothing is visible in play. `ProjectileSpawnerComponent.projectile_impacted` is still unused: the burst fires from `HurtboxComponent.take_hit`, not from that signal.
- Cast-time `damage_scale` for Frost and Wind (and its cap), level-gated infusion effects, and Wind's generic speed stat are designed (Decided) but not built.
- First evolution (decided, first form only): Arcane Bolt -> Plasma, using `ChainLinkGeometry` (an area form, so its evolved `structural_tags` drop `PROJECTILE`). Not authored yet.
- Any authored evolution, evolution card or compound (tags, shared effects). Until one exists, an ability reaching its soft cap is forced into Overclock.
- A trigger for infusion drafts in a normal run.
- Room transitions.
- Every future ability or evolution stats profile needs `DOT_DAMAGE`, `STATUS_DURATION` and `STATUS_RAMP_CAP` entries (a missing stat reads 0.0 and ignores modifiers, and `mutate_base_profile` replaces the whole profile). Today `arcane_bolt_stats.tres` is the only ability profile and it has them; the entity profiles (`player_stats`, `bat_stats`, `enemy_stats_profile`) are not ability profiles and do not need them.
- Reactions (hook marked by a comment in `Entity._on_hit_received`). `FROZEN` has no source.
- STACK policy is untuned and unused. Proc chance for statuses.

Known open bugs: nothing emits `room_completion_confirmed`; `boss_node` is never generated; `EventBus.campaign_victory_triggered` is undeclared; `InfusionAllocationUI` uses wrong member names (`run_ledger`, `ui_inventory_changed`; latent, it is only reached when the player already exists); enemies never drop XP; enemies spawn at fixed coordinates; nothing counts remaining enemies, so a room has no clear condition (`EnemySpawnerComponent` emits `wave_completed` and `campaign_cleared`, but nothing listens); nothing handles `Entity.died`, so there is no death or game-over flow.
