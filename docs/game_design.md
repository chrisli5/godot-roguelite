# Game Design Document v1.9: Modular Action Roguelite

Oct 14, 2026 · @Christopher

## Revision summary

This revision aligns the design with the code as of 2026-10-14. Since v1.8, the infusion-to-status hook, the Burn ramp retune, base tags from `AbilityData`, evolution gating, the Overclock card, forced offer drafts and queue persistence are in the code. Infusions are now drafted separately from level-up drafts (decided). Compounds are redefined as shared effects, with evolutions unique per ability (§4).

Every section carries one status tag:

- **Implemented**: in the code and used by the game.
- **Decided**: settled in design and specified for implementation, but not yet in the code.
- **Proof of concept**: a direction to test, with placeholder numbers.
- **Deferred**: kept from the earlier document and not scheduled.

Where this document and the code disagree, the code is the baseline until a section says otherwise.

Verification uses three levels. **Verified**: run by the designer in Godot. **Headless**: run by Claude Code with the Godot executable (163 scripts, scenes and resources load; the world scene runs 600 frames without errors; 38 of 38 logic checks passed). **Written**: not run. Details are in §6 to §8. Visuals, key presses, the draft screens and real room changes are still untested by hand, and room transitions are not implemented.

## Glossary

- **Ability tier**: TIER_1_BASE, TIER_2_EVOLVED, TIER_3_APEX (§7).
- **Infusion tier / level**: how many times an element has been socketed into an ability (§7).
- **Card tier**: in the multiplicative formula (§5), the number of times a card has been drafted (its duplicate count). This is a third meaning, unrelated to the two above.
- **Compound**: a fixed pair of elements that forms the same named effect on every ability (§4).
- **Offer draft**: a forced draft for one eligible ability, holding its evolution cards plus Overclock (§7).

## 1. System architecture

**Status:** Implemented.

&#91;embedded content: system architecture · player, ability container, run state\]

Child components never hold references to sibling nodes. The Player and each Ability are the mediators that wire components together with signals and method parameters. The Player's run ledger is the single source of truth for upgrades. The EventBus is the global signal hub, and systems find the player through `EventBus.active_player_instance_id`. Because room scenes are freed on every transition, run state is held outside the room by `RunSession`. `UpgradeManager` sits under the Systems node of the World scene and is freed with it, so it writes the state it needs straight through to `RunSession.state`.

## 2. Action bar: four ability slots and the Character Core

**Status: Implemented for slots 0 to 4; Deferred for manual casting.** The code mounts abilities in slots 1 to 4 and reserves slot 0 for the Character Core, so the player's own stats and upgrades use the same slot lookup as abilities.

| Slot | Holds | Status |
| --- | --- | --- |
| 0 | Character Core: the player's stats and core upgrades (Max Health, Move Speed). Never holds an ability. | Implemented |
| 1 to 4 | One ability each, mounted from its `AbilityData`; fires automatically when its cooldown ends. | Implemented |
| Manual cast, dash with i-frames, passive module | Needs input-triggered casting and movement support that do not exist yet. | Deferred |

The earlier five-slot layout (Engine, Catalyst, Finisher, Dash, Passive) stays as design intent for ability roles, but roles are not tied to slot numbers. Moving to five slots would mean raising `MAX_SLOT` in the ability container and updating the upgrade pool loops that assume four.

## 3. Tag taxonomy

**Status:** Implemented for ability tags and status tags. Deferred for trigger tags.

Tags describe what an ability or effect is, and they decide which upgrades apply to it. They are the enum `Tags.Type`, never strings.

