# Game Design Document v1.10: Modular Action Roguelite

Oct 18, 2026 · @Christopher

Last synced with code commit: `eb56909`. Update this line whenever this file changes.

## Revision summary

This revision aligns the design with the code as of the commit named above. Since v1.8, the infusion-to-status hook, base tags from `AbilityData`, evolution gating, the Overclock card, forced offer drafts and queue persistence are in the code. The Burn ramp (0.10 / 0.5) was set by hand on Oct 15,. Infusions are now drafted separately from level-up drafts (decided). Compounds are redefined as shared effects, with evolutions unique per ability (§4). A review of the ability driver folders (Oct 14, later the same day) added the driver library to §1, the Arcane Bolt decisions to §3 and §4, and open items 27 to 31. A later design pass (Oct 15) defined the five base infusions in §4 and the two-stat model in §5: every ability carries `BASE\_DAMAGE` and `DOT\_DAMAGE`, Fire becomes a duration and ramp-cap infusion, and indirect scalings unlock by infusion level. All of it is Decided. Fire is built; the rest is not. On Oct 16 area abilities were made to read `AOE\_RADIUS` for their reach (§4), and the evidence labels moved to `STATUS.md`. On Oct 17 and 18 the card plumbing and debug tools changed without changing the design: a card carries all its stat modifiers in one `stat\_modifiers` list, stat cards, statuses, bursts and draft eligibility read permanent tags only (temporary status tags no longer switch a card on), a stat card bought for one slot updates that slot's cached stat, and the debug tools became one F1 panel.

Oct 25 and 26 (Tasks AH to AL). Compounds became cards: at the tier 1 milestone a pair with a compound gets "Evolve + compound" and "Overclock + compound" in its forced offer, and Shatter (Frost + Earth) and Magma (Fire + Earth) are built (§4). Bursts filter the statuses they carry by tag (`carried\_status\_tags`), replacing the all-or-nothing switch. DoTs no longer stack and the strongest application wins (§6). Crit is rolled per hit, not per cast (§1, §4). Open items 21, 24, 25, 29, 31, 32, 35, 38, 41, 44 to 46, 48 and 52 to 56 were updated, and item 57 was added.

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
* **Offer draft**: a forced draft for one eligible ability, holding its form evolution cards plus either the generic Overclock or, for a pair with a compound, that pair's two compound cards (§7).

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
* All projectiles of one cast share one payload. Crit is rolled per hit, when each projectile lands (decided Oct 26, Task AL), so a volley can mix crits and plain hits.
* Each driver reads specific stats, and a missing stat reads 0.0. An evolution's stats profile must therefore carry every stat its drivers read (open item 18).
* An evolution may change family, for example from a projectile ability to an area ability (decided).
* Arcane Bolt today: caster anchor, a circular query sorted nearest-first, Targeted projectile geometry with a fan, and the Vector trajectory. The bolt is destroyed on its first hit.

### Geometry contract (Implemented, Task W)

Every concrete geometry declares its family, its reach stats (what Earth scales) and its speed stats (what Wind scales). Earth raises the `REACH\_BONUS` stat and Wind the `SPEED\_BONUS` stat; each driver multiplies its declared reach and speed stats by one plus the bonus (Task X). The radial pulse and the linear sweep share the `AreaGeometry` base (Task Y); the other classes keep their parents. The declarations sit on each driver, and a logic check fails if a geometry scene has none. Fire, Frost and Lightning need no declaration: they work through statuses, the cooldown and the per-hit crit, so they reach every geometry that ends in `HurtboxComponent.take\_hit`. Timed areas (a melee swing arc, an aura, a trap) will join the area family as wrappers around the lingering zone; summons are out of scope until designed.

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
* **Compound tags (Deferred).** A compound tag would be granted by an evolution through its `structural\_tags`, but none exists. Plasma (an evolution form) and the compound cards Shatter and Magma have no tag: Plasma's effect is a stat on the evolved profile and the cards' effects are bursts (§4). A tag is added only when a card needs to target compound abilities.
* **Trigger tags (Deferred).** On Hit, On Dash, On Crit, On Crowd Control and On Health Loss do not exist yet. They need to be added before any card that depends on them.

