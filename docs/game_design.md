# Game Design Document v1.10: Modular Action Roguelite

Oct 18, 2026 · @Christopher

Last synced with code commit: `b1ca55e`. Update this line whenever this file changes.

## Revision summary

This revision aligns the design with the code as of the commit named above. Since v1.8, the infusion-to-status hook, base tags from `AbilityData`, evolution gating, the Overclock card, forced offer drafts and queue persistence are in the code. The Burn ramp (0.10 / 0.5) was set by hand on Oct 15,. Infusions are now drafted separately from level-up drafts (decided). Compounds are redefined as shared effects, with evolutions unique per ability (§4). A review of the ability driver folders (Oct 14, later the same day) added the driver library to §1, the Arcane Bolt decisions to §3 and §4, and open items 27 to 31. A later design pass (Oct 15) defined the five base infusions in §4 and the two-stat model in §5: every ability carries `BASE\_DAMAGE` and `DOT\_DAMAGE`, Fire becomes a duration and ramp-cap infusion, and indirect scalings unlock by infusion level. All of it is Decided. Fire is built; the rest is not. On Oct 16 area abilities were made to read `AOE\_RADIUS` for their reach (§4), and the evidence labels moved to `STATUS.md`. On Oct 17 and 18 the card plumbing and debug tools changed without changing the design: a card carries all its stat modifiers in one `stat\_modifiers` list, stat cards, statuses, bursts and draft eligibility read permanent tags only (temporary status tags no longer switch a card on), a stat card bought for one slot updates that slot's cached stat, and the debug tools became one F1 panel.

Every section carries one status tag:

* **Implemented**: in the code and used by the game.
* **Decided**: settled in design and specified for implementation, but not yet in the code.
* **Proof of concept**: a direction to test, with placeholder numbers.
* **Deferred**: kept from the earlier document and not scheduled.

Where this document and the code disagree, the code is the baseline until a section says otherwise.

This document holds design intent only. What was run, by whom and at which commit (Verified, Headless, Written) is recorded in `STATUS.md`, which Claude Code owns. Where the two disagree about what is built, `STATUS.md` and the code win.

## Glossary

* **Ability tier**: TIER\_1\_BASE, TIER\_2\_EVOLVED, TIER\_3\_APEX (§7).
* **Infusion tier / level**: how many times an element has been socketed into an ability (§7). Derived from the ledger.
* **Card tier**: in the multiplicative formula (§5), the number of times a card has been drafted (its duplicate count). This is a third meaning, unrelated to the two above.
* **Compound**: a fixed pair of elements that forms the same named effect on every ability (§4).
* **Offer draft**: a forced draft for one eligible ability, holding its evolution cards plus Overclock (§7).

## 1\. System architecture

**Status:** Implemented.

\[embedded content: system architecture · player, ability container, run state]

Child components never hold references to sibling nodes. The Player and each Ability are the mediators that wire components together with signals and method parameters. The Player's run ledger is the single source of truth for upgrades. The EventBus is the global signal hub, and systems find the player through `EventBus.active\_player\_instance\_id`. Because room scenes are freed on every transition, run state is held outside the room by `RunSession`. `UpgradeManager` sits under the Systems node of the World scene and is freed with it, so it writes the state it needs straight through to `RunSession.state`.

### Ability drivers

An ability is a stack of swappable drivers chosen by its `AbilityData`: a deployment anchor, a geometry driver, an optional payload driver and a stats profile.

|Layer|Existing pieces|
|-|-|
|Anchors|Caster position, mouse position|
|Projectile geometry|Targeted (nearest enemy), Straight (player movement direction), Mouse aim. All use the fan helper (`PROJECTILE\_AMOUNT`, 15 degree spread)|
|Area geometry|Radial pulse, Linear sweep (wedge), Fissure (three growing strikes along the movement direction), Converging vortex (pulls enemies in), Chain link (nearest enemy, then up to 4 jumps, `CHAIN\_RADIUS`)|
|Persistent geometry|Orbiting ring|
|Trajectories|Vector (default), Homing, Boomerang, Sine wave, Tornado|
|Payload drivers|`MissileHitPayload` only (sets the trajectory scene)|

* Every geometry delivers hits through `HurtboxComponent.take\_hit`, so status effects apply from any shape.
* All projectiles of one cast share one payload, and crit is rolled once per cast (decided, simplest).
* Each driver reads specific stats, and a missing stat reads 0.0. An evolution's stats profile must therefore carry every stat its drivers read (open item 18).
* An evolution may change family, for example from a projectile ability to an area ability (decided).
* Arcane Bolt today: caster anchor, a circular query sorted nearest-first, Targeted projectile geometry with a fan, and the Vector trajectory. The bolt is destroyed on its first hit.

### Geometry contract (Implemented, Task W)