- **Append-only.** Tags are stored as integers in `.tres` files. New entries go at the end of the enum. Entries are never inserted, reordered or deleted. The same rule applies to `UpgradeDefinition.PayloadType` and every other enum referenced from `.tres` files.
- **Source of truth.** Each stats container reads tags from its own `TagComponent`. Callers do not pass tags in.
- **Layers.** A `TagComponent` compiles three layers: base tags, infusion tags and temporary tags.
- **Base tags (Implemented, Written).** Base tags come from `AbilityData.structural_tags`, and they replace the ability's previous base tags whenever it is mounted or evolves. An empty list logs a warning and leaves the tags unchanged. Arcane Bolt may still have none (open item 22).
- **Infusion tags.** Rebuilt from the run ledger on every recompile, so evolving never removes them.
- **Status tags (Implemented).** `BURNING`, `CHILLED` and `FROZEN` are appended to the enum. `TagComponent` grants them as temporary tags with reference counts, so a tag only clears when the last status that granted it ends. `FROZEN` has no source yet.
- **Compound tags (Proof of concept).** A compound is a tag granted by an evolution through its `structural_tags`. None exists yet.
- **Trigger tags (Deferred).** On Hit, On Dash, On Crit, On Crowd Control and On Health Loss do not exist yet. They need to be added before any card that depends on them.

## 4. Elemental infusions, compounds and evolutions

**Status:** Implemented for the stat contributions and for applying statuses, except Fire `STATUS_DURATION` (Decided, not built). Decided for how infusions are drafted. Proof of concept for the indirect scalings and compounds. Deferred for compound effects.

Infusions are socketed into ability slots. They contribute through stat modifiers (`stat_modifier_payload`), plus an optional status carried by the card (`status_effect_payload`, §6). Effect templates define shape, never absolute damage. The ledger stores slot-specific purchases under `<upgrade_id>::slot_<n>`, and that key wins over the plain key.

**Drafting (Decided).** Infusions are drafted through their own draft, separate from level-up drafts. Only elements that at least one ability can accept are offered. In the code today, this draft is a debug key only, and level-up drafts never show infusion cards. When infusion drafts happen in a normal run is not decided (open item 23).

| Element | Role | Direct stat contribution | Status applied | Indirect scaling (Proof of concept) |
| --- | --- | --- | --- | --- |
| Fire | Damage over time | DOT\_DAMAGE (Implemented). STATUS\_DURATION (Decided, not built: needs a second payload field) | Burn (Implemented, headless) | Not yet defined |
| Frost | Control | COOLDOWN (Implemented) | Chill (Implemented, headless) | Not yet defined |
| Lightning | Hit and crit | CRIT\_CHANCE, through its one payload (Implemented). CRIT\_MULTIPLIER is not built | None | Not yet defined |
| Wind | Mobility | PROJECTILE\_MOVEMENT\_SPEED (Implemented) | None | Not yet defined |
| Earth | Area | AOE\_RADIUS (Implemented) | None | Not yet defined |

Each infusion definition holds one `stat_modifier_payload`. A second payload field on `UpgradeDefinition` is needed for Fire `STATUS_DURATION` and Lightning `CRIT_MULTIPLIER`. See the open items.

### Compounds and evolutions

**Status:** Proof of concept. Nothing in this subsection is built beyond the gating in §7.

- A **compound** is a fixed pair of elements. It always forms the same named effect, and that effect works the same way on every ability.
- An **evolution** is unique per ability. It changes the ability's geometry and is themed by a compound.
- **The evolution grants the compound.** The evolved `AbilityData` lists the compound tag in `structural_tags`, and a card scoped to that tag supplies the shared effect.
- Compounds are given to element pairs one at a time. A pair with no compound only offers Overclock.

| Compound | Recipe | Placeholder shared effect | Depends on |
| --- | --- | --- | --- |
| Plasma | Fire + Lightning | Plasma Bleed (burst reaction) | Burn, and the pre-damage reaction hook |
| Magma | Fire + Earth | Lava Tiles (area hazard) | Burn, and an Earth area effect |
| Name to decide | Frost + Earth | Deep Frozen (shatter reaction) | Chill and Frozen |

The effects above are working names from v1.8 (Plasma Scorch, Magma Volcano and Brittle Fracture were the old evolution names). None has a defined mechanic, and all are **Deferred**.

## 5. Damage channels

**Status:** Implemented for the multiplicative modifier type and the `DOT_DAMAGE` and `STATUS_DURATION` stats. Balance numbers are placeholders.

