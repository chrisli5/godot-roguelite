# Game Design Document v1.10: Modular Action Roguelite

Oct 18, 2026 · @Christopher

Last synced with code commit: `db332a1`. Update this line whenever this file changes.

## Revision summary

This revision aligns the design with the code as of the commit named above. Since v1.8, the infusion-to-status hook, base tags from `AbilityData`, evolution gating, the Overclock card, forced offer drafts and queue persistence are in the code. The Burn ramp (0.10 / 0.5) was set by hand on Oct 15,. Infusions are now drafted separately from level-up drafts (decided). Compounds are redefined as shared effects, with evolutions unique per ability (§4). A review of the ability driver folders (Oct 14, later the same day) added the driver library to §1, the Arcane Bolt decisions to §3 and §4, and open items 27 to 31. A later design pass (Oct 15) defined the five base infusions in §4 and the two-stat model in §5: every ability carries `BASE\_DAMAGE` and `DOT\_DAMAGE`, Fire becomes a duration and ramp-cap infusion, and indirect scalings unlock by infusion level. All of it is Decided. Fire is built; the rest is not. On Oct 16 area abilities were made to read `AOE\_RADIUS` for their reach (§4), and the evidence labels moved to `STATUS.md`. On Oct 17 and 18 the card plumbing and debug tools changed without changing the design: a card carries all its stat modifiers in one `stat\_modifiers` list, stat cards, statuses, bursts and draft eligibility read permanent tags only (temporary status tags no longer switch a card on), a stat card bought for one slot updates that slot's cached stat, and the debug tools became one F1 panel.

Oct 25 and 26 (Tasks AH to AL). Compounds became cards: at the tier 1 milestone a pair with a compound gets "Evolve + compound" and "Overclock + compound" in its forced offer, and Shatter (Frost + Earth) and Magma (Fire + Earth) are built (§4). Bursts filter the statuses they carry by tag (`carried\_status\_tags`), replacing the all-or-nothing switch. DoTs no longer stack and the strongest application wins (§6). Crit is rolled per hit, not per cast (§1, §4). Open items 21, 24, 25, 29, 31, 32, 35, 38, 41, 44 to 46, 48 and 52 to 56 were updated, and item 57 was added.

Oct 26 (Task AP, docs only). The status design system: Fire is the only base infusion with a status, every other status comes from a compound card, a Fire compound carries none, and Chill moved from the Frost card to the Shatter cards (Task AO, §4, §6). Open items 54 and 57 were updated, and items 58 to 60 were added.

Oct 27 (Task AR, docs only entry). Status strength: `STATUS\_MAGNITUDE\_BONUS` scales non-ticking statuses (Chill), `STATUS\_DURATION` stays as is, global tag cards now need ALL their target tags (§6, items 20, 58, 61).

Oct 27 (Task AU, docs in Task AV). The Earth explosion and Lightning overload bursts were removed; at level 3 Lightning (`CRIT\_CHANCE`) and Earth (`REACH\_BONUS`) add to the shared indirect damage scale, and bursts now belong to compounds (§4, §5, items 29, 33, 39, 40, 42, 48, 51, 57; item 62 added).

Oct 28 (Tasks AW and AX, docs in Task AY). Storm (Lightning + Wind) is built: a critting hit calls down one extra strike on the enemy it hit, and its cards carry Shock, which raises the crit chance of every hit the enemy receives (§4, §6, items 55, 59, 63).

Oct 29 (design pass, docs only). Decided: (1) a three-layer model: an infusion is one stat theme, a compound is a stat bridge between two themes plus at most one status, and anything that spawns in the world belongs to an ability or its form (§4); (2) infusion stats are FLAT and generic stat cards are PERCENT, with element-gated cards for stacking a theme (§4, §5); (3) Frost becomes `COOLDOWN_BONUS` (Task BC); (4) the indirect damage scalings are removed (Task BC). The ten stat bridges are proposed, not decided (item 65). Whether a form arrives at tier 2 is open (item 66). Tasks AZ and BA (Superconduct, Blizzard) are recorded. Items 24, 25, 32, 33, 47, 49, 54, 57, 61, 62 and 63 were updated and items 64 to 68 were added.

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
* **Compound**: a fixed pair of elements that forms the same stat bridge, and at most one status, on every ability (§4).
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
* **Status tags (Implemented).** `BURNING`, `CHILLED`, `FROZEN` and `SHOCKED` are appended to the enum. `TagComponent` grants them as temporary tags with reference counts, so a tag only clears when the last status that granted it ends. `FROZEN` has no source yet.
* **Compound tags (Deferred).** A compound tag would be granted by an evolution through its `structural\_tags`, but none exists. Plasma (an evolution form) and the compound cards Shatter and Magma have no tag: Plasma's effect is a stat on the evolved profile and the cards' effects are bursts (§4). A tag is added only when a card needs to target compound abilities.
* **Trigger tags (Deferred).** On Hit, On Dash, On Crit, On Crowd Control and On Health Loss do not exist yet. They need to be added before any card that depends on them.