Every concrete geometry declares its family, its reach stats (what Earth scales) and its speed stats (what Wind scales). Earth raises the `REACH\_BONUS` stat and Wind the `SPEED\_BONUS` stat; each driver multiplies its declared reach and speed stats by one plus the bonus (Task X). The radial pulse and the linear sweep share the `AreaGeometry` base (Task Y); the other classes keep their parents. The declarations sit on each driver, and a logic check fails if a geometry scene has none. Fire, Frost and Lightning need no declaration: they work through statuses, the cooldown and the cast-time crit, so they reach every geometry that ends in `HurtboxComponent.take\_hit`. Timed areas (a melee swing arc, an aura, a trap) will join the area family as wrappers around the lingering zone; summons are out of scope until designed.

|Family|Drivers|Reach stats (Earth)|Speed stats (Wind)|
|-|-|-|-|
|Moving hitbox|Targeted, Straight and Mouse aim projectiles|`AOE\_RADIUS` (hitbox)|`PROJECTILE\_MOVEMENT\_SPEED`|
|Area, instant|Radial pulse, Linear sweep, Converging vortex|`AOE\_RADIUS`|none|
|Area, stepped|Fissure (three strikes, `step\_delay` 0.12 s apart)|`AOE\_RADIUS`|the step delay, divided by one plus `SPEED\_BONUS`|
|Chain|Chain link (first-target range is `QUERY\_RADIUS`, which is targeting and not scaled; bounces `step\_delay` 0.08 s apart)|`CHAIN\_RADIUS`|the step delay, divided by one plus `SPEED\_BONUS`|
|Timed|Orbiting ring (its shards are moving hitboxes)|`ORBIT\_RADIUS`, `AOE\_RADIUS`|`ORBIT\_ROTATION\_SPEED`|

## 2\. Action bar: four ability slots and the Character Core

**Status: Implemented for slots 0 to 4; Deferred for manual casting.** The code mounts abilities in slots 1 to 4 and reserves slot 0 for the Character Core, so the player's own stats and upgrades use the same slot lookup as abilities.

|Slot|Holds|Status|
|-|-|-|
|0|Character Core: the player's stats and core upgrades (Max Health, Move Speed). Never holds an ability.|Implemented|
|1 to 4|One ability each, mounted from its `AbilityData`; fires automatically when its cooldown ends.|Implemented|
|Manual cast, dash with i-frames, passive module|Needs input-triggered casting and movement support that do not exist yet.|Deferred|

The earlier five-slot layout (Engine, Catalyst, Finisher, Dash, Passive) stays as design intent for ability roles, but roles are not tied to slot numbers. Moving to five slots would mean raising `MAX\_SLOT` in the ability container and updating the upgrade pool loops that assume four.

## 3\. Tag taxonomy

**Status:** Implemented for ability tags and status tags. Deferred for trigger tags.

Tags describe what an ability or effect is, and they decide which upgrades apply to it. They are the enum `Tags.Type`, never strings.

* **Append-only.** Tags are stored as integers in `.tres` files. New entries go at the end of the enum. Entries are never inserted, reordered or deleted. The same rule applies to `UpgradeDefinition.PayloadType` and every other enum referenced from `.tres` files.
* **Source of truth.** Each stats container reads tags from its own `TagComponent`. Callers do not pass tags in.
* **Layers.** A `TagComponent` compiles three layers: base tags, infusion tags and temporary tags. Permanent tags are base plus infusion tags. Stat cards, statuses, bursts and draft eligibility read permanent tags only. Active tags add the temporary ones and are used for damage payload tags.
* **Base tags (Implemented).** Base tags come from `AbilityData.structural\_tags`, and they replace the ability's previous base tags whenever it is mounted or evolves. An empty list logs a warning and leaves the tags unchanged. Arcane Bolt has `METAMAGIC` and `PROJECTILE`. They are provisional until the tag system is fully designed, because tags will eventually decide which global upgrades apply to an ability (open item 22). An evolution that changes family replaces the tag set, so a chain form drops `PROJECTILE` and projectile-scoped global cards stop applying to it.
* **Infusion tags.** Rebuilt from the run ledger on every recompile, so evolving never removes them.
* **Status tags (Implemented).** `BURNING`, `CHILLED` and `FROZEN` are appended to the enum. `TagComponent` grants them as temporary tags with reference counts, so a tag only clears when the last status that granted it ends. `FROZEN` has no source yet.
* **Compound tags (Deferred).** A compound tag would be granted by an evolution through its `structural\_tags`, but none exists. Plasma, the first compound, has no tag (Task R): its effect is a stat on the evolved profile (§4). A tag is added only when a card needs to target compound abilities.
* **Trigger tags (Deferred).** On Hit, On Dash, On Crit, On Crowd Control and On Health Loss do not exist yet. They need to be added before any card that depends on them.

## 4\. Elemental infusions, compounds and evolutions

**Status:** Implemented for the current stat contributions and for applying statuses, including the Fire rework. Decided, not built, for the indirect scalings, the other elements' changes and how infusions are drafted. Proof of concept for the numbers and for compounds. Deferred for compound effects.

Infusions are socketed into ability slots. They contribute through stat modifiers (`UpgradeDefinition.stat\_modifiers`), plus an optional status carried by the card (`status\_effect\_payload`, §6). Effect templates define shape, never absolute damage. The ledger stores slot-specific purchases under `<upgrade\_id>::slot\_<n>`, and that key wins over the plain key.