There are two separate channels. A build specializes in one of them, and hit damage is not the best scaling option for both.

|  | Hit channel | DoT channel |
| --- | --- | --- |
| Element | Lightning | Fire |
| Damage stat | BASE\_DAMAGE | DOT\_DAMAGE (per second) |
| Other stats | Crit chance, crit multiplier | STATUS\_DURATION |
| Crits | Yes | No, ticks never crit |
| Reads BASE\_DAMAGE | Yes | Never |

The DoT magnitude is snapshotted at cast time from the source ability into the payload (`dot_damage_snapshot`). When a status is applied, the snapshot is copied into that status instance. `status_duration_snapshot` works the same way.

### Stacking of modifiers

Card scaling is multiplicative, per card. The ledger multiplies one term per upgrade into a single product, and the stat container applies it:

```latex
\text{final} = (\text{base} + \text{flat}) \times (1 + \text{percent}) \times \text{multiplicative}
```

```latex
\text{multiplicative} = \prod_{\text{cards}} (1 + \text{value})^{\text{tier}}
```

Here `value` is the card's value and `tier` is the card's duplicate count (see the glossary): drafting a duplicate card raises its tier. In code, `get_modifier_totals` returns `Vector3(flat, percent, multiplicative)`.

In the balance workbook, additive pools made hit cards the best choice for DoT builds too. Multiplicative pools passed all 6 specialization tests. All numbers are placeholders. The model still fails the specialization test at 4 and 8 drafts, and the DoT to hit ratio drifts from 1.02 to 0.80 between 4 and 20 drafts at a fixed Fire value.

Compound effects should be conditional or capped. A pair bonus or an evolution multiplier stacked on the multiplicative rule would put evolved builds ahead of every other build.

### Optional later layers

- **Mono-channel bonus (Deferred).** A bonus for committing to one channel.
- **Fire hit tax (Deferred).** A penalty on hit scaling for Fire builds.
- **Stacking policy.** Burn uses REFRESH. STACK exists in the status component but is untuned and unused: it multiplies DoT output two to four times at the placeholder values and needs re-tuning first.

## 6. Status effects

**Status:** Implemented. Application and removal of Burn and Chill, and Burn tick damage and ramp, were Verified through the debug trigger (before the ramp retune). The rest is Headless. Applying statuses from ability hits is **Implemented, Headless**; a bolt hitting an enemy has not been checked by hand.

### Design

- **Template resource.** `StatusEffect` holds id, base duration, stacking policy, max stacks, tick interval, two ramp floats (`ramp_bonus_per_second`, `ramp_max_bonus`, used instead of a Curve resource), stat modifiers and granted tags. Templates define shape only and are never mutated.
- **Runtime state.** Each application gets its own `StatusEffectInstance` (per-application copies of the modifiers with unique ids), so shared payloads are never changed per hit.
- **Routing.** `StatusEffectComponent` emits `applied`, `refreshed`, `ticked` and `expired`. The Entity routes them to stats, health and tags. The component knows nothing about its siblings.
- **Tick damage.** `dot_damage * (1 + min(elapsed * ramp_bonus_per_second, ramp_max_bonus)) * tick_interval * stacks`. Ticks bypass the hurtbox through `take_dot_damage`. They never crit and never read BASE\_DAMAGE.
- **Refresh.** REFRESH resets the timer and takes the newer snapshot, but keeps `elapsed`, so a sustained Burn keeps ramping. The ramp resets only after the effect expires.
- **Dead targets.** A status is not applied to an entity that is already dead, and all effects are cleared when health is depleted.
- **Persistence.** Status effects are not carried between rooms.
- **Reactions.** A hook before damage in `Entity._on_hit_received` is reserved for reactions (marked by a comment). The reactions themselves are deferred.

### Application rules (Implemented, Headless)