## 4\. Elemental infusions, compounds and evolutions

**Status:** Implemented for one stat theme per base infusion (Task BC), the statuses, impact bursts and six compounds (Plasma as an evolution form; Shatter, Magma, Storm, Superconduct and Blizzard as cards). Decided, not built: compounds as stat bridges with spawned effects moving to abilities and forms (items 64, 65), and how infusions are drafted in a normal run. All numbers are placeholders. Four compounds are sketches.

Infusions are socketed into ability slots. They contribute through stat modifiers (`UpgradeDefinition.stat\_modifiers`), plus an optional status carried by the card (`status\_effect\_payload`, §6). Effect templates define shape, never absolute damage. The ledger stores slot-specific purchases under `<upgrade\_id>::slot\_<n>`, and that key wins over the plain key.

**Drafting (Decided).** Infusions are drafted through their own draft, separate from level-up drafts. Only elements that at least one ability can accept are offered. In the code today, this draft is reachable only from the debug panel (F1, Run tab), and level-up drafts never show infusion cards. When infusion drafts happen in a normal run is not decided (open item 23).

### Layer model (Decided Oct 29)

Each layer carries one idea:

1. **Infusion:** one stat theme, raised per level.
2. **Compound:** two themes interact through a stat bridge, with at most one status.
3. **Form evolution:** this ability transforms. Anything that spawns in the world (a burst, a zone, a strike) belongs to the ability or its form, not to a compound (item 64).

### Base infusions (Implemented, Task BC)

Each infusion is one stat theme, applied as FLAT modifiers. Generic stat cards are PERCENT and amplify what the infusions provide. All numbers are placeholders.

|Element|Theme|Stat per level (FLAT)|
|-|-|-|
|Fire|Burn lasts longer and burns hotter|`STATUS_DURATION` +3.0 s and `STATUS_RAMP_CAP` +0.1; applies Burn (the one infusion with a status)|
|Frost|Faster cooldown|`COOLDOWN_BONUS` +0.1; the ability waits `COOLDOWN / (1 + COOLDOWN_BONUS)` (1.0 s base: 0.77 s at level 3, 0.40 s at 15)|
|Lightning|Critical hits|`CRIT_CHANCE` +0.03 and `CRIT_MULTIPLIER` +0.15 (item 49)|
|Wind|Faster delivery|`SPEED_BONUS` +0.1|
|Earth|Wider reach|`REACH_BONUS` +0.1|

Rules:

* **Foundation and amplifier.** The infusion supplies the base amount; PERCENT cards multiply it. A PERCENT card on a stat whose base is 0 (`COOLDOWN_BONUS`, `SPEED_BONUS`, `REACH_BONUS`, Fire's stats) does nothing without the infusion, so a generic card meant to work alone must be FLAT.
* **Stacking a theme.** Element-gated cards are ordinary cards with `GLOBAL_TAG_MATCH` and the element's tag (Task AR); they need no special code.
* **No indirect damage.** The indirect scalings (Frost cooldown, Wind speed, Lightning crit, Earth reach converted to a damage scale, capped at +50%) were removed in Task BC. Frost, Wind and Earth change delivery and favor neither channel; damage comes from the damage stats and compounds. Frost leans toward hit builds, because extra casts do not raise Burn's damage (item 38).
* **Cast time, not impact time** (kept): speed and reach are read at cast time; crit is rolled per hit (Task AL).
* **Fire.** Fire deals no damage itself. Burn's damage comes from the ability's own `DOT\_DAMAGE`, and Fire turns it on by supplying duration. Implemented: flat +3.0 s duration and +0.1 ramp cap per level. Flat modifiers scale as value times tier, so level 3 is 9.0 s and +0.3. Burn's `base\_duration` is 0. All numbers are placeholders. Fire stays build agnostic: it enables DoT and lengthens it, and it never favors one build over another.
* **Status sources (Decided Oct 26).** Fire is the only base infusion with a status (Burn). Frost, Lightning, Wind and Earth apply none. Every other status comes from a compound card, so the designer assigns each compound's status explicitly. A compound that includes Fire carries no status of its own: the ability's status is Burn, and the compound may use, spread or amplify it. A compound without Fire carries at most one. An ability therefore applies at most one status at tier 1. Players also have no non-Fire status before their first compound.

### Impact bursts

**Status:** Implemented for the mechanism, the level gate, the status filter and the compound bursts built so far (Shatter, Magma's lava zone, Storm's strike, Blizzard's vortex; Tasks AI, AJ, AW, BA). Direction (Decided Oct 29, not built): bursts, zones and strikes become part of abilities and forms instead of compound cards (item 64); the runner, shapes and `LingeringZone` stay and are reused. All numbers are placeholders.

A burst is not an ability. It has no slot, cooldown, anchor, stats profile or tags: it is a one-shot effect that fires when a hit lands, borrows the casting ability's numbers, and leaves nothing behind.

* **Centered on the enemy hit.** The origin is that enemy's position at the moment of the hit. The burst is not attached to the enemy, so it survives the enemy dying. Damage is credited to the casting ability.
* **Defined as data.** A burst definition holds a trigger (on hit, or on crit), an optional required tag on the primary target, a shape (none means an effect-only burst), a damage fraction, an optional bonus per enemy caught with a cap, an optional list of status tags it carries (`carried\_status\_tags`), and an optional visual. A card carries one, chosen at cast time like a status.
* **Shapes only find targets.** The shape decides where the burst reaches. A circle burst, as Shatter uses, is sized from the ability's `AOE\_RADIUS`. Damage and every rule below are applied by one runner, so a new shape cannot skip them. A burst's size is the originating slot's AOE\_RADIUS and REACH\_BONUS, read from the caster's stats when the burst fires, times the shape's radius\_multiplier. Statuses and damage (including the triggering hit's crit) carry over from the hit's payload; crit rolls, speed and cooldown do not.
* **Damage.** A fraction of the hit's final damage (a crit's extra damage is included). With a per-enemy bonus, the fraction grows with the number of enemies caught, up to a cap. The crit is the triggering hit's own (per hit, Task AL), and ON\_CRIT bursts fire only for a critting hit.
* **Limits.** A burst never crits and never triggers another burst. It carries only the cast statuses its definition lists by tag (`carried\_status\_tags`, Task AH): a status is carried, with the cast's snapshots, only if at least one of its granted tags is listed; an empty list carries none. The enemy that triggers a burst never takes that burst's damage (it is excluded by its hurtbox id; checked headless), with one exception: a strike-mode burst (`hits\_primary`, Task AW, Storm) hits only that enemy and does nothing if it is already dead. A required tag is checked on the primary target before the hit's own statuses apply.
* **Per-cast cap (Implemented, Task AB).** Each burst definition has `max_per_cast` (0 = unlimited, the default, so a fan, a chain or an area hit with many targets produces a burst per qualifying hit). The limit is enforced through a per-cast budget shared by every copy of the cast's payload. Only a qualifying burst spends it. The shipped bursts set caps (Shatter 2, Magma's lava zone 1; item 39). Open item 40 still revisits the rest.
* **Timing.** The burst runs one frame after the hit, because a hit can land inside a physics callback.
* **Lingering zones (Implemented as a component, Task V).** An effect-only burst can spawn a zone that lingers (4 s by default), re-applies the cast statuses its burst lets through (`carried\_status\_tags`), with their snapshots, to enemies inside it every 0.5 s, and deals no damage of its own. A new zone near a live one of the same kind refreshes it instead of stacking, and at most 8 live zones per kind exist. Magma's lava zone is the first card to use it (Task AJ).

A card carries all its stat modifiers in one ordered list, `UpgradeDefinition.stat\_modifiers`. Fire uses two. Lightning's `CRIT\_MULTIPLIER` can use it later. See the open items.

### Compound infusions

**Status:** Decided. Built: Plasma (as an evolution form), and Shatter, Magma, Storm, Superconduct and Blizzard as cards (Tasks AI, AJ, AW, AX, AZ, BA), placeholders. Four compounds are sketches.