**Drafting (Decided).** Infusions are drafted through their own draft, separate from level-up drafts. Only elements that at least one ability can accept are offered. In the code today, this draft is reachable only from the debug panel (F1, Run tab), and level-up drafts never show infusion cards. When infusion drafts happen in a normal run is not decided (open item 23).

### Base infusions (Decided; Fire Implemented)

Each infusion has a direct stat that works from level 1 and an indirect scaling that unlocks at a higher infusion level. Unlock levels and all numbers are placeholders. Where an element's soft cap is 3, level 3 is its capstone.

|Element|Role|Direct stat (level 1)|Indirect scaling (unlock level)|Status applied|
|-|-|-|-|-|
|Fire|Duration and DoT|`STATUS\_DURATION` and `STATUS\_RAMP\_CAP`, both flat per level (Implemented). No damage of its own|Burn's ramp: the cap grows per level (Implemented), and a longer duration keeps the ramp running. DoT only|Burn (Implemented)|
|Frost|Cooldown|`COOLDOWN` (Implemented)|Level 2 (Implemented, Task AC, placeholders): bonus damage of 0.04 per 0.1 s shaved off the ability's default cooldown, counting the effective cooldown as at least 0.25 s in this calculation only (the real cooldown has no floor). Summed with the other indirect bonuses, capped at +50%, and applied as a cast-time damage scale to hit damage and DoT|Chill (Implemented)|
|Lightning|Crit|`CRIT\_CHANCE` +0.03 per level and `CRIT\_MULTIPLIER` +0.15 per level (Implemented, placeholders; open item 49)|Level 3: a crit releases an overload that damages nearby enemies for a percentage of the crit damage|None|
|Wind|Action velocity|`SPEED\_BONUS` +0.1 per level (Implemented, Task X): each driver multiplies its own speed (`PROJECTILE\_MOVEMENT\_SPEED`, `ORBIT\_ROTATION\_SPEED`) by one plus the bonus; geometries with no speed concept ignore it until they get a base delay (item 47)|Level 2 (Implemented, Task AC, placeholders): bonus damage of 0.5 * `SPEED\_BONUS` (+0.10 gives +5%), read at cast time. Summed with the other indirect bonuses, capped at +50%, and applied as a cast-time damage scale to hit damage and DoT|None|
|Earth|Area|`REACH\_BONUS` +0.1 per level (Implemented, Task X): each driver multiplies its own reach (`AOE\_RADIUS`, `CHAIN\_RADIUS`, `ORBIT\_RADIUS`) by one plus the bonus|Level 3: an on-impact explosion whose damage scales with the number of enemies it catches|None|

Rules:

* **Both channels.** Indirect bonuses apply to hit damage and to DoT. Frost and Wind compute one cast-time `damage\_scale` and apply it to the final hit damage and to `dot\_damage\_snapshot`, so ticks never read anything later. Indirect bonuses are summed into one scale and capped (open item 32). Fire's indirect is DoT only by nature.
* **Cast time, not impact time.** Wind's description says "at the point of impact". The scale is read at cast time instead, for the same reason crit is rolled once per cast.
* **One shared impact burst.** Earth's explosion and Lightning's overload are both secondary area damage centered on a hit enemy, so they share one mechanism, described below. It would also serve Magma later.
* **Burst effects scale off hit damage.** A DoT specialist gets less from the overload and the explosion. This is accepted for now.
* **Fire.** Fire deals no damage itself. Burn's damage comes from the ability's own `DOT\_DAMAGE`, and Fire turns it on by supplying duration. Implemented: flat +3.0 s duration and +0.1 ramp cap per level. Flat modifiers scale as value times tier, so level 3 is 9.0 s and +0.3. Burn's `base\_duration` is 0. All numbers are placeholders. Fire stays build agnostic: it enables DoT and lengthens it, and it never favors stacking over duration.
* **Staged unlocks.** Indirect effects unlock by infusion level (open item 33). Placeholder levels: Frost 2, Wind 2, Lightning 3, Earth 3.

### Impact bursts

**Status:** Implemented for the mechanism. Decided, not built, for the Earth and Lightning cards that use it.

A burst is not an ability. It has no slot, cooldown, anchor, stats profile or tags: it is a one-shot effect that fires when a hit lands, borrows the casting ability's numbers, and leaves nothing behind.