- **Carried by cards.** Any `UpgradeDefinition` can carry a `status_effect_payload`, independent of its `payload_type`. An infusion can carry its stat modifier and its status on one card.
- **Resolved through the ledger** with the normal scope rules (a status card needs `LOCAL_SLOT` or `GLOBAL_TAG_MATCH` scope to reach abilities; infusions work through slot-specific purchases). Duplicate copies of a card add nothing, and templates are deduplicated by `effect_id`, first in purchase order wins.
- **Chosen at cast time.** The payload's `status_effects_to_apply` is filled once per cast, then applied on every hit. Application is guaranteed: there is no chance stat.
- **No DOT\_DAMAGE, no ticking status.** A status that ticks (`tick_interval > 0`) is skipped when the ability's `dot_damage_snapshot` is 0, with a one-time warning per `effect_id`. A status that does not tick (Chill) always applies.
- **STATUS\_DURATION is ability-wide.** The single snapshot lengthens every status the ability applies.
- **No status variants.** Templates stay fixed. Scaling of Chill's slow and Burn's ramp is undefined.

### Effects

| Effect | Source | Behavior | Status |
| --- | --- | --- | --- |
| Burn | Fire | DoT with REFRESH stacking, sets BURNING. Base 3 s, tick 0.5 s, ramp +10% per second capped at +50% | Implemented. Verified (apply, expiry, ticks, ramp at the old numbers). Headless (retuned ramp) |
| Chill | Frost | Slows the target by 30% movement speed, sets CHILLED. Base 3 s, no tick | Implemented, Verified (apply, expiry). Headless (slow, tag removal) |
| Plasma Bleed | Plasma (compound) | Burst reaction | Deferred |
| Deep Frozen | Frost + Earth compound | Shatter reaction | Deferred |
| Lava Tiles | Magma (compound) | Area hazard | Deferred |

Burn ramp: retuned to the balance workbook (+10% per second, capped at +50%). All other Burn and Chill numbers are placeholders.

## 7. Evolution gating, progression and overclock

**Status:** Implemented. Headless-checked (the Overclock offer, the cap changes); the draft screens are untested by hand. No evolution is authored yet.