## 4\. Elemental infusions, compounds and evolutions

**Status:** Implemented for the stat contributions, the statuses, the indirect scalings, impact bursts and three compounds (Plasma, Shatter, Magma). Decided, not built, for how infusions are drafted in a normal run. All numbers are placeholders. Seven compounds are sketches.

Infusions are socketed into ability slots. They contribute through stat modifiers (`UpgradeDefinition.stat\_modifiers`), plus an optional status carried by the card (`status\_effect\_payload`, §6). Effect templates define shape, never absolute damage. The ledger stores slot-specific purchases under `<upgrade\_id>::slot\_<n>`, and that key wins over the plain key.

**Drafting (Decided).** Infusions are drafted through their own draft, separate from level-up drafts. Only elements that at least one ability can accept are offered. In the code today, this draft is reachable only from the debug panel (F1, Run tab), and level-up drafts never show infusion cards. When infusion drafts happen in a normal run is not decided (open item 23).

### Base infusions (Decided; Fire Implemented)

Each infusion has a direct stat that works from level 1 and an indirect scaling that unlocks at a higher infusion level. Unlock levels and all numbers are placeholders. Where an element's soft cap is 3, level 3 is its capstone.

|Element|Role|Direct stat (level 1)|Indirect scaling (unlock level)|Status applied|
|-|-|-|-|-|
|Fire|Duration and DoT|`STATUS\_DURATION` and `STATUS\_RAMP\_CAP`, both flat per level (Implemented). No damage of its own|Burn's ramp: the cap grows per level (Implemented), and a longer duration keeps the ramp running. DoT only|Burn (Implemented)|
|Frost|Cooldown|`COOLDOWN` (Implemented)|Level 2 (Implemented, Task AC, placeholders): bonus damage of 0.04 per 0.1 s shaved off the ability's default cooldown, counting the effective cooldown as at least 0.25 s in this calculation only (the real cooldown has no floor). Summed with the other indirect bonuses, capped at +50%, and applied as a cast-time damage scale to hit damage and DoT|Chill (Implemented)|
|Lightning|Crit|`CRIT\_CHANCE` +0.03 per level and `CRIT\_MULTIPLIER` +0.15 per level (Implemented, placeholders; open item 49)|Level 3 (Implemented, Task AE, placeholders): a crit releases an overload, a circle of `AOE\_RADIUS` times 8 (times one plus `REACH\_BONUS`) around the enemy hit, dealing 0.6 of the crit's final damage; once per cast|None|
|Wind|Action velocity|`SPEED\_BONUS` +0.1 per level (Implemented, Task X): each driver multiplies its own speed (`PROJECTILE\_MOVEMENT\_SPEED`, `ORBIT\_ROTATION\_SPEED`) by one plus the bonus; geometries with no speed concept ignore it until they get a base delay (item 47)|Level 2 (Implemented, Task AC, placeholders): bonus damage of 0.5 * `SPEED\_BONUS` (+0.10 gives +5%), read at cast time. Summed with the other indirect bonuses, capped at +50%, and applied as a cast-time damage scale to hit damage and DoT|None|
|Earth|Area|`REACH\_BONUS` +0.1 per level (Implemented, Task X): each driver multiplies its own reach (`AOE\_RADIUS`, `CHAIN\_RADIUS`, `ORBIT\_RADIUS`) by one plus the bonus|Level 3 (Implemented, Task AE, placeholders): an on-hit explosion, a circle of `AOE\_RADIUS` times 6 (times one plus `REACH\_BONUS`) around the enemy hit, dealing 0.4 of the hit's final damage, at most 3 per cast; no per-enemy bonus yet|None|

Rules:

* **Both channels.** Indirect bonuses apply to hit damage and to DoT. Frost and Wind compute one cast-time `damage\_scale` and apply it to the final hit damage and to `dot\_damage\_snapshot`, so ticks never read anything later. Indirect bonuses are summed into one scale and capped (open item 32). Fire's indirect is DoT only by nature.
* **Cast time, not impact time.** Wind's description says "at the point of impact". The scale is read at cast time instead, so every hit of a cast carries the same scale. Crit, by contrast, is rolled per hit (Task AL).
* **One shared impact burst.** Earth's explosion and Lightning's overload are secondary area damage centered on a hit enemy, and the compound bursts use the same mechanism: Shatter (secondary damage on a Chilled enemy) and Magma's lava zone (an effect-only burst that spawns a lingering zone). They are all described below.
* **Burst effects scale off hit damage.** A DoT specialist gets less from the overload and the explosion. This is accepted for now.
* **Fire.** Fire deals no damage itself. Burn's damage comes from the ability's own `DOT\_DAMAGE`, and Fire turns it on by supplying duration. Implemented: flat +3.0 s duration and +0.1 ramp cap per level. Flat modifiers scale as value times tier, so level 3 is 9.0 s and +0.3. Burn's `base\_duration` is 0. All numbers are placeholders. Fire stays build agnostic: it enables DoT and lengthens it, and it never favors one build over another.
* **Staged unlocks.** Indirect effects unlock by infusion level (open item 33). Placeholder levels: Frost 2, Wind 2, Lightning 3, Earth 3.

### Impact bursts

**Status:** Implemented for the mechanism, the level gate, the status filter (Task AH) and four cards: Earth's explosion and Lightning's overload (Task AE), and the compound bursts Shatter and Magma's lava zone (Tasks AI, AJ). All numbers are placeholders.

A burst is not an ability. It has no slot, cooldown, anchor, stats profile or tags: it is a one-shot effect that fires when a hit lands, borrows the casting ability's numbers, and leaves nothing behind.

* **Centered on the enemy hit.** The origin is that enemy's position at the moment of the hit. The burst is not attached to the enemy, so it survives the enemy dying. Damage is credited to the casting ability.
* **Defined as data.** A burst definition holds a trigger (on hit, or on crit), an optional required tag on the primary target, a shape (none means an effect-only burst), a damage fraction, an optional bonus per enemy caught with a cap, an optional list of status tags it carries (`carried\_status\_tags`), and an optional visual. A card carries one, chosen at cast time like a status.
* **Shapes only find targets.** The shape decides where the burst reaches. Earth's explosion is a circle sized from the ability's `AOE\_RADIUS`. Lightning's overload could emit a series of sparks around the impact. Damage and every rule below are applied by one runner, so a new shape cannot skip them. A burst's size is the originating slot's AOE\_RADIUS and REACH\_BONUS, read from the caster's stats when the burst fires, times the shape's radius\_multiplier. Statuses and damage (including the triggering hit's crit) carry over from the hit's payload; crit rolls, speed and cooldown do not.
* **Damage.** A fraction of the hit's final damage (a crit's extra damage is included). With a per-enemy bonus, the fraction grows with the number of enemies caught, up to a cap. The crit is the triggering hit's own (per hit, Task AL), and ON\_CRIT bursts fire only for a critting hit.
* **Limits.** A burst never crits and never triggers another burst. It carries only the cast statuses its definition lists by tag (`carried\_status\_tags`, Task AH): a status is carried, with the cast's snapshots, only if at least one of its granted tags is listed; an empty list carries none. The enemy that triggers a burst never takes that burst's damage (it is excluded by its hurtbox id; checked headless). A required tag is checked on the primary target before the hit's own statuses apply.
* **Per-cast cap (Implemented, Task AB).** Each burst definition has `max_per_cast` (0 = unlimited, the default, so a fan, a chain or an area hit with many targets produces a burst per qualifying hit). The limit is enforced through a per-cast budget shared by every copy of the cast's payload. Only a qualifying burst spends it. The shipped bursts set caps (Earth's explosion 3, Lightning's overload 1, Shatter 2, Magma's lava zone 1; item 39). Open item 40 still revisits the rest.
* **Timing.** The burst runs one frame after the hit, because a hit can land inside a physics callback.
* **Lingering zones (Implemented as a component, Task V).** An effect-only burst can spawn a zone that lingers (4 s by default), re-applies the cast statuses its burst lets through (`carried\_status\_tags`), with their snapshots, to enemies inside it every 0.5 s, and deals no damage of its own. A new zone near a live one of the same kind refreshes it instead of stacking, and at most 8 live zones per kind exist. Magma's lava zone is the first card to use it (Task AJ).

