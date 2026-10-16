# Project: Action Roguelite (Godot 4, GDScript)

Auto-attack action roguelite (Vampire Survivors-style combat) with a Slay the Spire-style room map.
Engine: Godot 4.x. The code uses `@abstract` and typed Dictionaries, so assume 4.5 or newer.
Elemental infusions (Fire, Frost, Lightning, Wind, Earth) are socketed into ability slots and drive evolutions.

## Code style
- Tabs for indentation. Static typing everywhere (`var x: int`, typed arrays and dictionaries).
- One `class_name` per script. `##` doc comments on public methods.
- Data lives in Resources (`.tres`), not hard-coded constants. Tunable numbers are `@export`.
- Tags are an enum (`Tags.Type`), never strings.
- No new `print()` calls in hot paths (damage, stat recalculation, invalidation).

## Architecture rules (do not break these)
- **Component isolation.** Child components never hold references to sibling nodes. The parent wires them with signals and method parameters. Entity, Player and Ability are the mediators.
- **EventBus** (autoload) is the global signal hub. `EventBus.active_player_instance_id` is how systems find the player; call `instance_from_id()` on it.
- **Slots.** Slot 0 is the Character Core (player stats). Abilities occupy slots 1-4 (`AbilityContainer.MIN_SLOT` / `MAX_SLOT`).
- **Ability pipeline.** `AbilityData` selects: deployment anchor, geometry driver, optional payload driver, stats profile. The ability runs anchor -> spatial query -> geometry driver. Evolutions swap those strategy nodes via `execute_ability_evolution`.
- **Stats.** `StatsContainer` caches lazily with dirty flags. Call `get_final_stat_value(stat_type)` with ONE argument. Tags come from the container's own `TagComponent`, never from the caller.
- **Tags.** `TagComponent` compiles three layers: `base_tags` (replaced from `AbilityData.structural_tags` in `Ability.swap_runtime_strategies`; an empty list logs a warning and leaves the tags unchanged), infusion tags (rebuilt from the run ledger, never stored on the component), and refcounted temporary tags from status effects.
- **Run ledger.** `RunLedgerComponent` (on the Player) is the single source of truth for upgrades. Aggregate with `get_modifier_totals(slot, tags, stat)`, which returns `Vector3(flat, percent, multiplicative)`. Do not create temporary modifier resources in hot paths. Slot-specific purchases (infusions, Overclock) are stored under the key `"<upgrade_id>::slot_<n>"` and win over the plain key.
- **Shared payloads.** A `CombatPayload` is shared by every projectile in a volley. Duplicate it before any per-hit mutation. Status effect resources are templates: never mutate them, keep runtime state in a separate per-application object (`StatusEffectInstance`). Per-hit state (for example a pierce count) lives on the projectile, never on the payload.
- **Driver library.** Geometry drivers: projectile (Targeted = nearest enemy, Straight = player movement direction, MouseAim; all use the fan helper with `PROJECTILE_AMOUNT` and 15 degree spread), area (RadialPulse, LinearSweep, Fissure, ConvergingVortex, ChainLink), persistent (OrbitingRing). Trajectories (`MovementStrategy`): Vector (default), Homing, Boomerang, SineWave, Tornado. The only payload driver is `MissileHitPayload`, which just sets the trajectory scene. Every geometry ends in `HurtboxComponent.take_hit(payload)`, so statuses apply from any shape. An evolution may change family (projectile -> area).
- **Driver stats.** Each driver reads specific stats from the ability's profile, and a missing stat reads 0.0: no `PROJECTILE_AMOUNT` means no shots, no `DURATION` kills a projectile instantly, no `CHAIN_RADIUS` means no chain. `mutate_base_profile` replaces the whole profile, so every evolution's stats profile must carry every stat its drivers read, plus `BASE_DAMAGE`, `COOLDOWN`, `CRIT_*`, `DOT_DAMAGE`, `STATUS_DURATION` and `STATUS_RAMP_CAP`, plus `AOE_RADIUS` for projectile and orbit abilities (it is their hitbox radius; Task G). A modifier on a stat that is missing from the profile has no effect (the stat reads 0.0), which is why Arcane Bolt's profile needed `STATUS_RAMP_CAP: 0.0` before Fire's cap bonus reached Burn.
- **Crit.** Rolled once per cast in `generate_hit_payload` (decided, simplest). A fan or chain crits entirely or not at all.

## Append-only enums
`Stat.Type`, `Tags.Type`, `UpgradeDefinition.PayloadType`, and any other enum referenced from `.tres` files are stored as integers. Add new entries at the END only. Never insert, reorder, or delete entries.