| Rule | Detail | Status |
| --- | --- | --- |
| Infusion level caps | Soft cap 3 in tier 1, soft cap 5 in tier 2, hard cap 15 | Implemented |
| Unique elements | At most 2 in tier 1, at most 3 in tier 2 | Implemented |
| Ability tiers | TIER\_1\_BASE, TIER\_2\_EVOLVED, TIER\_3\_APEX | Implemented |
| Offer eligibility | Tier 1: two elements at level 3 or higher. Tier 2: three elements at level 5 or higher. No offers at tier 3, or after Overclock | Implemented |
| Evolution cards | `ABILITY_UNLOCK` definitions with `evolves_from` (the ability's current `AbilityData`) and `recipe_requirements` (elements that must be at the soft cap) | Implemented |
| Overclock | A generic `ABILITY_OVERCLOCK` card, logged per slot, that sets the permanent overclock flag. It lifts only the per-element cap to 15, and the element-count limit still applies. It blocks evolution | Implemented |
| Offer drafts | A forced draft per eligible ability: matching evolution cards, then Overclock. No decline, no reroll, no random fill. Checked after each confirmed infusion and at room start, before queued level-ups. Never stored | Implemented, Headless |
| Recipes | Elements at or above the soft cap, matched against `recipe_requirements`. A recipe may be a subset of the active elements | Implemented |
| Evolution swaps | Evolutions swap the anchor, geometry and payload strategy nodes through `execute_ability_evolution`, and replace base tags from `structural_tags` | Implemented, Written |
| Level-up drafts | Never contain evolution, Overclock or infusion cards | Implemented |

Known quirks:
- An overclocked tier 3 ability has no element-count limit.
- Until the first evolution is authored, an ability that reaches its soft cap is forced into Overclock (open item 24).

## 8. Run persistence between rooms

**Status:** Implemented. Tested through the F3 player respawn only. Room transitions are not implemented, so a real room change is untested.

Room scenes are freed on every transition, so the player's ledger and upgrades live in `RunSession.state`, a `RunState` resource.

- **Capture.** `Player._exit_tree` captures the state. It is skipped if the player is dead.
- **Restore.** `Player._ready` restores the state before `player_spawned` is emitted.
- **Reset.** `MapGenerator` calls `RunSession.reset()` when a new run starts.
- **Persisted.** Run ledger, ability runtime state (including the overclock flag), evolution gate, infusion levels, progression, current health, and the pending level-up draft queue (`pending_draft_levels`). Status cards and Overclock live in the ledger, so they persist with it.
- **Pending drafts.** `UpgradeManager` writes the on-screen level plus the queue through to `RunSession.state` on every change, because it is freed with the World scene. It reloads them in `_ready`, and drafting resumes after the player spawns. Headless-checked only.
- **Not persisted, on purpose.** Status effects, temporary modifiers, cooldown timers, uncollected pickups and offer drafts (eligibility is derived from persisted state).
- **Adding new state.** Three edits: a field in `RunState`, capture in `Player.capture_run_state`, and restore in `Player._restore_run_state`.
- **Debug.** F3 respawns the player to test the round trip. It does not free `UpgradeManager`, so it cannot test the pending drafts.

## 9. Class archetypes

**Status:** Mostly Deferred. Only the Mage starting ability is partly built.

| Class | Starting ability | Status |
| --- | --- | --- |
| Warrior | Not yet built | Deferred |
| Mage | Arcane Bolt | Partial |
| Rogue | Not yet built | Deferred |

The `player_core_blueprints` loop currently ends in `pass`, so the starting ability is granted through a debug key. Class selection needs to be wired up before the archetypes can be tested.

## 10. Open items

Numbers are stable. A gap in the numbering is an item resolved since v1.8 (6, 11, 16 and 17).

| # | Item | Type |
| --- | --- | --- |
| 1 | `UpgradeDefinition` needs a second payload field: Lightning's `stat_modifier_payload` carries CRIT\_CHANCE only (CRIT\_MULTIPLIER missing), and Fire has no STATUS\_DURATION source, so Burn lasts its 3.0 s base | Design decision |
| 2 | Fire value and card strengths are placeholders | Balance |
| 3 | Early-game specialization fails at 4 and 8 drafts in the model | Balance |
| 4 | Fire needs a value curve across a run | Balance |
| 5 | Four slots or five | Design decision |
| 7 | Nothing emits `room_completion_confirmed` | Bug |
| 8 | `boss_node` is never generated | Bug |
| 9 | `EventBus.campaign_victory_triggered` is undeclared | Bug |
| 10 | `InfusionAllocationUI` uses wrong member names (`run_ledger`, `ui_inventory_changed`). Latent: it is only reached when the player already exists | Bug |
| 12 | Enemies never drop XP and spawn at fixed coordinates | Gap |
| 13 | `player_core_blueprints` loop ends in `pass` | Gap |
| 14 | Pending level-up drafts are persisted but untested, because room transitions are not implemented | Gap |
| 15 | Trigger tags and a passive ability type are missing | Gap |
| 18 | Stats profiles of other abilities and evolutions need `DOT_DAMAGE` and `STATUS_DURATION` entries (a missing stat reads 0.0, and `mutate_base_profile` replaces the whole profile) | Gap |
| 19 | Status proc chance is not built (application is guaranteed) | Deferred |
| 20 | Scaling of Chill's slow and Burn's ramp is undefined | Design decision |
| 21 | STACK policy is untuned and unused | Balance |
| 22 | Every `AbilityData` needs `structural_tags` (Arcane Bolt may have none) | Gap |
| 23 | When infusion drafts occur in a normal run (separate draft decided; debug key only today) | Design decision |
| 24 | No evolution is authored, so an ability at its soft cap is forced into Overclock. Author the first evolution, or add an `@export` switch on `UpgradeManager` | Design decision |
| 25 | Compound designs: pairs, names, effects, tags | Design decision |
| 26 | Room transitions are not implemented | Gap |