A card carries all its stat modifiers in one ordered list, `UpgradeDefinition.stat\_modifiers`. Fire uses two. Lightning's `CRIT\_MULTIPLIER` can use it later. See the open items.

### Compound infusions

**Status:** Decided. Built for Shatter and Magma (Tasks AI and AJ, placeholders); Plasma is built as an evolution form (§4, "Compounds and evolutions"). Seven compounds are sketches.

Rules (Decided Oct 25):

* Ten compounds, one per unordered pair of the five base elements. A compound has no level and no tag of its own. Each needs a distinct on-hit or on-cast mechanic built from bursts, zones, statuses or tag conditions, not a stat bridge. Names and numbers are placeholders.
* **Delivered at the tier 1 milestone, as cards.** When an ability reaches two elements at level 3 (its forced offer, §7) and the pool has compound cards for that pair, the offer shows exactly two compound cards: "Evolve + compound" (evolve to tier 2: cap 5, three elements) and "Overclock + compound" (cap 15, no evolution). The compound effect is identical on both, so the player keeps the broad-or-deep choice and the compound follows from the pair already chosen. The generic Overclock is not offered for that pair. Form evolutions, when authored for the pair, are listed first.
* **Shared, not per ability.** One pair of cards per compound serves every ability, so no per-ability authoring is needed. A card is a slot-specific purchase, so its effect reaches only the slot that took it.
* **One compound per ability at tier 1**, because a tier 1 ability has exactly two elements. Compounds at tier 2 (three elements, up to three pairs) are not designed or built (item 54).
* Compounds arrive at level 3 in both elements. The first draft said soft cap 5; that was replaced.

|Pair|Name|Mechanic|Status|
|-|-|-|-|
|Fire + Lightning|Plasma|Evolution form (Arc Bolt), not a card: the evolved profile has `CRIT\_DOT\_SHARE` 1.0, so a critting hit's own Burn snapshot is scaled by the crit bonus (per hit since Task AL)|Built (evolution), untuned|
|Fire + Earth|Magma|ON\_HIT effect-only burst that spawns a lingering lava zone (radius `AOE\_RADIUS` times 6, 4 s, applies every 0.5 s, 1 per cast, at most 8 live zones). It re-applies only Burn (`carried\_status\_tags` BURNING) and deals no direct damage|Built (Task AJ), placeholders|
|Frost + Earth|Shatter|ON\_HIT burst on a CHILLED primary: radius `AOE\_RADIUS` times 8, 0.5 of the hit's final damage, 2 per cast, carries only Chill (`carried\_status\_tags` CHILLED). No Chill consumption in v1. The hit's own Chill does not count on its first hit|Built (Task AI), placeholders|
|Lightning + Wind|Storm|Mechanic not yet designed|Sketched|
|Frost + Wind|Blizzard|Mechanic not yet designed|Sketched|
|Fire + Frost|Steam cloud|Idea (unapproved): a lingering zone; mechanic not yet designed|Sketched|
|Frost + Lightning|Superconduct|Mechanic not yet designed|Sketched|
|Fire + Wind|Wildfire|Idea (unapproved): a burst on a Burning target that spreads Burn (the status filter and the BURNING tag now exist)|Sketched|
|Lightning + Earth|(unnamed)|Mechanic not yet designed|Sketched|
|Wind + Earth|Sandstorm|Needs a new status|Sketched|

### Compounds and evolutions

**Status:** Plasma's first form (Arc Bolt, chain link) and its crit-to-Burn effect are Implemented (Task R; per hit since Task AL). Shatter and Magma are Implemented as compound cards (Tasks AI, AJ). Other compounds and evolutions are not authored.