* **Centered on the enemy hit.** The origin is that enemy's position at the moment of the hit. The burst is not attached to the enemy, so it survives the enemy dying. Damage is credited to the casting ability.
* **Defined as data.** A burst definition holds a trigger (on hit, or on crit), an optional required tag on the primary target, a shape (none means an effect-only burst), a damage fraction, an optional bonus per enemy caught with a cap, an optional switch to carry the cast's statuses, and an optional visual. A card carries one, chosen at cast time like a status.
* **Shapes only find targets.** The shape decides where the burst reaches. Earth's explosion is a circle sized from the ability's `AOE\_RADIUS`. Lightning's overload could emit a series of sparks around the impact. Damage and every rule below are applied by one runner, so a new shape cannot skip them.
* **Damage.** A fraction of the hit's final damage (a crit's extra damage is included). With a per-enemy bonus, the fraction grows with the number of enemies caught, up to a cap.
* **Limits.** A burst never crits and never triggers another burst. It applies no status unless its definition opts in, in which case it carries the cast's statuses and their snapshots. The enemy just hit is not hit again by its own burst. A required tag is checked on the primary target before the hit's own statuses apply.
* **Per-cast cap (Implemented, Task AB).** Each burst definition has `max_per_cast` (0 = unlimited, the default, so a fan, a chain or an area hit with many targets produces a burst per qualifying hit). The limit is enforced through a per-cast budget shared by every copy of the cast's payload. Only a qualifying burst spends it. No card sets a cap yet. Open item 40 still revisits the rest.
* **Timing.** The burst runs one frame after the hit, because a hit can land inside a physics callback.
* **Lingering zones (Implemented as a component, Task V).** An effect-only burst can spawn a zone that lingers (4 s by default), re-applies the cast's statuses with their snapshots to enemies inside it every 0.5 s, and deals no damage of its own. A new zone near a live one of the same kind refreshes it instead of stacking, and at most 8 live zones per kind exist. No card uses it yet.

A card carries all its stat modifiers in one ordered list, `UpgradeDefinition.stat\_modifiers`. Fire uses two. Lightning's `CRIT\_MULTIPLIER` can use it later. See the open items.

### Compounds and evolutions

**Status:** Proof of concept, except the first evolution: Plasma's first form (Arc Bolt, chain link) and its crit-to-Burn effect are Implemented (Task R). Other compounds and evolutions are not authored.

* A **compound** is a fixed pair of elements. It always forms the same named effect on the abilities that evolve through it.
* An **evolution** is unique per ability. It changes the ability's geometry and is themed by a compound.
* **The evolution carries the compound's effect (Decided Oct 20; built by Task R for Plasma).** Plasma's effect is a stat in the evolved profile: `CRIT\_DOT\_SHARE`, a plain float (0 = off, 1.0 = the full crit multiplier). On a crit cast, the cast's Burn snapshot is multiplied by `1 + (CRIT\_MULTIPLIER - 1) * CRIT\_DOT\_SHARE`. Ticks never crit. Only evolved profiles set it. A compound tag and a shared card are added later, only if a card needs to target compound abilities. Plasma has no infusion level: progression after evolving flows through Fire and Lightning (tier 2 caps of 5), a third element, and Overclock.
* Compounds are given to element pairs one at a time. A pair with no compound only offers Overclock.

|Compound|Recipe|Placeholder shared effect|Depends on|
|-|-|-|-|
|Plasma|Fire + Lightning|A crit cast boosts the Burn snapshot (`CRIT\_DOT\_SHARE`, Implemented). The old Plasma Bleed burst reaction is Deferred|Burn and Lightning's crit|
|Magma|Fire + Earth|Lava Tiles (area hazard)|Burn, and an Earth area effect|
|Name to decide|Frost + Earth|Deep Frozen (shatter reaction)|Chill and Frozen|

The effects above are working names from v1.8 (Plasma Scorch, Magma Volcano and Brittle Fracture were the old evolution names). None has a defined mechanic, and all are **Deferred**.

### First evolution forms

An evolution may leave its ability's family (decided). The forms below are built from drivers that already exist. They are **Proof of concept**, except the Plasma form, which is **Implemented** as the first evolution (Task R).