Rules (Decided Oct 25, revised Oct 29):

* Ten compounds, one per unordered pair of the five base elements. A compound has no level and no tag.
* **A compound is a stat bridge (Decided Oct 29).** It reads a stat from one element's domain and writes a stat in another's, at cast time, and may carry one status. It spawns nothing: bursts, zones and strikes belong to abilities and forms (item 64). Plasma (a critting hit scales its Burn) and Superconduct (a critting hit refunds cooldown) already fit.
* **Bridge rules (proposed, item 65):** a bridge reads direct stats only, never another bridge's output (no loops); it is computed at cast time like the other cast snapshots; it has its own cap (the old +50% cap is gone); amounts are ratios of the ability's own stats where possible, not flat seconds (Superconduct's flat 0.25 s refund is about 3.5% faster casting on a single-projectile 1 s ability).
* **Delivered at the tier 1 milestone, as cards** (unchanged): two cards, "Evolve + compound" (cap 5, three elements) and "Overclock + compound" (cap 15), identical effect, generic across abilities. Form evolutions, when authored for the pair, are listed first. Whether a form arrives at tier 2 instead is open (item 66).
* **Status per compound** (Decided Oct 26, unchanged): a compound with Fire carries no status (its status is Burn); a compound without Fire carries at most one.
* **One compound per ability at tier 1;** tier 2 (up to three pairs) is not designed (item 54).
* Compounds arrive at level 3 in both elements. The first draft said soft cap 5; that was replaced.

Table (bridges marked Proposed are under review and not decided):

|Pair|Name|Mechanic|Status|State|
|-|-|-|-|-|
|Fire + Lightning|Plasma|Evolution form (Arc Bolt) today: `CRIT_DOT_SHARE` 1.0 on the evolved profile. Decided direction: a card modifier (item 57)|none (Burn)|Built (form), untuned|
|Frost + Lightning|Superconduct|Bridge: a critting hit refunds cooldown (0.25 s, cap 0.5 s per cast today; to become a fraction of the cooldown)|none|Built (Task AZ), placeholders|
|Fire + Earth|Magma|Built as an ON_HIT lava zone that re-applies Burn (to move to abilities, item 64). Proposed bridge: `REACH_BONUS` to `DOT_DAMAGE`|none (Burn)|Built as a zone (Task AJ)|
|Frost + Earth|Shatter|Built as a burst on a Chilled primary (to move). Proposed bridge: `REACH_BONUS` to a crit multiplier bonus against Chilled targets|Chill|Built as a burst (Task AI)|
|Lightning + Wind|Storm|Built as an ON_CRIT strike on the hit enemy (to move). Proposed bridge: `SPEED_BONUS` to `CRIT_CHANCE`|Shock|Built as a strike (Tasks AW, AX)|
|Frost + Wind|Blizzard|Built as a vortex zone with damaging Chill pulses (to move). Proposed bridge: `SPEED_BONUS` to `STATUS_MAGNITUDE_BONUS`|Chill|Built as a zone (Task BA)|
|Fire + Frost|Steam|Proposed: `COOLDOWN_BONUS` to `STATUS_RAMP_CAP` (helps Fire on fast abilities, item 38)|none|Sketched|
|Fire + Wind|Wildfire|Proposed: `SPEED_BONUS` to `STATUS_DURATION` (weakest fit; spreading belongs to forms)|none|Sketched|
|Lightning + Earth|(unnamed)|Proposed: `REACH_BONUS` to `CRIT_MULTIPLIER`|none|Sketched|
|Wind + Earth|Sandstorm|Proposed: `SPEED_BONUS` to `REACH_BONUS` (weakest identity; Blind is blocked)|none|Sketched|

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
* Fire is the on-switch for DoT, and the ability's `DOT_DAMAGE` says how hard it hits once on. Lightning's crit touches hit damage only. The infusions form a gradient across specializations: Fire favors DoT specialists, Lightning favors hit specialists, and Frost, Wind and Earth change delivery and favor neither. (The Oct 15 indirect damage that reached DoT was removed in Task BC.)
* Hit and DoT need one exchange rate and a split per specialization (for example 85/15, 60/40 and 25/75, placeholders). By arithmetic from the current Burn numbers, one Burn application delivers about 3.5 times its `DOT\_DAMAGE` value. None of this is in `balance\_notes.md` yet (open item 34).
* Arcane Bolt hits for `BASE\_DAMAGE` 1.0 every 1.0 s, so its base `DOT\_DAMAGE` is 0.15 (placeholder). With Burn always on, that is about 15 to 20% of its damage, a hit specialist split. A value of 1.0 would have made one Burn application worth about 3.5 hits.
* A modifier on a stat that is missing from an ability's profile has no effect, because the stat reads 0.0. Every profile therefore needs `DOT\_DAMAGE`, `STATUS\_DURATION` and `STATUS\_RAMP\_CAP`. Arcane Bolt's profile gained `STATUS\_RAMP\_CAP: 0.0` for this reason.

### Stacking of modifiers

The ledger aggregates each modifier by its type, and the stat container applies the result (formulas below). FLAT adds `value * tier`, PERCENT adds `value * tier` to one shared percent term, and MULTIPLICATIVE multiplies `(1 + value)^tier` into the product. In code, `get_modifier_totals` returns `Vector3(flat, percent, multiplicative)`.

```latex
\\text{final} = (\\text{base} + \\text{flat}) \\times (1 + \\text{percent}) \\times \\text{multiplicative}
```

```latex
\\text{multiplicative} = \\prod\_{\\text{cards}} (1 + \\text{value})^{\\text{tier}}
```

Here `value` is the card's value and `tier` is the card's duplicate count (see the glossary). The product term applies only to MULTIPLICATIVE modifiers.

* **Layers (Decided Oct 29).** Infusions are FLAT, generic stat cards are PERCENT: infusions are the foundation and generic cards amplify. A PERCENT card on a zero-base stat does nothing without the infusion.
* **MULTIPLICATIVE is unused.** No shipped card uses it (checked in the `.tres` files, Oct 29). Earlier text said card scaling is multiplicative per card; the code applies the product only to MULTIPLICATIVE modifiers.
* In the balance workbook, additive pools made hit cards the best choice for DoT builds too, and multiplicative pools passed all 6 specialization tests. That finding is therefore not reflected in the game, and it has to be re-run for the FLAT/PERCENT split (item 67). All numbers are placeholders. The model still fails the specialization test at 4 and 8 drafts, and the DoT to hit ratio drifts from 1.02 to 0.80 between 4 and 20 drafts at a fixed Fire value.
* Compound effects should be conditional or capped. A pair bonus or an evolution multiplier stacked on top of the layers would put evolved builds ahead of every other build.

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

* **Carried by cards.** Any `UpgradeDefinition` can carry a `status\_effect\_payload`, independent of its `payload\_type`. In practice only the Fire infusion card and compound cards carry one (next bullet).
* **Status sources (Decided Oct 26).** See §4, "Base infusions" rules. Fire is the only base-infusion status; every other status is carried by a compound card, none by a Fire pair, at most one by a non-Fire pair. At most one status per ability at tier 1.
* **Resolved through the ledger** with the normal scope rules (a status card needs `LOCAL\_SLOT` or `GLOBAL\_TAG\_MATCH` scope to reach abilities; infusions work through slot-specific purchases). Duplicate copies of a card add nothing, and templates are deduplicated by `effect\_id`, first in purchase order wins.
* **Chosen at cast time.** The payload's `status\_effects\_to\_apply` is filled once per cast, then applied on every hit. Application is guaranteed: there is no chance stat.
* **No DOT\_DAMAGE, no ticking status.** A status that ticks (`tick\_interval > 0`) is skipped when the ability's `dot\_damage\_snapshot` is 0, with a one-time warning per `effect\_id`. A status that does not tick (Chill) always applies.
* **STATUS\_DURATION is ability-wide.** The single snapshot lengthens every status the ability applies.
* **Magnitude (Decided Oct 27, Task AR).** `STATUS\_MAGNITUDE\_BONUS` is a second ability-wide status stat (default 0.0, effective magnitude = template magnitude times one plus the bonus, snapshotted at cast time, capped per status, placeholder +50%). Non-ticking statuses opt in (Chill does); Burn does not read it, so Burn's strength stays `DOT\_DAMAGE` and the ramp cap. A status with no scalable magnitude reads duration only.
* **Raising duration and magnitude.** Ordinary stat cards: a level-up card with `GLOBAL\_TAG\_MATCH` scope whose modifier targets `STATUS\_DURATION` or `STATUS\_MAGNITUDE\_BONUS`. A global card applies only to abilities that have ALL of its `target\_tags` (Task AR). Compound cards may also carry stat modifiers. No special draft, and no tag marks "applies a status" (item 61).
* **Duration decides (Implemented).** There is no cast-time gate. A ticking Burn gets its whole duration from `STATUS\_DURATION` (template `base\_duration` 0). `apply\_effect` returns early when the effective duration is 0 or less: no instance, no `BURNING` tag, no ticks, no warning, and an already-active Burn is left alone.
* **No status variants.** Templates stay fixed. Chill's slow scales with `STATUS\_MAGNITUDE\_BONUS`, not through a template variant. Burn's ramp cap grows with Fire levels through a per-application bonus, not a template change (Implemented).

### Effects

|Effect|Source|Behavior|Status|
|-|-|-|-|
|Burn|Fire|DoT, never stacks (the strongest application wins), sets BURNING. Tick 0.5 s, ramp +10% per second capped at +50% plus 0.1 per Fire level. Template `base\_duration` 0, so duration comes from Fire (+3.0 s per level)|Implemented|
|Chill|Shatter cards (Frost + Earth compound)|Slows the target by 30% movement speed, sets CHILLED. Base 3 s, no tick. Moved from the Frost card in Task AO. Slow scales with `STATUS\_MAGNITUDE\_BONUS`|Implemented|
|Shock|Storm cards (Lightning + Wind compound)|Non-ticking, base 3 s, sets SHOCKED. Adds a flat 0.15 to the crit chance of every hit the enemy receives, from any source, through the enemy stat `INCOMING\_CRIT\_BONUS`; scales with `STATUS\_MAGNITUDE\_BONUS`. A hit never benefits from its own Shock|Implemented (Task AX), placeholders|
|Stun|Undecided (an Earth compound without Fire)|Idea: brief stop, with an immunity window so it cannot be chained (item 60)|Idea|
|Blind|Undecided (Sandstorm)|Idea: lowers enemy accuracy; enemies do not attack yet|Idea, blocked|
|Plasma Bleed|Plasma (compound)|Burst reaction|Deferred|
|Shatter|Frost + Earth compound|Burst on a Chilled primary that spreads Chill|Implemented (Task AI)|
|Magma lava zone|Fire + Earth compound|Lingering zone that re-applies Burn|Implemented (Task AJ)|

Wind has no status. The `FROZEN` tag exists with no source.

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
|20|Chill's slow is 30% at base and scales with `STATUS\_MAGNITUDE\_BONUS` (item 58). Burn's ramp cap scales with Fire levels|Design decision|
|21|Closed (Task AK): statuses never stack, so there is no stack cap to tune (items 44 to 46 are closed with it)|Closed|
|22|Every `AbilityData` needs `structural\_tags`. Arcane Bolt now has `METAMAGIC` and `PROJECTILE`. Future abilities and evolutions still need them|Gap|
|23|When infusion drafts occur in a normal run (separate draft decided; debug panel only today)|Design decision|
|24|Pairs with neither a form nor compound cards (Steam, Wildfire, Lightning + Earth, Wind + Earth) are forced into the generic Overclock (no decline). Author more compounds or forms, or add an `@export` switch on `UpgradeManager`|Design decision|
|25|Compound designs: delivery is decided (Oct 25) and six are built (Plasma as a form, Shatter, Magma, Storm, Superconduct, Blizzard as cards). Oct 29: compounds become stat bridges (items 64, 65). Four are sketches|Design decision|
|26|Room transitions are not implemented. Missing: room completion (nothing emits `room\_completion\_confirmed`, nothing counts remaining enemies, and `EnemySpawnerComponent`'s `wave\_completed` and `campaign\_cleared` have no listeners) and a death or game-over flow (nothing handles `Entity.died`). See items 7 to 9|Gap|
|27|Projectile hitboxes and area abilities both read `AOE\_RADIUS` for their size and reach. Chain link and the projectile geometries keep `QUERY\_RADIUS` / `CHAIN\_RADIUS`. Still open: the sprite is not scaled with the hitbox, and every future area, projectile or orbit profile needs `AOE\_RADIUS`|Gap|
|28|No pierce: `CombatVolume` frees itself on every hit, and orbit shards (same class) vanish after one hit|Gap|
|29|The impact-burst mechanism is built and used by Shatter and Magma's lava zone (Tasks AI, AJ); Earth's explosion and Lightning's overload were removed (Task AU)|Built|
|31|Built (Task AL, decided Oct 26): crit is rolled per hit. Reason: a volley or chain should show a mix of crits and plain hits (future damage numbers). See CLAUDE.md "Crit"|Built|
|32|Closed (Decided Oct 29, Task BC): the indirect damage scale and its +50% cap were removed|Closed|
|33|Closed except for bursts (Decided Oct 29, Task BC): infusion effects are no longer level-gated; only `ImpactBurstDefinition.unlock_level` remains, through `LevelGate`, until bursts move to abilities (item 64)|Design decision|
|34|The damage budget, the hit/DoT split per specialization and the hit-to-DoT exchange rate are not in `balance\_notes.md`. The workbook solved Fire as an additive amount and needs re-solving for the potency model|Balance|
|35|Built (Task AK, decided Oct 26): the strongest application wins. A weaker Burn applied later no longer downgrades a stronger one (the stronger `dot\_damage`, duration bonus and ramp cap stay as a unit, and the timer is the longer). A crit-boosted Burn therefore lasts until it expires (item 48)|Built|
|37|Every ability profile needs nonzero `BASE\_DAMAGE` and `DOT\_DAMAGE`, plus `STATUS\_DURATION` and `STATUS\_RAMP\_CAP` entries (a missing stat ignores modifiers). Only Arcane Bolt's profile has them (`DOT\_DAMAGE` 0.15, placeholder). A headless warning for zeros was offered, not requested|Gap|
|38|Fire's duration does little for fast abilities, by arithmetic from the numbers: Arcane Bolt's cooldown is 1.0 s and Burn lasts 3.0 s at level 1, so a re-apply keeps it up, and the ramp keeps running because a refresh keeps `elapsed`. The ramp cap and Frost's cooldown cuts matter more there. Duration matters for slow abilities and after target changes|Balance|
|39|Per-hit or per-cast bursts. Built (Task AB): `max_per_cast` on each burst definition (0 = unlimited), enforced through a per-cast budget shared by the cast's payload copies. The first caps are set (placeholders): Shatter 2 per cast, Magma's lava zone 1 per cast|Built|
|40|Closed (Task AU): the Earth explosion and Lightning overload were removed|Design decision|
|41|Statuses on bursts are filtered by `carried\_status\_tags` (Task AH): Shatter carries Chill and Magma's zone carries Burn. Revisit spam on chains and fans (a status never stacks, but each hit re-applies it) before authoring more|Design decision|
|42|Closed (Task AU): the Earth explosion and Lightning overload were removed|Design decision|
|43|A shaped burst's visual is spawned only when it catches at least one enemy; an effect-only burst (no shape) always spawns its effect (Task U). Confirm the shaped rule is wanted, and add visuals for Earth and Lightning|Design decision|
|44|Closed (Task AK): there are no stack cards|Closed|
|45|Closed (Task AK): there are no stack caps to tune|Closed|
|46|Closed (Task AK): statuses never stack. Several sources share one instance and the strongest application wins|Closed|
|47|With indirect damage gone, Wind's value is delivery speed only, and the instant geometries (pulse, sweep, vortex) have no speed concept. Open: add a base delay to them. Wind also scales chain and fissure step delays (Task Z)|Design decision|
|48|Plasma numbers are placeholders. Crit is rolled per hit (Task AL): at Lightning 3 the chance is 14% and the multiplier 1.95. Because the strongest application wins (Task AK), one critting hit puts a crit-strength Burn on its target that later plain hits cannot lower, so the average Burn bonus is higher than the per-hit +13% (Lightning 3) or +25% (Lightning 5). Needs retuning. Lightning's level 3 crit-chance bonus now also raises Burn through the shared damage scale, on top of `CRIT\_DOT\_SHARE`; include that in the retune.|Balance|
|49|Lightning's crit chance and multiplier ship on the infusion card as FLAT (+0.03 and +0.15 per level, placeholders; the workbook used +0.05 and +0.15). Open: whether the multiplier stays on the infusion, and how generic crit cards look (PERCENT). The workbook's hit-build numbers need re-running|Design decision|
|50|Every shape query returns at most 32 enemies (`MAX\_QUERY\_RESULTS`), so an area or chain hits only the 32 nearest in a crowd larger than that. Decide whether the limit should be higher before swarms are designed|Balance|
|51|Closed (Task AU): the Earth explosion and Lightning overload were removed|Design decision|
|52|Decided (Oct 25, Tasks AI and AJ): compounds are cards, offered at the tier 1 milestone as "Evolve + compound" and "Overclock + compound" with an identical effect, generic across abilities. Plasma stays an evolution form (item 57)|Built|
|53|Closed (Task AH): `ImpactBurstDefinition.carried\_status\_tags` replaces the `applies\_statuses` switch. A burst carries a cast status only if one of its granted tags is listed; an empty list carries none|Built|
|54|Compound stacking. A tier 1 ability has exactly two elements, so one compound. Tier 2 allows three elements (up to three pairs); how bridges and statuses combine there is not designed (status cap per ability, whether bridges stack)|Open|
|55|Closed: the enemy that triggers a burst does not take the burst's damage. It is excluded by its hurtbox id (`SpatialQuery.filter\_enemy\_hurtboxes`), and a logic check covers it. Exception (Task AW): a burst definition with `hits\_primary` hits only the triggering enemy (Storm's strike)|Closed|
|56|Closed (Task AI): a CHILLED tag exists. Compound cards are offered through `compound\_pair` and `UpgradeManager.get\_compound\_pair` (tier 1, exactly two elements, both at level 3), not through `evolves\_from` and recipes, so a recipe never has to express a level|Built|
|57|Plasma is an evolution form today. Decided direction (Oct 29): it becomes a normal compound card whose `CRIT_DOT_SHARE` is a card modifier, so an Overclock + Plasma pick keeps the effect and Arc Bolt stays the Arcane Bolt form. Not built|Design decision|
|58|Closed (Decided Oct 27, Task AR): status strength comes from two ability-wide stats, `STATUS\_DURATION` and `STATUS\_MAGNITUDE\_BONUS` (non-ticking statuses only; Burn keeps `DOT\_DAMAGE`), raised by ordinary global stat cards and optionally by compound cards|Closed|
|59|Closed (Decided Oct 27, Task AX): Shock carries a flat modifier on the enemy-side stat `INCOMING\_CRIT\_BONUS`, which `resolve\_hit\_crit` adds to the crit chance of every hit the enemy receives; it scales with `STATUS\_MAGNITUDE\_BONUS` and applies to every source|Closed|
|60|Per-status re-apply and anti-lock rules (for example a Stun immunity window), and whether statuses may consume or amplify each other (today they only grant tags that conditions read)|Design decision|
|61|No tag says an ability applies a status. Element-gated stat cards (`GLOBAL_TAG_MATCH` with the element tag) handle theme stats; a duration or magnitude card can still be dead on an ability whose only status is Burn|Design decision|
|62|Closed (Task BC): the +50% cap on summed indirect bonuses was removed with the indirect scalings|Closed|
|63|Storm placeholders and open edges: strike 0.5 of the crit hit, 4 per cast; Shock +0.15 for 3 s. The strike is to move to abilities (item 64); Shock stays on the card. Shock raising every source's crit chance makes it a party-wide debuff; revisit if it overshadows other builds|Design decision|
|64|Spawn ownership (Decided Oct 29, not built): bursts, zones and strikes belong to abilities and their forms, not to compound cards, so two abilities never carry two versions of one compound effect. Rework scope: Shatter, Magma, Storm, Blizzard, their cards, the ledger's burst resolution, tests|Design decision|
|65|The ten stat bridges are proposed (see §4) and under review before any build. Open: ratios and caps, double-dipping with direct stats, Wildfire and Sandstorm identities, a CHILLED condition for Shatter's bridge|Design decision|
|66|Timing of forms: compound at the tier 1 milestone and form at tier 2 (proposed), or the form at tier 1. Open. Depends on the Overclock path (it blocks evolution, so the deep path never gets a form), run length, and item 54|Design decision|
|67|Layers: infusions FLAT, generic cards PERCENT, MULTIPLICATIVE unused. The workbook (multiplicative pools) must be re-run for this split before the hit/DoT balance is trusted|Balance|
|68|Retune after Task BC: removing indirect damage lowers tier 1 damage by roughly a quarter to a third (placeholder estimate), and Frost's formula changed. Level-up stat cards for theme and damage stats do not exist yet, so the pool is nearly empty|Balance|