* A **compound** is a fixed pair of elements. It always forms the same named effect on every ability that takes it.
* An **evolution form** is unique per ability. It changes the ability's geometry and may be themed by a compound. A form is optional: a compound does not need one.
* **Two ways a compound's effect is delivered.** Cards (Shatter, Magma; Decided Oct 25): see "Compound infusions". Evolved profile (Plasma; Decided Oct 20, built by Task R): the effect is a stat in the evolved profile, `CRIT\_DOT\_SHARE`, a plain float (0 = off, 1.0 = the full crit multiplier). A critting hit multiplies its own Burn snapshot by `1 + (CRIT\_MULTIPLIER - 1) \* CRIT\_DOT\_SHARE`. Ticks never crit. Only evolved profiles set it. Plasma has no infusion level: progression after evolving flows through Fire and Lightning (tier 2 caps of 5), a third element, and Overclock. Because the effect lives on Arc Bolt's profile, a Fire + Lightning slot that takes the generic Overclock gets no Plasma effect (item 57).
* A pair with no compound cards and no form evolution only offers the generic Overclock (item 24).

The compound table in "Compound infusions" is the one list of compound effects. The v1.8 working names (Plasma Scorch, Magma Volcano, Brittle Fracture, Plasma Bleed, Deep Frozen, Lava Tiles) are retired; Plasma Bleed stays a deferred idea in §6.

### First evolution forms

An evolution may leave its ability's family (decided). The forms below are built from drivers that already exist. They are **Proof of concept**, except the Plasma form, which is **Implemented** as the first evolution (Task R).