## Run persistence
Room scenes are freed on every transition, so run state lives in `RunSession.state` (a `RunState` resource).
- `Player._exit_tree` captures it (skipped if the player is dead). `Player._ready` restores it before `player_spawned` is emitted. `MapGenerator` resets it when a new run starts.
- Any NEW state that must survive rooms needs three edits: a field in `RunState`, capture in `Player.capture_run_state`, restore in `Player._restore_run_state`.
- Exception: `UpgradeManager` lives under the Systems node of the World scene (freed with it). It writes `RunState.pending_draft_levels` through to `RunSession.state` on every queue change and reloads it in `_ready`.
- Not persisted on purpose: status effects, temporary modifiers, cooldown timers, uncollected pickups, offer drafts (eligibility is derived from persisted state).

## Upgrade drafts, evolution and Overclock
- **Level-up drafts** never contain infusion cards, evolution cards or Overclock cards.
- **Infusion drafts** are separate from level-up drafts (`UpgradeManager.trigger_infusion_draft_event`). Only elements that at least one ability can accept are offered. When infusion drafts happen in a normal run is undecided; today it is a debug key only.
- **Offer drafts.** When an ability reaches its soft cap (`EvolutionGateComponent.is_offer_eligible`), `UpgradeManager` presents a forced draft for it: every evolution card that matches, then Overclock. No decline, no reroll, no random fill. Checked after each confirmed infusion and at room start, before queued level-ups. Never stored.
- **Evolution cards** are `ABILITY_UNLOCK` definitions with `evolves_from` (the ability's current `AbilityData`, compared by `resource_path`) and `recipe_requirements` (elements that must be at the soft cap).
- **Overclock** is a generic `ABILITY_OVERCLOCK` card, logged per slot with `log_slot_specific_purchase`, which sets `is_permanently_overclocked`. It lifts only the per-element cap (3 or 5 -> 15). The element-count limit still applies.
- Compounds (Fire + Lightning = Plasma) are tags granted by an evolution through `structural_tags`, not an infusion level. They are not designed yet.

## Combat design decisions
- Two separate damage channels. **Hit** uses `BASE_DAMAGE`, crit chance and crit multiplier. **DoT** uses its own `DOT_DAMAGE` and `STATUS_DURATION`. DoT never reads `BASE_DAMAGE`, and DoT ticks never crit.
- Fire is the DoT element (duration theme). Lightning is the hit element (crit theme).
- **Two stats on every ability (Decided Oct 15; built for Arcane Bolt only).** Every ability profile carries a nonzero `BASE_DAMAGE` and a nonzero `DOT_DAMAGE`. `DOT_DAMAGE` is inert potency: nothing ticks until a status with a duration is applied. There is no cast-time duration gate: `StatusEffectComponent.apply_effect` returns early when the effective duration (template `base_duration` plus the `STATUS_DURATION` bonus) is 0 or less, so there is no instance, no tag, no ticks and no warning (Task F, Headless).
- **Fire deals no damage itself (Implemented, Headless, Task F).** Per level it adds flat `STATUS_DURATION` (+3.0 s) and flat `STATUS_RAMP_CAP` (+0.1; `Stat.Type` 19). Flat modifiers scale as `value * tier` (level 3 is 9.0 s and +0.3). The cap bonus flows through `status_ramp_cap_snapshot` to `StatusEffectInstance.ramp_cap_bonus`, the same path as `duration_bonus`, and a refresh takes the latest applier's value. Burn's template `base_duration` is 0, so duration comes only from Fire. A card carries several modifiers through `UpgradeDefinition.additional_stat_modifiers`. All numbers are placeholders. Arcane Bolt's base `DOT_DAMAGE` is 0.15.
- **Decided, not built: indirect infusion scalings.** They unlock by infusion level and boost both channels through a cast-time `damage_scale` applied to final hit damage and `dot_damage_snapshot` (indirect bonuses summed, then capped). Frost: bonus per 0.1 s shaved off the default cooldown (level 2). Wind: speed ratio, with one generic speed stat read by every driver (level 2). Lightning (overload on crit, level 3) and Earth (on-impact explosion scaling with enemies caught, level 3) share one impact-burst component; a burst never crits and never triggers another burst. Burst effects scale off hit damage.
- Infusions contribute through stat modifiers (`stat_modifier_payload`) and, optionally, a status carried by the card (`status_effect_payload`). Effect templates define shape only (tick interval, ramp, stacking), never absolute damage.
- Card scaling is multiplicative, per card: the ledger multiplies `pow(1.0 + value, tier)` for each card, where tier is the card's duplicate count. Final stat = `(base + flat) * (1 + percent) * multiplicative`. This was the one rule that made both specializations viable in `effective_dps_hit_vs_dot.xlsx`.
- Burn uses a REFRESH stacking policy. STACK exists but is untuned and unused: it multiplies DoT output several times over.
- Status effect templates are never mutated. Runtime state lives in `StatusEffectInstance`. Statuses are not persisted between rooms. Burn ramp is +10%/s capped at +50%, matching the workbook (the designer edited `burn.tres` to 0.10 / 0.5 by hand on 2026-10-15; until then the shipped file was 0.25 / 1.0; the logic test passes with the new values, Task E, Headless). Burn's template `base_duration` is 0 (duration comes from Fire). All other Burn and Chill numbers are placeholders.
- All numbers in the balance workbook are placeholders.
- **Status application rules.** Any `UpgradeDefinition` can carry a `status_effect_payload`, resolved through the ledger with the normal scope rules and deduplicated by `effect_id`. Statuses are chosen at cast time and applied on every hit (no chance stat). A ticking status is skipped when the ability's `DOT_DAMAGE` snapshot is 0. `STATUS_DURATION` is ability-wide. A status whose effective duration is 0 or less is not applied at all (`apply_effect`). No status variants.

## Status (as of 2026-10-16, verify against the code)
Three levels of evidence are used below:
- **Verified**: the user ran it in Godot.
- **Headless**: Claude Code ran it with the Godot executable and reported it (163 scripts, scenes and resources load; the world scene runs 600 frames without errors; 63 logic checks passed in Task G (54 after Task F). The 38 in earlier reports was a miscount; Task E counted 36).
- **Written**: not run.

Task letters used below map to commits: Task D = `c1cbdff`, Task E = `814f2ce`, Tasks F and G = `63afff2` (one commit), Task H = pending (not yet given).

Verified:
- Burn and Chill, triggered with B / C, apply and are removed on expiry. Burn tick damage and ramp (checked before the ramp retune).
- Run persistence through the F3 player respawn only. Room transitions are not implemented, so a real room change is untested.

Headless:
- Burn ticks, ramp (0.10 / 0.5, read from `burn.tres`), refresh, expiry and death cleanup (the logic test was re-run after the hand edit, Task E). Chill slow and tag removal. Refcounted tags.
- Fire levels 1 to 3 (Task F): duration 3.0 / 6.0 / 9.0 s, ramp cap 0.6 / 0.7 / 0.8, multiplier 1.3 at 3.0 s at level 1 and 1.8 at 8.0 s at level 3. A cast without Fire carries no status. A duration-0 application does nothing. A refresh takes the latest ramp cap bonus.
- Fire and Frost statuses carried on payloads.
- The Overclock offer appears as the only forced card and does not repeat. Overclock cap changes.
- The pending-level write-through.

Written (needs a hand check): B and C key presses (B now uses a 3.0 s `debug_duration_bonus`), the draft screens (including the reworked Fire card) (offer, level-up, infusion), a bolt hit applying a status to an enemy, and a room transition with queued drafts.

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
- Task F (`63afff2`, Headless: import scan, world run, load check 163 / 0, logic test 54 PASS): `Stat.Type.STATUS_RAMP_CAP` = 19; `UpgradeDefinition.additional_stat_modifiers` (the ledger's `get_modifier_totals` loops the primary payload and then the extras through `_modifier_contribution`, and `StatsContainer` invalidation flags every stat any of a card's modifiers targets); `CombatPayload.status_ramp_cap_snapshot`; `StatusEffectInstance.ramp_cap_bonus`; `apply_effect(effect, dot_damage, duration_bonus, ramp_cap_bonus := 0.0)` (`Entity` passes the fourth argument); `burn.tres` `base_duration` 0.0; `inf_fire_upgrade_def.tres` carries the two flat modifiers; Arcane Bolt profile `DOT_DAMAGE` 0.15 and `STATUS_RAMP_CAP` 0.0 (key 19); `debug_status_trigger.gd` default `debug_duration_bonus` 3.0, because B would otherwise apply nothing.
- Level-up drafts (`generate_selection_pool`) skip every infusion definition unconditionally, and the `HealthComponent.take_damage` print is removed (Task D, `c1cbdff`, Headless: 163 loads, world 600 frames, logic checks, identical before and after).
- `RunState.pending_draft_levels`, written through by `UpgradeManager`.

Not implemented:
- Lightning `CRIT_MULTIPLIER` is not authored. A card can now carry it through `additional_stat_modifiers` (Task F).
- Pierce does not exist: `CombatVolume._on_collision_detected` frees the volume on every hit. `OrbitingShard` shares it, so orbit shards vanish after one hit (looks unintended).
- Most area geometries do not read `AOE_RADIUS` for their reach yet: radial pulse uses the `QUERY_RADIUS` query circle (inherited from `GeometryDriver.get_query_shape`), linear sweep uses `strike_length`, and fissure uses its exports. Converging vortex is the exception: its query circle is also `QUERY_RADIUS`, but it already reads `AOE_RADIUS` for its maximum reach. Decided: the others read `AOE_RADIUS` too (Task H, pending: the task has not been given yet). Chain link and the projectile geometries keep `QUERY_RADIUS` / `CHAIN_RADIUS`.
- No on-impact burst: `ProjectileSpawnerComponent.projectile_impacted` exists but nothing uses it. It is needed for Earth's explosion and Lightning's overload (one shared component, Decided).
- Cast-time `damage_scale` for Frost and Wind (and its cap), level-gated infusion effects, and Wind's generic speed stat are designed (Decided) but not built.
- First evolution (decided, first form only): Arcane Bolt -> Plasma, using `ChainLinkGeometry` (an area form, so its evolved `structural_tags` drop `PROJECTILE`). Not authored yet.
- Any authored evolution, evolution card or compound (tags, shared effects). Until one exists, an ability reaching its soft cap is forced into Overclock.
- A trigger for infusion drafts in a normal run.
- Room transitions.
- Every future ability or evolution stats profile needs `DOT_DAMAGE`, `STATUS_DURATION` and `STATUS_RAMP_CAP` entries (a missing stat reads 0.0 and ignores modifiers, and `mutate_base_profile` replaces the whole profile). Today `arcane_bolt_stats.tres` is the only ability profile and it has them; the entity profiles (`player_stats`, `bat_stats`, `enemy_stats_profile`) are not ability profiles and do not need them.
- Reactions (hook marked by a comment in `Entity._on_hit_received`). `FROZEN` has no source.
- STACK policy is untuned and unused. Proc chance for statuses.

Known open bugs: nothing emits `room_completion_confirmed`; `boss_node` is never generated; `EventBus.campaign_victory_triggered` is undeclared; `InfusionAllocationUI` uses wrong member names (`run_ledger`, `ui_inventory_changed`; latent, it is only reached when the player already exists); enemies never drop XP; enemies spawn at fixed coordinates; nothing counts remaining enemies, so a room has no clear condition (`EnemySpawnerComponent` emits `wave_completed` and `campaign_cleared`, but nothing listens); nothing handles `Entity.died`, so there is no death or game-over flow.

## Setup after cloning
The repo is public, so some folders are deliberately not in it (both are in `.gitignore`):
- `assets/` holds art, including a commercial pack (files named `oryx_16bit_fantasy_*`) that must not be redistributed. Do not commit or push it. Without it, scenes and resources that reference these textures show missing-texture errors and the game has no sprites. Put the files back at the same paths (`assets/entities/bullet.png`, `assets/entities/oryx_16bit_fantasy_creatures_55.png`, `assets/entities/oryx_16bit_fantasy_creatures_219.png`, `assets/world/oryx_16bit_fantasy_world_trans.png`), then open the project once in Godot so it regenerates the `.import` files.
- `addons/` holds GUT (the test framework). Install it from the Godot Asset Library or its GitHub release if you need to run tests.
- Script `.uid` files and `test/` are tracked. Commit new `.uid` files with their scripts.

## Working in this repo
- Before changing a method signature, grep all `.gd` AND `.tscn` files for callers.
- Be careful with `.tscn` / `.tres` edits: they hold resource IDs and enum integers. Keep diffs small and review them.
- Prefer editing existing files over creating new ones. Do not add features that were not asked for.
- Do not claim something works unless it was actually run, and say which kind of run it was (Verified or Headless).
- Headless checks (Godot 4.5; `$GODOT` is `C:\Users\chris\Desktop\Godot_v4.5-stable_win64.exe`; run from the project root):
  - Import / project scan: `$GODOT --headless --path . --import`
  - World run (600 frames, read the errors; about 4 s): `$GODOT --headless --path . res://scenes/world/world.tscn --quit-after 600`
  - Load check (163 scripts and resources; about 1 s): `$GODOT --headless --path . -s res://tools/headless/load_all.gd`. It skips `res://tools/`, because it crashed Godot by reloading itself.
  - Logic test (63 checks as of Task G; about 1 s): `$GODOT --headless --path . -s res://tools/headless/runner.gd`. It runs `res://tools/headless/logic_test.gd` unless the `LOGIC_TEST` environment variable names another script. It prints `ERROR: N resources still in use at exit` (N was 5 as of Task G; it grows when a check creates objects it does not free) because the harness quits early; that is expected.
  - The three scripts live in `tools/headless/`. Put new checks in `logic_test.gd`. Most working-tree files use CRLF line endings, but at least `combat_volume.gd` uses LF, so check each file before matching text.
  - Custom check scripts run with `-s <script>`. Autoloads (`EventBus`) do not exist when an `-s` script compiles: load project code from `_process` after the first frame, and reach autoloads with `root.get_node("EventBus")`.
  - Headless runs cannot show visuals or take key presses (B / C, drafts on screen): those still need a manual playthrough.
- When a task changes anything listed under Status, update the Status section in the same change and show its diff in your report. Only list something as Verified if the user said they ran it. List something as Headless only if you ran it and can name the command.