|Compound|Arcane Bolt form (existing drivers)|What the original idea would need|
|-|-|-|
|Plasma|**Arc bolt**: Chain link geometry. Every link applies the Burn the Fire infusion carries, so Burn spreads. **Implemented as the first form (Task R).**|A piercing lance needs a pierce count and a change to `CombatVolume`|
|Magma|Fissure: three growing strikes along the movement direction|A lobbed bomb needs an on-impact burst (the spawner's `projectile\_impacted` signal is unused) and lava hazards|
|Frost + Earth|Shatter nova: Radial pulse with Chill (Converging vortex is the alternative)|A bursting shard needs fragment spawning and a `FROZEN` source|

The first form (Task R) exercises the offer draft with an evolution card, replacing the base tags, the evolved profile carrying the compound's effect, and Burn spreading through chain hits. A chain crit is all-or-nothing, because crit is rolled once per cast.

## 5\. Damage channels

**Status:** Implemented for the multiplicative modifier type and the `DOT\_DAMAGE` and `STATUS\_DURATION` stats. Balance numbers are placeholders. The two-stat model below is Decided and built for Arcane Bolt only.

There are two separate channels. A build specializes in one of them, and hit damage is not the best scaling option for both.

||Hit channel|DoT channel|
|-|-|-|
|Element|Lightning|Fire|
|Damage stat|BASE\_DAMAGE|DOT\_DAMAGE (per second)|
|Other stats|Crit chance, crit multiplier|STATUS\_DURATION|
|Crits|Yes|No, ticks never crit|
|Reads BASE\_DAMAGE|Yes|Never|

The DoT magnitude is snapshotted at cast time from the source ability into the payload (`dot\_damage\_snapshot`). When a status is applied, the snapshot is copied into that status instance. `status\_duration\_snapshot` works the same way.

### Every ability carries both stats (Decided; built for Arcane Bolt only)

* Every ability profile holds a nonzero `BASE\_DAMAGE` and a nonzero `DOT\_DAMAGE`. A hit specialist has a high `BASE\_DAMAGE` and a low `DOT\_DAMAGE`, and a DoT specialist is the reverse. Every infusion therefore applies to every ability, and a poor fit is a weak synergy, not a dead pick.
* `DOT\_DAMAGE` is inert potency. Nothing ticks until a status with a duration is applied, and today only the Fire card supplies Burn. There is no explicit duration gate: duration alone decides. Burn's template `base\_duration` becomes 0 and Fire supplies `STATUS\_DURATION`. A DoT specialist is therefore weak until Fire is socketed.
* Fire is the on-switch for DoT, and the ability's `DOT\_DAMAGE` says how hard it hits once on. Lightning's crit touches hit damage only. The infusions form a gradient across specializations: Fire favors DoT specialists, Lightning favors hit specialists, and Frost, Wind and Earth change delivery and favor neither.
* Hit and DoT need one exchange rate and a split per specialization (for example 85/15, 60/40 and 25/75, placeholders). By arithmetic from the current Burn numbers, one Burn application delivers about 3.5 times its `DOT\_DAMAGE` value. None of this is in `balance\_notes.md` yet (open item 34).
* Arcane Bolt hits for `BASE\_DAMAGE` 1.0 every 1.0 s, so its base `DOT\_DAMAGE` is 0.15 (placeholder). With Burn always on, that is about 15 to 20% of its damage, a hit specialist split. A value of 1.0 would have made one Burn application worth about 3.5 hits.
* A modifier on a stat that is missing from an ability's profile has no effect, because the stat reads 0.0. Every profile therefore needs `DOT\_DAMAGE`, `STATUS\_DURATION` and `STATUS\_RAMP\_CAP`. Arcane Bolt's profile gained `STATUS\_RAMP\_CAP: 0.0` for this reason.

### Stacking of modifiers

Card scaling is multiplicative, per card. The ledger multiplies one term per upgrade into a single product, and the stat container applies it:

```latex
\\text{final} = (\\text{base} + \\text{flat}) \\times (1 + \\text{percent}) \\times \\text{multiplicative}
```

```latex
\\text{multiplicative} = \\prod\_{\\text{cards}} (1 + \\text{value})^{\\text{tier}}
```

Here `value` is the card's value and `tier` is the card's duplicate count (see the glossary): drafting a duplicate card raises its tier. In code, `get\_modifier\_totals` returns `Vector3(flat, percent, multiplicative)`.

In the balance workbook, additive pools made hit cards the best choice for DoT builds too. Multiplicative pools passed all 6 specialization tests. All numbers are placeholders. The model still fails the specialization test at 4 and 8 drafts, and the DoT to hit ratio drifts from 1.02 to 0.80 between 4 and 20 drafts at a fixed Fire value.

Compound effects should be conditional or capped. A pair bonus or an evolution multiplier stacked on the multiplicative rule would put evolved builds ahead of every other build.

### Optional later layers

* **Mono-channel bonus (Deferred).** A bonus for committing to one channel.
* **Fire hit tax (Deferred).** A penalty on hit scaling for Fire builds.
* **Stacking (Decided Oct 18).** REFRESH is a stack cap of 1, and a stat, `STATUS\_STACK\_BONUS`, raises the cap of ticking statuses (snapshotted at cast time; templates never change). Burn's template stays REFRESH. Fire never carries the bonus, so duration builds and stacking builds are a player choice. Stack caps are not tuned: a sustained Fire 3 Burn deals about 0.27 per second per stack at the placeholder numbers, so a cap of 4 would match Arcane Bolt's hit damage (open item 45).

## 6\. Status effects

**Status:** Implemented.

### Design

* **Template resource.** `StatusEffect` holds id, base duration, stacking policy, max stacks, tick interval, two ramp floats (`ramp\_bonus\_per\_second`, `ramp\_max\_bonus`, used instead of a Curve resource), stat modifiers and granted tags. Templates define shape only and are never mutated.
* **Runtime state.** Each application gets its own `StatusEffectInstance` (per-application copies of the modifiers with unique ids), so shared payloads are never changed per hit.
* **Routing.** `StatusEffectComponent` emits `applied`, `refreshed`, `ticked` and `expired`. The Entity routes them to stats, health and tags. The component knows nothing about its siblings.
* **Tick damage.** `dot\_damage \* (1 + min(elapsed \* ramp\_bonus\_per\_second, ramp\_max\_bonus)) \* tick\_interval \* stacks`. Ticks bypass the hurtbox through `take\_dot\_damage`. They never crit and never read BASE\_DAMAGE. The cap is `ramp\_max\_bonus` plus a per-application `ramp\_cap\_bonus`, snapshotted from the `STATUS\_RAMP\_CAP` stat the same way `STATUS\_DURATION` is (Implemented).
* **Refresh.** REFRESH resets the timer and takes the newer snapshot, but keeps `elapsed`, so a sustained Burn keeps ramping. The ramp resets only after the effect expires.
* **Dead targets.** A status is not applied to an entity that is already dead, and all effects are cleared when health is depleted.
* **Persistence.** Status effects are not carried between rooms.
* **Reactions.** A hook before damage in `Entity.\_on\_hit\_received` is reserved for reactions (marked by a comment). The reactions themselves are deferred.

### Application rules (Implemented)

* **Carried by cards.** Any `UpgradeDefinition` can carry a `status\_effect\_payload`, independent of its `payload\_type`. An infusion can carry its stat modifier and its status on one card.
* **Resolved through the ledger** with the normal scope rules (a status card needs `LOCAL\_SLOT` or `GLOBAL\_TAG\_MATCH` scope to reach abilities; infusions work through slot-specific purchases). Duplicate copies of a card add nothing, and templates are deduplicated by `effect\_id`, first in purchase order wins.
* **Chosen at cast time.** The payload's `status\_effects\_to\_apply` is filled once per cast, then applied on every hit. Application is guaranteed: there is no chance stat.
* **No DOT\_DAMAGE, no ticking status.** A status that ticks (`tick\_interval > 0`) is skipped when the ability's `dot\_damage\_snapshot` is 0, with a one-time warning per `effect\_id`. A status that does not tick (Chill) always applies.
* **STATUS\_DURATION is ability-wide.** The single snapshot lengthens every status the ability applies.
* **Duration decides (Implemented).** There is no cast-time gate. A ticking Burn gets its whole duration from `STATUS\_DURATION` (template `base\_duration` 0). `apply\_effect` returns early when the effective duration is 0 or less: no instance, no `BURNING` tag, no ticks, no warning, and an already-active Burn is left alone.
* **No status variants.** Templates stay fixed. Chill's slow scaling is undefined. Burn's ramp cap grows with Fire levels through a per-application bonus, not a template change (Implemented).

### Effects

|Effect|Source|Behavior|Status|
|-|-|-|-|
|Burn|Fire|DoT with REFRESH stacking, sets BURNING. Tick 0.5 s, ramp +10% per second capped at +50% plus 0.1 per Fire level. Template `base\_duration` 0, so duration comes from Fire (+3.0 s per level)|Implemented|
|Chill|Frost|Slows the target by 30% movement speed, sets CHILLED. Base 3 s, no tick|Implemented|
|Plasma Bleed|Plasma (compound)|Burst reaction|Deferred|
|Deep Frozen|Frost + Earth compound|Shatter reaction|Deferred|
|Lava Tiles|Magma (compound)|Area hazard|Deferred|

Burn ramp: the shipped file was still 0.25 / 1.0 until Oct 15, when the designer set it by hand to the balance workbook values (+10% per second, capped at +50%). All other Burn and Chill numbers are placeholders.

## 7\. Evolution gating, progression and overclock

**Status:** Implemented. One evolution is authored (Arcane Bolt to Arc Bolt, Fire + Lightning, Task R).

|Rule|Detail|Status|
|-|-|-|
|Infusion level caps|Soft cap 3 in tier 1, soft cap 5 in tier 2, hard cap 15|Implemented|
|Unique elements|At most 2 in tier 1, at most 3 in tier 2|Implemented|
|Ability tiers|TIER\_1\_BASE, TIER\_2\_EVOLVED, TIER\_3\_APEX|Implemented|
|Offer eligibility|Tier 1: two elements at level 3 or higher. Tier 2: three elements at level 5 or higher. No offers at tier 3, or after Overclock|Implemented|
|Evolution cards|`ABILITY\_UNLOCK` definitions with `evolves\_from` (the ability's current `AbilityData`) and `recipe\_requirements` (elements that must be at the soft cap)|Implemented|
|Overclock|A generic `ABILITY\_OVERCLOCK` card, logged per slot in the ledger. Whether a slot is overclocked is derived from that purchase (`RunLedgerComponent.is\_overclocked`); no separate flag is stored or persisted. It lifts only the per-element cap to 15, and the element-count limit still applies. It blocks evolution|Implemented|
|Offer drafts|A forced draft per eligible ability: matching evolution cards, then Overclock. No decline, no reroll, no random fill. Checked after each confirmed infusion and at room start, before queued level-ups. Never stored|Implemented|
|Recipes|Elements at or above the soft cap, matched against `recipe\_requirements`. A recipe may be a subset of the active elements|Implemented|
|Evolution swaps|Evolutions swap the anchor, geometry and payload strategy nodes through `execute\_ability\_evolution`, and replace base tags from `structural\_tags`|Implemented|
|Level-up drafts|Never contain evolution, Overclock or infusion cards|Implemented|

Known quirks:

* An overclocked tier 3 ability has no element-count limit.
* A pair with no evolution (every pair except Fire + Lightning on Arcane Bolt) reaches its soft cap and is forced into Overclock (open item 24).

## 8\. Run persistence between rooms

**Status:** Implemented. Room transitions are not implemented (open item 26).

Room scenes are freed on every transition, so the player's ledger and upgrades live in `RunSession.state`, a `RunState` resource.

* **Capture.** `Player.\_exit\_tree` captures the state. It is skipped if the player is dead.
* **Restore.** `Player.\_ready` restores the state before `player\_spawned` is emitted.
* **Reset.** `MapGenerator` calls `RunSession.reset()` when a new run starts.
* **Persisted.** Run ledger, ability runtime state (the evolution state; Overclock is not part of it), evolution gate, progression, current health, and the pending level-up draft queue (`pending\_draft\_levels`). Infusion levels and the Overclock state are derived from the ledger and are not saved separately. Status cards and Overclock cards live in the ledger, so they persist with it.
* **Pending drafts.** `UpgradeManager` writes the on-screen level plus the queue through to `RunSession.state` on every change, because it is freed with the World scene. It reloads them in `\_ready`, and drafting resumes after the player spawns.
* **Not persisted, on purpose.** Status effects, temporary modifiers, cooldown timers, uncollected pickups and offer drafts (eligibility is derived from persisted state).
* **Adding new state.** Three edits: a field in `RunState`, capture in `Player.capture\_run\_state`, and restore in `Player.\_restore\_run\_state`.
* **Debug.** The F1 panel's Run tab has a "Respawn player" button that runs the same capture and restore as a room change (it replaced the old F3 key). It does not free `UpgradeManager`, so it cannot test the pending drafts.

## 9\. Class archetypes

**Status:** Mostly Deferred. Only the Mage starting ability is partly built.

|Class|Starting ability|Status|
|-|-|-|
|Warrior|Not yet built|Deferred|
|Mage|Arcane Bolt|Partial|
|Rogue|Not yet built|Deferred|

The `player\_core\_blueprints` loop currently ends in `pass`, so the starting ability is granted through the debug panel (F1, Run tab, "Grant card"). Class selection needs to be wired up before the archetypes can be tested.

## 10\. Open items

Numbers are stable. A gap in the numbering is an item resolved since v1.8 (1, 6, 11, 16, 17, 30 and 36).

|#|Item|Type|
|-|-|-|
|2|Fire value and card strengths are placeholders|Balance|
|3|Early-game specialization fails at 4 and 8 drafts in the model|Balance|
|4|Fire needs a value curve across a run. Flat modifiers scale as value times tier, so Overclock level 15 would give 45 s duration and a ramp cap of 2.0 at the placeholder values|Balance|
|5|Four slots or five|Design decision|
|7|Nothing emits `room\_completion\_confirmed`|Bug|
|8|`boss\_node` is never generated|Bug|
|9|`EventBus.campaign\_victory\_triggered` is undeclared|Bug|
|10|`InfusionAllocationUI` uses wrong member names (`run\_ledger`, `ui\_inventory\_changed`). Latent: it is only reached when the player already exists|Bug|
|12|Enemies never drop XP and spawn at fixed coordinates|Gap|
|13|`player\_core\_blueprints` loop ends in `pass`|Gap|
|14|Pending level-up drafts are persisted but untested, because room transitions are not implemented|Gap|
|15|Trigger tags and a passive ability type are missing|Gap|
|18|Stats profiles of other abilities and evolutions need `DOT\_DAMAGE`, `STATUS\_DURATION`, `STATUS\_RAMP\_CAP` and every stat their drivers read, such as `PROJECTILE\_AMOUNT`, `DURATION` or `CHAIN\_RADIUS` (a missing stat reads 0.0, and `mutate\_base\_profile` replaces the whole profile)|Gap|
|19|Status proc chance is not built (application is guaranteed)|Deferred|
|20|Chill's slow scaling is undefined (Burn's ramp cap now scales with Fire levels)|Design decision|
|21|The stack cap is a stat with no card behind it yet, so every status behaves as REFRESH today (items 44 to 46)|Balance|
|22|Every `AbilityData` needs `structural\_tags`. Arcane Bolt now has `METAMAGIC` and `PROJECTILE`. Future abilities and evolutions still need them|Gap|
|23|When infusion drafts occur in a normal run (separate draft decided; debug panel only today)|Design decision|
|24|Only Fire + Lightning on Arcane Bolt has an evolution, so every other pair at its soft cap is forced into a lone Overclock (no decline). Author more evolutions, or add an `@export` switch on `UpgradeManager`|Design decision|
|25|Compound designs: pairs, names, effects, tags|Design decision|
|26|Room transitions are not implemented. Missing: room completion (nothing emits `room\_completion\_confirmed`, nothing counts remaining enemies, and `EnemySpawnerComponent`'s `wave\_completed` and `campaign\_cleared` have no listeners) and a death or game-over flow (nothing handles `Entity.died`). See items 7 to 9|Gap|
|27|Projectile hitboxes and area abilities both read `AOE\_RADIUS` for their size and reach. Chain link and the projectile geometries keep `QUERY\_RADIUS` / `CHAIN\_RADIUS`. Still open: the sprite is not scaled with the hitbox, and every future area, projectile or orbit profile needs `AOE\_RADIUS`|Gap|
|28|No pierce: `CombatVolume` frees itself on every hit, and orbit shards (same class) vanish after one hit|Gap|
|29|The impact-burst mechanism is built, but no card uses it yet. Earth's explosion and Lightning's overload still need authoring and level gating (item 33). Magma would reuse it later|Gap|
|31|Crit is rolled once per cast (decided, simplest). Revisit if the Lightning theme needs per-hit crit|Design decision|
|32|Built (Task AC, placeholders): Frost and Wind compute one cast-time `damage\_scale`, 1 plus the summed indirect bonuses clamped to +50%. It multiplies the cast's hit damage before the crit roll and its DoT snapshot before the `CRIT\_DOT\_SHARE` bonus. It does not change status duration, ramp cap, stack bonus, tick interval, burst damage or burst shape, and a burst copy or lingering-zone hit is never scaled again. The cap is a constant in `IndirectScaling`|Built|
|33|Built for Frost and Wind (Task AC, placeholders): each card carries an optional `indirect\_effect` with its own `unlock\_level` (2 for both). The effect is active in a slot only when the card's level in that slot (`get\_card\_tier`) reaches it; direct effects are never gated. Earth's and Lightning's level 3 effects reuse the gate when built. Level gating of burst cards is not built|Partly built|
|34|The damage budget, the hit/DoT split per specialization and the hit-to-DoT exchange rate are not in `balance\_notes.md`. The workbook solved Fire as an additive amount and needs re-solving for the potency model|Balance|
|35|REFRESH takes the latest applier's snapshot, so a weaker Burn applied later can downgrade a stronger one, now that every ability can apply Burn. Left as is. Alternative: keep the higher `dot\_damage`|Design decision|
|37|Every ability profile needs nonzero `BASE\_DAMAGE` and `DOT\_DAMAGE`, plus `STATUS\_DURATION` and `STATUS\_RAMP\_CAP` entries (a missing stat ignores modifiers). Only Arcane Bolt's profile has them (`DOT\_DAMAGE` 0.15, placeholder). A headless warning for zeros was offered, not requested|Gap|
|38|Fire's duration does little for fast abilities, by arithmetic from the numbers: Arcane Bolt's cooldown is 1.0 s and Burn lasts 3.0 s at level 1, so REFRESH keeps it up, and the ramp keeps running because a refresh keeps `elapsed`. The ramp cap and Frost's cooldown cuts matter more there. Duration matters for slow abilities and after target changes|Balance|
|39|Per-hit or per-cast bursts. Built (Task AB): `max_per_cast` on each burst definition (0 = unlimited), enforced through a per-cast budget shared by the cast's payload copies. Intended values for the later cards (placeholders): Earth's explosion 3 per cast, Lightning's overload 1 per cast. No card sets a cap yet|Built|
|40|Earth's explosion on area abilities. A radial pulse already hits everything in range, so an explosion per target is mostly redundant. Option: projectile hits only, with area abilities getting only the larger radius|Design decision|
|41|Statuses on bursts are built behind an opt-in switch (Task U) and no card uses it yet. Revisit stacking and spam on chains and fans before authoring one (see item 39)|Design decision|
|42|Lightning's spark shape: spark count, reach, spread pattern, whether each spark hits like a ray or jumps like a chain, and how damage splits per spark. `BurstShape` is built so it can be added as a new shape|Design decision|
|43|A shaped burst's visual is spawned only when it catches at least one enemy; an effect-only burst (no shape) always spawns its effect (Task U). Confirm the shaped rule is wanted, and add visuals for Earth and Lightning|Design decision|
|44|How stack cards are introduced (level-up pool, a separate draft, or tied to something else). Not Fire levels: Fire stays build agnostic|Design decision|
|45|Stack caps and per-stack strength are untuned: at the placeholder numbers a cap of 4 gives a hit-specialist ability as much DoT as hit damage. Needs the hit/DoT budget (item 34) first|Balance|
|46|Stacks from several sources share one instance per target. A re-apply never lowers the stack count, so a cap-1 source keeps a cap-4 source's stacks and its own snapshot wins. Decide whether that is wanted|Design decision|
|47|Earth scales chain reach (`REACH\_BONUS` scales `CHAIN\_RADIUS`, Task X) and Wind's `SPEED\_BONUS` shortens the step delay of chain and fissure (Task Z). Wind still does nothing on the instant geometries (pulse, sweep, vortex), which have no speed concept|Design decision|
|48|Plasma numbers are placeholders. At Lightning 3 the crit chance is 14% (0.05 plus 0.03 per level) and the multiplier is 1.95, so the average Burn bonus is about +13%; at Lightning 5 it is about +25%|Balance|
|49|Lightning's crit chance and multiplier ship on the infusion card (+0.03 and +0.15 per level, placeholders; the balance workbook used +0.05 and +0.15). Whether crit stats stay on the infusion card is undecided, because the library of non-infusion cards is not designed yet. The workbook's hit-build numbers need re-running with the multiplier|Design decision|
|50|Every shape query returns at most 32 enemies (`MAX\_QUERY\_RESULTS`), so an area or chain hits only the 32 nearest in a crowd larger than that. Decide whether the limit should be higher before swarms are designed|Balance|