|Compound|Arcane Bolt form (existing drivers)|What the original idea would need|
|-|-|-|
|Plasma|**Arc bolt**: Chain link geometry. Every link applies the Burn the Fire infusion carries, so Burn spreads. **Implemented as the first form (Task R).**|A piercing lance needs a pierce count and a change to `CombatVolume`|
|Magma|Fissure: three growing strikes along the movement direction|A lobbed bomb needs an on-impact burst (the spawner's `projectile\_impacted` signal is unused) and lava hazards|
|Frost + Earth|Shatter nova: Radial pulse with Chill (Converging vortex is the alternative)|A bursting shard needs fragment spawning and a `FROZEN` source|

The first form (Task R) exercises the offer draft with an evolution card, replacing the base tags, the evolved profile carrying the compound's effect, and Burn spreading through chain hits. A chain's crits are rolled per hit (Task AL), so each link may crit or not, and a critting link's own Burn is boosted. The Magma and Shatter rows above are optional ability forms now: both compounds are delivered by cards and need no form.

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
* **Re-applying (Decided Oct 26, Task AK).** Statuses never stack: one instance per effect per target. Re-applying an active ticking status, the strongest application wins: if the new `dot\_damage` is at least the existing one (a tie takes the newer), the new `dot\_damage`, duration bonus and ramp cap bonus are adopted as a unit, otherwise the existing ones stay. `elapsed` is kept, `refreshed` is emitted and the timer becomes the longer of the time left and the new application's duration. A non-ticking status (Chill) adopts the latest values and resets its timer. Fire never favors a build: it supplies duration and ramp cap only.

## 6\. Status effects

**Status:** Implemented.

### Design

* **Template resource.** `StatusEffect` holds id, base duration, tick interval, two ramp floats (`ramp\_bonus\_per\_second`, `ramp\_max\_bonus`, used instead of a Curve resource), stat modifiers and granted tags. Templates define shape only and are never mutated.
* **Runtime state.** Each application gets its own `StatusEffectInstance` (per-application copies of the modifiers with unique ids), so shared payloads are never changed per hit.
* **Routing.** `StatusEffectComponent` emits `applied`, `refreshed`, `ticked` and `expired`. The Entity routes them to stats, health and tags. The component knows nothing about its siblings.
* **Tick damage.** `dot\_damage \* (1 + min(elapsed \* ramp\_bonus\_per\_second, ramp\_max\_bonus)) \* tick\_interval`. Ticks bypass the hurtbox through `take\_dot\_damage`. They never crit and never read BASE\_DAMAGE. The cap is `ramp\_max\_bonus` plus a per-application `ramp\_cap\_bonus`, snapshotted from the `STATUS\_RAMP\_CAP` stat the same way `STATUS\_DURATION` is (Implemented).
* **Refresh.** Re-applying follows the Re-applying rule above. In every case `elapsed` is kept, so a sustained Burn keeps ramping. The ramp resets only after the effect expires.
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
|Burn|Fire|DoT, never stacks (the strongest application wins), sets BURNING. Tick 0.5 s, ramp +10% per second capped at +50% plus 0.1 per Fire level. Template `base\_duration` 0, so duration comes from Fire (+3.0 s per level)|Implemented|
|Chill|Frost|Slows the target by 30% movement speed, sets CHILLED. Base 3 s, no tick|Implemented|
|Plasma Bleed|Plasma (compound)|Burst reaction|Deferred|
|Shatter|Frost + Earth compound|Burst on a Chilled primary that spreads Chill|Implemented (Task AI)|
|Magma lava zone|Fire + Earth compound|Lingering zone that re-applies Burn|Implemented (Task AJ)|

Burn ramp: the shipped file was still 0.25 / 1.0 until Oct 15, when the designer set it by hand to the balance workbook values (+10% per second, capped at +50%). All other Burn and Chill numbers are placeholders.

## 7\. Evolution gating, progression and overclock

**Status:** Implemented. One form evolution is authored (Arcane Bolt to Arc Bolt, Fire + Lightning, Task R), and two compounds are delivered by cards (Shatter, Magma; Tasks AI, AJ).

|Rule|Detail|Status|
|-|-|-|
|Infusion level caps|Soft cap 3 in tier 1, soft cap 5 in tier 2, hard cap 15|Implemented|
|Unique elements|At most 2 in tier 1, at most 3 in tier 2|Implemented|
|Ability tiers|TIER\_1\_BASE, TIER\_2\_EVOLVED, TIER\_3\_APEX|Implemented|
|Offer eligibility|Tier 1: two elements at level 3 or higher. Tier 2: three elements at level 5 or higher. No offers at tier 3, or after Overclock|Implemented|
|Evolution cards|`ABILITY\_UNLOCK` definitions with `evolves\_from` (the ability's current `AbilityData`) and `recipe\_requirements` (elements that must be at the soft cap)|Implemented|
|Compound cards|`compound\_pair` (two elements) on an `UpgradeDefinition`. Offered only at tier 1 with exactly two elements at level 3, as "Evolve + compound" (`ABILITY\_UNLOCK`, no `evolves\_from`: advances the evolution state with no swap) and "Overclock + compound" (`ABILITY\_OVERCLOCK`). Slot-specific purchases. Never in level-up drafts|Implemented|
|Overclock|A generic `ABILITY\_OVERCLOCK` card, logged per slot in the ledger. Whether a slot is overclocked is derived from that purchase (`RunLedgerComponent.is\_overclocked`); no separate flag is stored or persisted. It lifts only the per-element cap to 15, and the element-count limit still applies. It blocks evolution. A compound Overclock card is an `ABILITY\_OVERCLOCK` card too and follows the same rule|Implemented|
|Offer drafts|A forced draft per eligible ability: matching form evolution cards, then Overclock, or for a pair with a compound its two compound cards instead of the generic Overclock. No decline, no reroll, no random fill. Checked after each confirmed infusion and at room start, before queued level-ups. Never stored|Implemented|
|Recipes|Elements at or above the soft cap, matched against `recipe\_requirements`. A recipe may be a subset of the active elements|Implemented|
|Evolution swaps|Evolutions swap the anchor, geometry and payload strategy nodes through `execute\_ability\_evolution`, and replace base tags from `structural\_tags`|Implemented|
|Level-up drafts|Never contain evolution, Overclock, compound or infusion cards|Implemented|

Known quirks:

* An overclocked tier 3 ability has no element-count limit.
* A pair with neither a form evolution nor compound cards (every pair except Fire + Lightning on Arcane Bolt, Frost + Earth and Fire + Earth) reaches its soft cap and is forced into the generic Overclock (open item 24).

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
|21|Closed (Task AK): statuses never stack, so there is no stack cap to tune (items 44 to 46 are closed with it)|Closed|
|22|Every `AbilityData` needs `structural\_tags`. Arcane Bolt now has `METAMAGIC` and `PROJECTILE`. Future abilities and evolutions still need them|Gap|
|23|When infusion drafts occur in a normal run (separate draft decided; debug panel only today)|Design decision|
|24|Only Fire + Lightning on Arcane Bolt has a form evolution, and only Frost + Earth and Fire + Earth have compound cards (Tasks AI, AJ). Every other pair at its soft cap is forced into a lone generic Overclock (no decline). Author more compounds or forms, or add an `@export` switch on `UpgradeManager`|Design decision|
|25|Compound designs: delivery is decided (Oct 25) and three are built (Plasma, Shatter, Magma). Names, effects and tags of the other seven are open|Design decision|
|26|Room transitions are not implemented. Missing: room completion (nothing emits `room\_completion\_confirmed`, nothing counts remaining enemies, and `EnemySpawnerComponent`'s `wave\_completed` and `campaign\_cleared` have no listeners) and a death or game-over flow (nothing handles `Entity.died`). See items 7 to 9|Gap|
|27|Projectile hitboxes and area abilities both read `AOE\_RADIUS` for their size and reach. Chain link and the projectile geometries keep `QUERY\_RADIUS` / `CHAIN\_RADIUS`. Still open: the sprite is not scaled with the hitbox, and every future area, projectile or orbit profile needs `AOE\_RADIUS`|Gap|
|28|No pierce: `CombatVolume` frees itself on every hit, and orbit shards (same class) vanish after one hit|Gap|
|29|The impact-burst mechanism is built and used by Earth's explosion and Lightning's overload (Task AE), Shatter (Task AI) and Magma's lava zone (Task AJ), all placeholders|Built|
|31|Built (Task AL, decided Oct 26): crit is rolled per hit. Reason: a volley or chain should show a mix of crits and plain hits (future damage numbers). See CLAUDE.md "Crit"|Built|
|32|Built (Task AC, placeholders): Frost and Wind compute one cast-time `damage\_scale`, 1 plus the summed indirect bonuses clamped to +50%. It multiplies the cast's pre-crit hit damage and its DoT snapshot; each hit's crit and the `CRIT\_DOT\_SHARE` bonus apply afterwards, per hit. It does not change status duration, ramp cap, tick interval, burst damage or burst shape, and a burst copy or lingering-zone hit is never scaled again. The cap is a constant in `IndirectScaling`|Built|
|33|Built for Frost and Wind (Task AC, placeholders): each card carries an optional `indirect\_effect` with its own `unlock\_level` (2 for both). The effect is active in a slot only when the card's level in that slot (`get\_card\_tier`) reaches it; direct effects are never gated. Burst cards are gated too (Task AE): `ImpactBurstDefinition.unlock_level` (3 for the Earth explosion and the Lightning overload), checked in the ledger with the same gate and the same tier lookup, so a slot gets the burst only when the card's level in that slot reaches it|Built|
|34|The damage budget, the hit/DoT split per specialization and the hit-to-DoT exchange rate are not in `balance\_notes.md`. The workbook solved Fire as an additive amount and needs re-solving for the potency model|Balance|
|35|Built (Task AK, decided Oct 26): the strongest application wins. A weaker Burn applied later no longer downgrades a stronger one (the stronger `dot\_damage`, duration bonus and ramp cap stay as a unit, and the timer is the longer). A crit-boosted Burn therefore lasts until it expires (item 48)|Built|
|37|Every ability profile needs nonzero `BASE\_DAMAGE` and `DOT\_DAMAGE`, plus `STATUS\_DURATION` and `STATUS\_RAMP\_CAP` entries (a missing stat ignores modifiers). Only Arcane Bolt's profile has them (`DOT\_DAMAGE` 0.15, placeholder). A headless warning for zeros was offered, not requested|Gap|
|38|Fire's duration does little for fast abilities, by arithmetic from the numbers: Arcane Bolt's cooldown is 1.0 s and Burn lasts 3.0 s at level 1, so a re-apply keeps it up, and the ramp keeps running because a refresh keeps `elapsed`. The ramp cap and Frost's cooldown cuts matter more there. Duration matters for slow abilities and after target changes|Balance|
|39|Per-hit or per-cast bursts. Built (Task AB): `max_per_cast` on each burst definition (0 = unlimited), enforced through a per-cast budget shared by the cast's payload copies. The first caps are set (Task AE, placeholders): Earth's explosion 3 per cast, Lightning's overload 1 per cast|Built|
|40|Earth's explosion on area abilities. A radial pulse already hits everything in range, so an explosion per target is mostly redundant. Option: projectile hits only, with area abilities getting only the larger radius|Design decision|
|41|Statuses on bursts are filtered by `carried\_status\_tags` (Task AH): Shatter carries Chill and Magma's zone carries Burn. Revisit spam on chains and fans (a status never stacks, but each hit re-applies it) before authoring more|Design decision|
|42|Lightning's spark shape: spark count, reach, spread pattern, whether each spark hits like a ray or jumps like a chain, and how damage splits per spark. `BurstShape` is built so it can be added as a new shape|Design decision|
|43|A shaped burst's visual is spawned only when it catches at least one enemy; an effect-only burst (no shape) always spawns its effect (Task U). Confirm the shaped rule is wanted, and add visuals for Earth and Lightning|Design decision|
|44|Closed (Task AK): there are no stack cards|Closed|
|45|Closed (Task AK): there are no stack caps to tune|Closed|
|46|Closed (Task AK): statuses never stack. Several sources share one instance and the strongest application wins|Closed|
|47|Earth scales chain reach (`REACH\_BONUS` scales `CHAIN\_RADIUS`, Task X) and Wind's `SPEED\_BONUS` shortens the step delay of chain and fissure (Task Z). Wind still does nothing on the instant geometries (pulse, sweep, vortex), which have no speed concept|Design decision|
|48|Plasma numbers are placeholders. Crit is rolled per hit (Task AL): at Lightning 3 the chance is 14% and the multiplier 1.95. Because the strongest application wins (Task AK), one critting hit puts a crit-strength Burn on its target that later plain hits cannot lower, so the average Burn bonus is higher than the per-hit +13% (Lightning 3) or +25% (Lightning 5). Needs retuning|Balance|
|49|Lightning's crit chance and multiplier ship on the infusion card (+0.03 and +0.15 per level, placeholders; the balance workbook used +0.05 and +0.15). Whether crit stats stay on the infusion card is undecided, because the library of non-infusion cards is not designed yet. The workbook's hit-build numbers need re-running with the multiplier|Design decision|
|50|Every shape query returns at most 32 enemies (`MAX\_QUERY\_RESULTS`), so an area or chain hits only the 32 nearest in a crowd larger than that. Decide whether the limit should be higher before swarms are designed|Balance|
|51|Earth's explosion is meant for projectile and chain hits only (see item 40). Both current abilities (Arcane Bolt, Arc Bolt) are projectile or chain, so it is unrestricted until an area ability exists|Design decision|
|52|Decided (Oct 25, Tasks AI and AJ): compounds are cards, offered at the tier 1 milestone as "Evolve + compound" and "Overclock + compound" with an identical effect, generic across abilities. Plasma stays an evolution form (item 57)|Built|
|53|Closed (Task AH): `ImpactBurstDefinition.carried\_status\_tags` replaces the `applies\_statuses` switch. A burst carries a cast status only if one of its granted tags is listed; an empty list carries none|Built|
|54|Compound stacking. A tier 1 ability has exactly two elements, so it gets exactly one compound. Tier 2 allows three elements (up to three pairs); how compounds work at tier 2 is not designed or built|Open|
|55|Closed: the enemy that triggers a burst does not take the burst's damage. It is excluded by its hurtbox id (`SpatialQuery.filter\_enemy\_hurtboxes`), and a logic check covers it|Closed|
|56|Closed (Task AI): a CHILLED tag exists. Compound cards are offered through `compound\_pair` and `UpgradeManager.get\_compound\_pair` (tier 1, exactly two elements, both at level 3), not through `evolves\_from` and recipes, so a recipe never has to express a level|Built|
|57|Plasma is an evolution form, not a compound card: its effect (`CRIT\_DOT\_SHARE` 1.0) lives on Arc Bolt's evolved profile. A Fire + Lightning slot that takes the generic Overclock, or an ability with no Plasma form, gets no Plasma effect. Decide whether Plasma moves onto cards like Shatter and Magma (the stat would then need to be a card modifier or sit in every ability profile)|Design decision|



