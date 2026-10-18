extends Node
## GOLDEN (CHARACTERIZATION) CHECKS.
##
## These record what the code computes TODAY, so a later refactor can be shown to preserve it. They are
## NOT claims that the numbers are correct or balanced.
##
## - Do NOT regenerate golden_values.json in a refactor task to make a failure go away. A failure means
##   the refactor changed behavior.
## - Regenerate only when a design change is intended, and say so in the report.
## - Regeneration is off by default. It runs only with the environment variable GOLDEN_UPDATE=1.
##
## Run (from the project root):
##   LOGIC_TEST=res://tools/headless/golden_test.gd $GODOT --headless --path . -s res://tools/headless/runner.gd
## Regenerate (intended design changes only):
##   GOLDEN_UPDATE=1 LOGIC_TEST=res://tools/headless/golden_test.gd $GODOT --headless --path . -s res://tools/headless/runner.gd
##
## Everything is deterministic: crit is forced on or off through CRIT_CHANCE (1.0 or 0.0), and every
## scenario builds its own fixture. Floats compare with a tolerance of 1e-6.

const Fixtures = preload("res://tools/headless/fixtures.gd")

const GOLDEN_PATH := "res://tools/headless/golden/golden_values.json"
const TOLERANCE := 0.000001

const ARCANE_PROFILE := "res://resources/abilities/arcane_bolt/arcane_bolt_stats.tres"
const PLAYER_PROFILE := "res://resources/entities/player/player_stats.tres"
const CORE_CARD := "res://resources/entities/player/player_move_speed_upgrade_def.tres"
const FIRE := "res://resources/infusions/inf_fire_upgrade_def.tres"
const FROST := "res://resources/infusions/inf_frost_upgrade_def.tres"
const LIGHTNING := "res://resources/infusions/inf_lightning_upgrade_def.tres"
const WIND := "res://resources/infusions/inf_wind_upgrade_def.tres"
const EARTH := "res://resources/infusions/inf_earth_upgrade_def.tres"
const OVERCLOCK_CARD := "res://resources/infusions/overclock_upgrade_def.tres"
const UNLOCK_CARD := "res://resources/abilities/arcane_bolt/arcane_bolt_upgrade_def.tres"

var fails: int = 0
var tree: SceneTree
var world: Node
var fx: Fixtures
var computed: Dictionary = {}
var _recorded_hits: Array[int] = []


func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS  ", msg)
	else:
		fails += 1
		print("FAIL  ", msg)


func run(scene_tree: SceneTree, world_node: Node) -> int:
	tree = scene_tree
	world = world_node
	fx = Fixtures.new(tree, world)

	var sections: Array[Callable] = [
		_section_stat_totals,
		_section_transient_modifiers,
		_section_payload_snapshots,
		_section_card_resolution,
		_section_damage_received,
		_section_card_stat_paths,
		_section_card_actions,
		_section_draft_pool,
		_section_evolution_offer,
		_section_infusion_pool,
		_section_tag_card_draft,
	]
	for section in sections:
		fx.begin_section()
		await section.call()
		fx.end_section()

	if OS.get_environment("GOLDEN_UPDATE") == "1":
		_write_golden()
		print("GOLDEN regenerated: %d scenarios, %d values -> %s" % [computed.size(), _count_values(), GOLDEN_PATH])
		return 0

	_compare_with_golden()
	print("GOLDEN done: %d scenarios, %d values, fails=%d" % [computed.size(), _count_values(), fails])
	return 1 if fails > 0 else 0


# ---------------------------------------------------------------------------------------------
# Comparison and regeneration
# ---------------------------------------------------------------------------------------------

func _count_values() -> int:
	var total := 0
	for scenario in computed:
		total += (computed[scenario] as Dictionary).size()
	return total


func _write_golden() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GOLDEN_PATH).get_base_dir())
	var file := FileAccess.open(GOLDEN_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(computed, "\t", true) + "\n")
	file.close()


func _compare_with_golden() -> void:
	if not FileAccess.file_exists(GOLDEN_PATH):
		check(false, "golden: %s is missing (run with GOLDEN_UPDATE=1 once)" % GOLDEN_PATH)
		return
	var expected = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN_PATH))
	if not (expected is Dictionary):
		check(false, "golden: %s is not a JSON object" % GOLDEN_PATH)
		return

	for scenario in computed:
		var actual: Dictionary = computed[scenario]
		var wanted = expected.get(scenario)
		if not (wanted is Dictionary):
			check(false, "golden %s: scenario missing from the golden file" % scenario)
			continue
		var differences: Array[String] = []
		for key in actual:
			if not wanted.has(key):
				differences.append("%s: not in golden" % key)
			elif not _values_match(actual[key], wanted[key]):
				differences.append("%s: now %s, golden %s" % [key, str(actual[key]), str(wanted[key])])
		for key in wanted:
			if not actual.has(key):
				differences.append("%s: in golden but no longer computed" % key)
		check(differences.is_empty(), "golden %s (%d values)%s" % [scenario, actual.size(), "" if differences.is_empty() else " -> " + "; ".join(differences)])
	for scenario in expected:
		if not computed.has(scenario):
			check(false, "golden %s: in the golden file but no longer computed" % scenario)


func _values_match(a: Variant, b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		return absf(float(a) - float(b)) <= TOLERANCE
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in range(a.size()):
			if not _values_match(a[i], b[i]):
				return false
		return true
	return a == b


# ---------------------------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------------------------

## An ability lane: a stats container wired to `ledger` in `slot`, with its own tag component.
## `crit_chance` >= 0 overrides the profile's CRIT_CHANCE so a cast is deterministic.
func _lane(slot: int, base_tags: Array[Tags.Type], ledger: RunLedgerComponent, profile_path: String = ARCANE_PROFILE, crit_chance: float = -1.0) -> Dictionary:
	var tag_component := TagComponent.new()
	fx.track(tag_component)
	tag_component.set_base_tags(base_tags)
	tag_component.configure_slot_context(slot, ledger)
	var stats := StatsContainer.new()
	fx.track(stats)
	stats.configure_slot_context(slot, ledger, tag_component)
	var profile := load(profile_path) as StatsProfile
	if crit_chance >= 0.0:
		var overridden := StatsProfile.new()
		var values: Dictionary[Stat.Type, float] = {}
		for stat_type in profile.base_stats:
			values[stat_type] = profile.base_stats[stat_type]
		values[Stat.Type.CRIT_CHANCE] = crit_chance
		overridden.base_stats = values
		profile = overridden
	stats.initialize_profile(profile)
	return {"stats": stats, "tags": tag_component}


func _arcane_tags() -> Array[Tags.Type]:
	var tags: Array[Tags.Type] = [Tags.Type.METAMAGIC, Tags.Type.PROJECTILE]
	return tags


func _no_tags() -> Array[Tags.Type]:
	var tags: Array[Tags.Type] = []
	return tags


func _new_ledger() -> RunLedgerComponent:
	var ledger := RunLedgerComponent.new()
	fx.track(ledger)
	return ledger


func _buy(ledger: RunLedgerComponent, card_path: String, slot: int, count: int) -> void:
	var card := load(card_path) as UpgradeDefinition
	for i in range(count):
		ledger.log_slot_specific_purchase(card, slot)


## Final value of every stat in the container's profile, keyed by stat name.
func _all_stats(stats: StatsContainer) -> Dictionary:
	var out := {}
	var keys := stats.stats.keys()
	keys.sort()
	for key in keys:
		out[Stat.Type.keys()[key]] = stats.get_final_stat_value(key)
	return out


func _prefixed(prefix: String, values: Dictionary) -> Dictionary:
	var out := {}
	for key in values:
		out["%s/%s" % [prefix, key]] = values[key]
	return out


func _card(id: String, scope: UpgradeDefinition.ScopeType, restrict_to_slot: int = 0) -> UpgradeDefinition:
	var card := UpgradeDefinition.new()
	card.upgrade_id = id
	card.scope = scope
	card.restrict_to_slot = restrict_to_slot
	return card


func _burst(id: StringName, trigger: ImpactBurstDefinition.Trigger, fraction: float, radius_multiplier: float = 1.0) -> ImpactBurstDefinition:
	var definition := ImpactBurstDefinition.new()
	definition.burst_id = id
	definition.trigger = trigger
	definition.damage_fraction = fraction
	var shape := CircleBurstShape.new()
	shape.radius_multiplier = radius_multiplier
	definition.shape = shape
	return definition


func _status(id: String, base_duration: float) -> StatusEffect:
	var effect := StatusEffect.new()
	effect.effect_id = id
	effect.base_duration = base_duration
	return effect


func _lost(bat: Enemy) -> float:
	return 1000.0 - bat.health_component.current_health


func _count_hit(_payload: CombatPayload, index: int) -> void:
	_recorded_hits[index] += 1


# ---------------------------------------------------------------------------------------------
# 1. Stat totals
# ---------------------------------------------------------------------------------------------

func _section_stat_totals() -> void:
	var loadouts: Array = [
		["none", []],
		["fire_1", [[FIRE, 1]]], ["fire_2", [[FIRE, 2]]], ["fire_3", [[FIRE, 3]]],
		["frost_1", [[FROST, 1]]], ["frost_2", [[FROST, 2]]], ["frost_3", [[FROST, 3]]],
		["lightning_1", [[LIGHTNING, 1]]], ["lightning_2", [[LIGHTNING, 2]]], ["lightning_3", [[LIGHTNING, 3]]],
		["wind_1", [[WIND, 1]]], ["wind_2", [[WIND, 2]]], ["wind_3", [[WIND, 3]]],
		["earth_1", [[EARTH, 1]]], ["earth_2", [[EARTH, 2]]], ["earth_3", [[EARTH, 3]]],
		["fire_3_earth_3", [[FIRE, 3], [EARTH, 3]]],
		["frost_2_lightning_2", [[FROST, 2], [LIGHTNING, 2]]],
		["wind_1_earth_1", [[WIND, 1], [EARTH, 1]]],
		["fire_15_overclocked", [[FIRE, 15]]],
	]
	for loadout in loadouts:
		var ledger := _new_ledger()
		for purchase in loadout[1]:
			_buy(ledger, purchase[0], 1, purchase[1])
		var lane := _lane(1, _arcane_tags(), ledger)
		computed["stats/arcane_bolt/%s" % loadout[0]] = _all_stats(lane["stats"])

	# Character Core (slot 0): MAX_HEALTH and MOVEMENT_SPEED, without and with the core upgrade card
	var core_ledger := _new_ledger()
	var core := _lane(0, _no_tags(), core_ledger, PLAYER_PROFILE)
	computed["stats/core/no_upgrade"] = _all_stats(core["stats"])
	core_ledger.log_purchase(load(CORE_CARD) as UpgradeDefinition)
	computed["stats/core/move_speed_card"] = _all_stats(core["stats"])
	core_ledger.log_purchase(load(CORE_CARD) as UpgradeDefinition)
	computed["stats/core/move_speed_card_x2"] = _all_stats(core["stats"])


# ---------------------------------------------------------------------------------------------
# 2. Transient modifiers (the second pass in Stat)
# ---------------------------------------------------------------------------------------------

func _add_modifier(stats: StatsContainer, id: String, type: StatModifier.Type, value: float, stat: Stat.Type) -> StatModifier:
	var modifier := StatModifier.new()
	modifier.id = id
	modifier.type = type
	modifier.value = value
	modifier.target_stat_type = stat
	stats.add_modifier(modifier)
	return modifier


func _section_transient_modifiers() -> void:
	var chill := load("res://resources/status_effects/chill.tres") as StatusEffect
	var burn := load("res://resources/status_effects/burn.tres") as StatusEffect

	# Real Chill and Burn on the Character Core lane (Chill changes MOVEMENT_SPEED, Burn changes no stat)
	for with_card in [false, true]:
		var ledger := _new_ledger()
		if with_card:
			ledger.log_purchase(load(CORE_CARD) as UpgradeDefinition)
		var core := _lane(0, _no_tags(), ledger, PLAYER_PROFILE)
		var suffix := "move_speed_card" if with_card else "no_upgrade"
		var chill_instance := StatusEffectInstance.new(chill, 1)
		for modifier in chill_instance.runtime_modifiers:
			core["stats"].add_modifier(modifier)
		computed["transient/core_%s/chill_active" % suffix] = _all_stats(core["stats"])
		for modifier in chill_instance.runtime_modifiers:
			core["stats"].remove_modifier(modifier)
		var burn_instance := StatusEffectInstance.new(burn, 2)
		for modifier in burn_instance.runtime_modifiers:
			core["stats"].add_modifier(modifier)
		computed["transient/core_%s/burn_active" % suffix] = _all_stats(core["stats"])

	# Synthetic flat, percent and multiplicative modifiers on top of Frost level 2 (ledger pass + transient pass)
	var cases: Array = [
		["flat", [[StatModifier.Type.FLAT, 0.5]]],
		["percent", [[StatModifier.Type.PERCENT, -0.25]]],
		["multiplicative", [[StatModifier.Type.MULTIPLICATIVE, 0.1]]],
		["all_three", [[StatModifier.Type.FLAT, 0.5], [StatModifier.Type.PERCENT, -0.25], [StatModifier.Type.MULTIPLICATIVE, 0.1]]],
	]
	for case in cases:
		var ledger := _new_ledger()
		_buy(ledger, FROST, 1, 2)
		var lane := _lane(1, _arcane_tags(), ledger)
		var index := 0
		for entry in case[1]:
			_add_modifier(lane["stats"], "golden#%d" % index, entry[0], entry[1], Stat.Type.COOLDOWN)
			index += 1
		computed["transient/arcane_frost_2/%s" % case[0]] = _all_stats(lane["stats"])


# ---------------------------------------------------------------------------------------------
# 3. Payload snapshots from generate_hit_payload
# ---------------------------------------------------------------------------------------------

func _payload_values(payload: CombatPayload) -> Dictionary:
	var status_ids: Array = []
	for effect in payload.status_effects_to_apply:
		status_ids.append(effect.effect_id)
	var burst_ids: Array = []
	for burst in payload.impact_bursts:
		burst_ids.append(String(burst.burst_id))
	return {
		"final_damage": payload.final_damage,
		"dot_damage_snapshot": payload.dot_damage_snapshot,
		"status_duration_snapshot": payload.status_duration_snapshot,
		"status_ramp_cap_snapshot": payload.status_ramp_cap_snapshot,
		"status_ids": status_ids,
		"burst_ids": burst_ids,
		"is_critical_hit": payload.is_critical_hit,
		"is_burst": payload.is_burst,
	}


func _section_payload_snapshots() -> void:
	var burst_card := _card("golden_burst_card", UpgradeDefinition.ScopeType.LOCAL_SLOT, 1)
	burst_card.impact_burst_payload = _burst(&"golden_burst", ImpactBurstDefinition.Trigger.ON_HIT, 0.5)
	var loadouts: Array = [
		["none", [], false],
		["fire_1", [[FIRE, 1]], false],
		["fire_3", [[FIRE, 3]], false],
		["frost_2", [[FROST, 2]], false],
		["fire_2_frost_2", [[FIRE, 2], [FROST, 2]], false],
		["fire_15_overclocked", [[FIRE, 15]], false],
		["burst_card_only", [], true],
		["fire_3_burst_card", [[FIRE, 3]], true],
	]
	for loadout in loadouts:
		for crit in [true, false]:
			var ledger := _new_ledger()
			for purchase in loadout[1]:
				_buy(ledger, purchase[0], 1, purchase[1])
			if loadout[2]:
				ledger.log_purchase(burst_card)
			var lane := _lane(1, _arcane_tags(), ledger, ARCANE_PROFILE, 1.0 if crit else 0.0)
			var payload := CombatCalculations.generate_hit_payload(world as Node2D, lane["stats"], lane["tags"])
			computed["payload/%s/crit_%s" % [loadout[0], "on" if crit else "off"]] = _payload_values(payload)


# ---------------------------------------------------------------------------------------------
# 4. Card resolution (statuses and bursts per slot)
# ---------------------------------------------------------------------------------------------

func _resolved(ledger: RunLedgerComponent) -> Dictionary:
	var slot_tags: Dictionary = {0: _no_tags(), 1: _arcane_tags(), 2: _aoe_tags()}
	var out := {}
	for slot in [0, 1, 2]:
		var statuses: Array = []
		for effect in ledger.get_status_effects(slot, slot_tags[slot]):
			statuses.append("%s:%.1f" % [effect.effect_id, effect.base_duration])
		var bursts: Array = []
		for burst in ledger.get_impact_bursts(slot, slot_tags[slot]):
			bursts.append("%s:%.1f" % [String(burst.burst_id), burst.damage_fraction])
		out["slot_%d/statuses" % slot] = statuses
		out["slot_%d/bursts" % slot] = bursts
	return out


func _aoe_tags() -> Array[Tags.Type]:
	var tags: Array[Tags.Type] = [Tags.Type.AOE]
	return tags


func _section_card_resolution() -> void:
	var fire := load(FIRE) as UpgradeDefinition

	# Duplicate copies of an infusion add nothing
	var ledger := _new_ledger()
	_buy(ledger, FIRE, 1, 3)
	computed["cards/fire_bought_3_times_slot_1"] = _resolved(ledger)

	# The same infusion for two different slots
	ledger = _new_ledger()
	_buy(ledger, FIRE, 1, 1)
	_buy(ledger, FIRE, 2, 1)
	computed["cards/fire_slot_1_and_slot_2"] = _resolved(ledger)

	# A slot-specific purchase plus a plain purchase of the same id (the card's own scope is LOCAL_SLOT, restrict slot 0)
	ledger = _new_ledger()
	_buy(ledger, FIRE, 1, 1)
	ledger.log_purchase(fire)
	computed["cards/fire_slot_1_plus_plain"] = _resolved(ledger)

	# A plain purchase alone
	ledger = _new_ledger()
	ledger.log_purchase(fire)
	computed["cards/fire_plain_only"] = _resolved(ledger)

	# Two different cards carry a status and a burst with the same ids: first in purchase order wins
	for order in ["a_then_b", "b_then_a"]:
		var card_a := _card("golden_dup_a", UpgradeDefinition.ScopeType.LOCAL_SLOT, 1)
		card_a.status_effect_payload = _status("golden_dup", 1.0)
		card_a.impact_burst_payload = _burst(&"golden_dup", ImpactBurstDefinition.Trigger.ON_HIT, 0.3)
		var card_b := _card("golden_dup_b", UpgradeDefinition.ScopeType.LOCAL_SLOT, 1)
		card_b.status_effect_payload = _status("golden_dup", 2.0)
		card_b.impact_burst_payload = _burst(&"golden_dup", ImpactBurstDefinition.Trigger.ON_CRIT, 0.6)
		ledger = _new_ledger()
		if order == "a_then_b":
			ledger.log_purchase(card_a)
			ledger.log_purchase(card_b)
		else:
			ledger.log_purchase(card_b)
			ledger.log_purchase(card_a)
		computed["cards/duplicate_ids_%s" % order] = _resolved(ledger)

	# Tag-scoped card: applies to slots whose tags include PROJECTILE, not to others
	var tag_card := _card("golden_tag_card", UpgradeDefinition.ScopeType.GLOBAL_TAG_MATCH)
	tag_card.target_tags = [Tags.Type.PROJECTILE]
	tag_card.status_effect_payload = _status("golden_tagged", 1.0)
	tag_card.impact_burst_payload = _burst(&"golden_tagged", ImpactBurstDefinition.Trigger.ON_HIT, 0.4)
	ledger = _new_ledger()
	ledger.log_purchase(tag_card)
	computed["cards/global_tag_match_projectile"] = _resolved(ledger)

	# Core-scoped card (the default scope) resolves for slot 0 only
	var core_card := _card("golden_core_card", UpgradeDefinition.ScopeType.CHARACTER_CORE)
	core_card.status_effect_payload = _status("golden_core", 1.0)
	ledger = _new_ledger()
	ledger.log_purchase(core_card)
	computed["cards/character_core_scope"] = _resolved(ledger)

	# A card bought for slot 2 only, through a LOCAL_SLOT restriction
	var slot_two_card := _card("golden_slot_two", UpgradeDefinition.ScopeType.LOCAL_SLOT, 2)
	slot_two_card.impact_burst_payload = _burst(&"golden_slot_two", ImpactBurstDefinition.Trigger.ON_HIT, 0.7)
	ledger = _new_ledger()
	ledger.log_purchase(slot_two_card)
	computed["cards/local_slot_restricted_to_2"] = _resolved(ledger)


# ---------------------------------------------------------------------------------------------
# 5. Damage received
# ---------------------------------------------------------------------------------------------

func _spawn_bats(origin: Vector2, offsets: Array[Vector2]) -> Array[Enemy]:
	_recorded_hits.clear()
	var bats: Array[Enemy] = []
	for i in range(offsets.size()):
		var bat := fx.spawn_bat()
		bat.set_physics_process(false)
		bat.health_component.update_max_health(1000.0, true)
		bat.health_component.set_to_full()
		bat.global_position = origin + offsets[i]
		_recorded_hits.append(0)
		bat.hurtbox_component.hit_received.connect(_count_hit.bind(i))
		bats.append(bat)
	await tree.physics_frame
	await tree.physics_frame
	return bats


func _section_damage_received() -> void:
	var burn := load("res://resources/status_effects/burn.tres") as StatusEffect

	# A normal hit and a forced crit hit (Arcane Bolt BASE_DAMAGE 1.0, CRIT_MULTIPLIER 1.5)
	for crit in [false, true]:
		var lane := _lane(1, _arcane_tags(), _new_ledger(), ARCANE_PROFILE, 1.0 if crit else 0.0)
		var payload := CombatCalculations.generate_hit_payload(world as Node2D, lane["stats"], lane["tags"])
		var bats := await _spawn_bats(Vector2(70000.0, 70000.0 + (1000.0 if crit else 0.0)), [Vector2.ZERO])
		bats[0].hurtbox_component.take_hit(payload)
		computed["damage/hit_%s" % ("crit" if crit else "normal")] = {"health_lost": _lost(bats[0])}
		bats[0].queue_free()

	# Burn from a Fire level 3 cast, advanced in fixed 0.5 s steps
	var ledger := _new_ledger()
	_buy(ledger, FIRE, 1, 3)
	var burn_lane := _lane(1, _arcane_tags(), ledger, ARCANE_PROFILE, 0.0)
	var burn_payload := CombatCalculations.generate_hit_payload(world as Node2D, burn_lane["stats"], burn_lane["tags"])
	var burn_bats := await _spawn_bats(Vector2(70000.0, 72000.0), [Vector2.ZERO])
	var burn_bat := burn_bats[0]
	burn_bat.status_effect_component.apply_effect(burn, burn_payload.dot_damage_snapshot, burn_payload.status_duration_snapshot, burn_payload.status_ramp_cap_snapshot)
	var burn_values := {}
	for step in range(1, 19):
		burn_bat.status_effect_component._process(0.5)
		if step in [2, 6, 10, 18]:
			burn_values["health_lost_after_%.1f_s" % (step * 0.5)] = _lost(burn_bat)
	burn_values["burn_still_active"] = not burn_bat.status_effect_component._active_effects.is_empty()
	computed["damage/burn_fire_3"] = burn_values
	burn_bat.queue_free()

	# ON_HIT burst: the neighbor's damage (and the primary's)
	var hit_values := await _burst_damage(Vector2(70000.0, 74000.0), ImpactBurstDefinition.Trigger.ON_HIT, 0.0)
	computed["damage/on_hit_burst_normal_hit"] = hit_values
	var hit_crit_values := await _burst_damage(Vector2(70000.0, 75000.0), ImpactBurstDefinition.Trigger.ON_HIT, 1.0)
	computed["damage/on_hit_burst_crit_hit"] = hit_crit_values

	# ON_CRIT burst with a forced crit and with a forced non-crit
	var crit_burst_values := await _burst_damage(Vector2(70000.0, 76000.0), ImpactBurstDefinition.Trigger.ON_CRIT, 1.0)
	computed["damage/on_crit_burst_crit_hit"] = crit_burst_values
	var crit_burst_off_values := await _burst_damage(Vector2(70000.0, 77000.0), ImpactBurstDefinition.Trigger.ON_CRIT, 0.0)
	computed["damage/on_crit_burst_normal_hit"] = crit_burst_off_values


## A cast from an Arcane Bolt lane carrying one burst card; reports the primary's and the neighbor's health lost.
func _burst_damage(origin: Vector2, trigger: ImpactBurstDefinition.Trigger, crit_chance: float) -> Dictionary:
	var card := _card("golden_damage_burst", UpgradeDefinition.ScopeType.LOCAL_SLOT, 1)
	card.impact_burst_payload = _burst(&"golden_damage_burst", trigger, 0.5, 4.0)
	var ledger := _new_ledger()
	ledger.log_purchase(card)
	var lane := _lane(1, _arcane_tags(), ledger, ARCANE_PROFILE, crit_chance)
	var payload := CombatCalculations.generate_hit_payload(world as Node2D, lane["stats"], lane["tags"])
	var bats := await _spawn_bats(origin, [Vector2.ZERO, Vector2(30, 0)])
	bats[0].hurtbox_component.take_hit(payload)
	await tree.process_frame
	await tree.process_frame
	var values := {
		"payload_final_damage": payload.final_damage,
		"payload_is_critical_hit": payload.is_critical_hit,
		"primary_health_lost": _lost(bats[0]),
		"neighbor_health_lost": _lost(bats[1]),
		"primary_hits": _recorded_hits[0],
		"neighbor_hits": _recorded_hits[1],
	}
	for bat in bats:
		bat.queue_free()
	return values


# ---------------------------------------------------------------------------------------------
# 6. Card paths added before the card-effects refactor (Task L2). Test-only cards are built in code,
#    their ids start with "test_", and none is ever saved as a resource.
# ---------------------------------------------------------------------------------------------

func _modifier(type: StatModifier.Type, value: float, stat: Stat.Type) -> StatModifier:
	var modifier := StatModifier.new()
	modifier.type = type
	modifier.value = value
	modifier.target_stat_type = stat
	return modifier


func _stat_card(id: String, scope: UpgradeDefinition.ScopeType, restrict_to_slot: int, modifier: StatModifier) -> UpgradeDefinition:
	var card := _card(id, scope, restrict_to_slot)
	card.payload_type = UpgradeDefinition.PayloadType.STAT_MODIFIER
	if modifier != null:
		card.stat_modifiers = [modifier]
	return card


## The ledger's Vector3(flat, percent, multiplicative) for one stat, as three numbers.
func _totals(ledger: RunLedgerComponent, slot: int, tags: Array[Tags.Type], stat: Stat.Type) -> Array:
	var totals := ledger.get_modifier_totals(slot, tags, stat)
	return [totals.x, totals.y, totals.z]


func _choice(definition: UpgradeDefinition, slot: int, max_tiers: int = 1) -> UpgradeChoice:
	var tracker := UpgradeTracker.new()
	tracker.definition = definition
	tracker.max_purchases = max_tiers
	var choice := UpgradeChoice.new()
	choice.source_tracker = tracker
	choice.target_slot_index = slot
	return choice


## Mounts a copy of Arcane Bolt's AbilityData in `slot` (optionally with other structural tags).
func _mount(player: Player, slot: int, tags: Array[Tags.Type] = []) -> Ability:
	var data := (load(Fixtures.ARCANE_BOLT_DATA) as AbilityData).duplicate() as AbilityData
	data.slot_index = slot as AbilityData.Role
	if not tags.is_empty():
		data.structural_tags = tags
	return player.ability_container.add_ability_from_data(data)


func _tag_ints(tags: Array[Tags.Type]) -> Array:
	var out: Array = []
	for tag in tags:
		out.append(int(tag))
	return out


func _stat_name(stat: Stat.Type) -> String:
	return Stat.Type.keys()[stat]


func _section_card_stat_paths() -> void:
	var damage := Stat.Type.BASE_DAMAGE

	# 1. A ledger MULTIPLICATIVE stat card, bought 1, 2 and 3 times: (1 + v)^tier. Plain and slot-specific purchases.
	for purchase_kind in ["plain", "slot_specific"]:
		var card := _stat_card("test_multiplicative", UpgradeDefinition.ScopeType.LOCAL_SLOT, 1, _modifier(StatModifier.Type.MULTIPLICATIVE, 0.1, damage))
		var ledger := _new_ledger()
		var lane := _lane(1, _arcane_tags(), ledger)
		var values := {"base": lane["stats"].get_final_stat_value(damage)}
		for tier in [1, 2, 3]:
			if purchase_kind == "plain":
				ledger.log_purchase(card)
			else:
				ledger.log_slot_specific_purchase(card, 1)
			var totals := _totals(ledger, 1, _arcane_tags(), damage)
			values["tier_%d/total_flat" % tier] = totals[0]
			values["tier_%d/total_percent" % tier] = totals[1]
			values["tier_%d/total_multiplicative" % tier] = totals[2]
			values["tier_%d/final" % tier] = lane["stats"].get_final_stat_value(damage)
		var other := _totals(ledger, 2, _arcane_tags(), damage)
		values["slot_2_tier_3/total_multiplicative"] = other[2]
		computed["cards/multiplicative_%s" % purchase_kind] = values

	# 3. A LOCAL_SLOT stat card (restrict_to_slot 1, PERCENT 0.5 on projectile speed): slot 1 only, tiers 1 and 2.
	var speed := Stat.Type.PROJECTILE_MOVEMENT_SPEED
	var local_card := _stat_card("test_local_speed", UpgradeDefinition.ScopeType.LOCAL_SLOT, 1, _modifier(StatModifier.Type.PERCENT, 0.5, speed))
	var local_ledger := _new_ledger()
	var lane_one := _lane(1, _arcane_tags(), local_ledger)
	var lane_two := _lane(2, _arcane_tags(), local_ledger)
	var local_values := {
		"tier_0/slot_1": lane_one["stats"].get_final_stat_value(speed),
		"tier_0/slot_2": lane_two["stats"].get_final_stat_value(speed),
	}
	for tier in [1, 2]:
		local_ledger.log_purchase(local_card)
		local_values["tier_%d/slot_1" % tier] = lane_one["stats"].get_final_stat_value(speed)
		local_values["tier_%d/slot_2" % tier] = lane_two["stats"].get_final_stat_value(speed)
		local_values["tier_%d/slot_1_total_percent" % tier] = _totals(local_ledger, 1, _arcane_tags(), speed)[1]
		local_values["tier_%d/slot_2_total_percent" % tier] = _totals(local_ledger, 2, _arcane_tags(), speed)[1]
	computed["cards/local_slot_stat_card"] = local_values

	# 4. A card with several modifiers: contribution at tier 0, at tier 2, with a mismatched stat, and a second card with one modifier on a stat the first also targets.
	var extras_card := _stat_card("test_extras", UpgradeDefinition.ScopeType.LOCAL_SLOT, 1, null)
	extras_card.stat_modifiers = [
		_modifier(StatModifier.Type.FLAT, 2.0, damage),
		_modifier(StatModifier.Type.PERCENT, 0.1, damage),
		_modifier(StatModifier.Type.FLAT, 0.5, Stat.Type.COOLDOWN),
		_modifier(StatModifier.Type.MULTIPLICATIVE, 0.2, Stat.Type.CRIT_MULTIPLIER),
	]
	var extras_only := _stat_card("test_extras_only", UpgradeDefinition.ScopeType.LOCAL_SLOT, 1, null)
	extras_only.stat_modifiers = [_modifier(StatModifier.Type.FLAT, 0.25, damage)]
	var extras_ledger := _new_ledger()
	var extras_lane := _lane(1, _arcane_tags(), extras_ledger)
	var extras_values := {}
	var probe_stats: Array[Stat.Type] = [damage, Stat.Type.COOLDOWN, Stat.Type.CRIT_MULTIPLIER, Stat.Type.DURATION]
	for stage in ["tier_0", "tier_1", "tier_2"]:
		if stage != "tier_0":
			extras_ledger.log_purchase(extras_card)
		for stat in probe_stats:
			extras_values["%s/%s/total" % [stage, _stat_name(stat)]] = _totals(extras_ledger, 1, _arcane_tags(), stat)
			extras_values["%s/%s/final" % [stage, _stat_name(stat)]] = extras_lane["stats"].get_final_stat_value(stat)
	extras_values["tier_2/slot_2_damage_total"] = _totals(extras_ledger, 2, _arcane_tags(), damage)
	extras_ledger.log_purchase(extras_only)
	extras_values["with_extras_only_card/damage_total"] = _totals(extras_ledger, 1, _arcane_tags(), damage)
	extras_values["with_extras_only_card/damage_final"] = extras_lane["stats"].get_final_stat_value(damage)
	computed["cards/additional_modifiers"] = extras_values

	# 7. Infusion level queries for cards that are not slot-specific infusions.
	var fire := load(FIRE) as UpgradeDefinition
	var general_fire_tagged := _stat_card("test_general_fire_tagged", UpgradeDefinition.ScopeType.LOCAL_SLOT, 1, _modifier(StatModifier.Type.FLAT, 1.0, damage))
	general_fire_tagged.target_tags = [Tags.Type.FIRE]
	var elementless_infusion := _stat_card("test_elementless_infusion", UpgradeDefinition.ScopeType.LOCAL_SLOT, 1, _modifier(StatModifier.Type.FLAT, 1.0, damage))
	elementless_infusion.category = UpgradeDefinition.Category.INFUSION
	var query_ledger := _new_ledger()
	var query_values := {}
	query_ledger.log_slot_specific_purchase(general_fire_tagged, 1)
	query_ledger.log_slot_specific_purchase(general_fire_tagged, 1)
	query_values["general_card_slot_specific_x2/levels_slot_1"] = query_ledger.get_infusion_levels(1)
	query_values["general_card_slot_specific_x2/fire_level_slot_1"] = query_ledger.get_infusion_level(1, Tags.Type.FIRE)
	query_ledger.log_purchase(fire)
	query_ledger.log_purchase(fire)
	query_values["plus_plain_fire_x2/levels_slot_0"] = query_ledger.get_infusion_levels(0)
	query_values["plus_plain_fire_x2/levels_slot_1"] = query_ledger.get_infusion_levels(1)
	query_values["plus_plain_fire_x2/fire_level_slot_0"] = query_ledger.get_infusion_level(0, Tags.Type.FIRE)
	query_values["plus_plain_fire_x2/fire_level_slot_1"] = query_ledger.get_infusion_level(1, Tags.Type.FIRE)
	query_ledger.log_slot_specific_purchase(fire, 1)
	query_values["plus_slot_fire_x1/levels_slot_1"] = query_ledger.get_infusion_levels(1)
	query_values["plus_slot_fire_x1/levels_slot_0"] = query_ledger.get_infusion_levels(0)
	query_ledger.log_slot_specific_purchase(fire, 3)
	query_values["slot_fire_in_slot_3/levels_slot_3"] = query_ledger.get_infusion_levels(3)
	query_ledger.log_slot_specific_purchase(elementless_infusion, 1)
	query_values["elementless_infusion/levels_slot_1"] = query_ledger.get_infusion_levels(1)
	query_values["elementless_infusion/level_for_NONE_slot_1"] = query_ledger.get_infusion_level(1, Tags.Type.NONE)
	query_values["elementless_infusion/level_for_PROJECTILE_slot_1"] = query_ledger.get_infusion_level(1, Tags.Type.PROJECTILE)
	computed["cards/infusion_level_queries"] = query_values

	# 2. A GLOBAL_TAG_MATCH stat card on real mounted abilities (the invalidation path reads the ability's tag component).
	var tag_card := _stat_card("test_tag_match", UpgradeDefinition.ScopeType.GLOBAL_TAG_MATCH, 0, _modifier(StatModifier.Type.PERCENT, 0.5, damage))
	tag_card.target_tags = [Tags.Type.FIRE]
	var player := fx.fresh_player()
	var ledger_a := player.run_ledger_component
	var fire_tags: Array[Tags.Type] = [Tags.Type.PROJECTILE, Tags.Type.FIRE]
	var ability_1 := _mount(player, 1)
	var ability_2 := _mount(player, 2)
	var ability_3 := _mount(player, 3, fire_tags)
	var tag_values := {
		"before_card/slot_1": ability_1.stats_container.get_final_stat_value(damage),
		"before_card/slot_3": ability_3.stats_container.get_final_stat_value(damage),
		"slot_3_has_fire_tag": ability_3.tag_component.has_tag(Tags.Type.FIRE),
		"slot_1_has_fire_tag": ability_1.tag_component.has_tag(Tags.Type.FIRE),
	}
	ability_2.stats_container.get_final_stat_value(damage)
	ledger_a.log_purchase(tag_card)
	tag_values["after_card/slot_1"] = ability_1.stats_container.get_final_stat_value(damage)
	tag_values["after_card/slot_2"] = ability_2.stats_container.get_final_stat_value(damage)
	tag_values["after_card/slot_3"] = ability_3.stats_container.get_final_stat_value(damage)
	tag_values["after_card/slot_1_total"] = _totals(ledger_a, 1, ability_1.tag_component.get_permanent_tags(), damage)
	tag_values["after_card/slot_3_total"] = _totals(ledger_a, 3, ability_3.tag_component.get_permanent_tags(), damage)
	# The matching tag appears on slot 1 through a Fire infusion
	ledger_a.log_slot_specific_purchase(fire, 1)
	tag_values["after_fire_infusion/slot_1_has_fire_tag"] = ability_1.tag_component.has_tag(Tags.Type.FIRE)
	tag_values["after_fire_infusion/slot_1"] = ability_1.stats_container.get_final_stat_value(damage)
	tag_values["after_fire_infusion/slot_2"] = ability_2.stats_container.get_final_stat_value(damage)
	# A temporary tag (a status effect's tag) appears on slot 2: stat cards ignore it (Task L6a; before, the ledger saw it
	# and the cache went stale).
	ability_2.tag_component.add_temporary_tag(Tags.Type.FIRE)
	tag_values["temp_tag_on_slot_2/ledger_total"] = _totals(ledger_a, 2, ability_2.tag_component.get_permanent_tags(), damage)
	tag_values["temp_tag_on_slot_2/cached_final"] = ability_2.stats_container.get_final_stat_value(damage)
	ability_2.stats_container.invalidate_all_caches()
	tag_values["temp_tag_on_slot_2/final_after_manual_invalidate"] = ability_2.stats_container.get_final_stat_value(damage)
	ability_2.tag_component.remove_temporary_tag(Tags.Type.FIRE)
	computed["cards/tag_match_stat_card"] = tag_values

	# The card is bought BEFORE the ability with the matching tag is mounted (the stats are built before the
	# ability's base tags are set). Recorded: the cached value is already correct right after the mount.
	player = fx.fresh_player()
	player.run_ledger_component.log_purchase(tag_card)
	var late_ability := _mount(player, 3, fire_tags)
	var late_values := {
		"mounted_with_fire_tag": late_ability.tag_component.has_tag(Tags.Type.FIRE),
		"ledger_total": _totals(player.run_ledger_component, 3, late_ability.tag_component.get_permanent_tags(), damage),
		"cached_final_right_after_mount": late_ability.stats_container.get_final_stat_value(damage),
	}
	late_ability.stats_container.invalidate_all_caches()
	late_values["final_after_manual_invalidate"] = late_ability.stats_container.get_final_stat_value(damage)
	computed["cards/tag_match_card_bought_before_mount"] = late_values

	# 5. A slot-specific purchase of a NON-infusion card that has modifiers. The ledger resolves it (the slot key wins),
	#    and since Task L6a the cache invalidation asks the ledger too, so the cached stat follows the purchase.
	var scopes := {
		"core_scope": [UpgradeDefinition.ScopeType.CHARACTER_CORE, 0],
		"local_slot_2": [UpgradeDefinition.ScopeType.LOCAL_SLOT, 2],
		"local_slot_1": [UpgradeDefinition.ScopeType.LOCAL_SLOT, 1],
	}
	for scope_name in scopes:
		player = fx.fresh_player()
		var scoped_card := _stat_card("test_slot_specific_general", scopes[scope_name][0], scopes[scope_name][1], _modifier(StatModifier.Type.PERCENT, 0.5, damage))
		var ability := _mount(player, 1)
		var before := ability.stats_container.get_final_stat_value(damage)
		player.run_ledger_component.log_slot_specific_purchase(scoped_card, 1)
		var cached_after := ability.stats_container.get_final_stat_value(damage)
		var ledger_total := _totals(player.run_ledger_component, 1, ability.tag_component.get_permanent_tags(), damage)
		ability.stats_container.invalidate_all_caches()
		var recomputed := ability.stats_container.get_final_stat_value(damage)
		computed["cards/slot_specific_general_card_%s" % scope_name] = {
			"final_before": before,
			"final_after_without_recompute": cached_after,
			"ledger_total": ledger_total,
			"final_after_manual_invalidate": recomputed,
			"cache_updated_by_purchase": absf(cached_after - recomputed) <= TOLERANCE,
		}


func _section_card_actions() -> void:
	# 6. Overclock purchase through the real purchase path.
	var player := fx.fresh_player()
	var ability := fx.mount_arcane_bolt(player)
	var gate := ability.evolution_gate_component
	var overclock := load(OVERCLOCK_CARD) as UpgradeDefinition
	var fire_frost_levels: Array[int] = [3, 3, 0, 0, 0]
	var overclock_values := {
		"before/flag": gate.is_permanently_overclocked,
		"before/export_has_overclocked_key": ability.export_runtime_state().has("overclocked"),
		"before/offer_eligible_at_fire3_frost3": gate.is_offer_eligible(fire_frost_levels),
	}
	player.apply_contextual_upgrade(_choice(overclock, 1))
	var registry := player.run_ledger_component.purchase_registry
	var exported := ability.export_runtime_state()
	overclock_values["after/registry_slot_key"] = registry.get("overclock::slot_1", 0)
	overclock_values["after/registry_plain_key"] = registry.get("overclock", 0)
	overclock_values["after/registry_size"] = registry.size()
	overclock_values["after/active_upgrades"] = player.run_ledger_component.active_upgrades.size()
	overclock_values["after/flag"] = gate.is_permanently_overclocked
	overclock_values["after/export_has_overclocked_key"] = exported.has("overclocked")
	overclock_values["after/exported_evolution_state"] = int(exported.get("evolution_state"))
	overclock_values["after/offer_eligible_at_fire3_frost3"] = gate.is_offer_eligible(fire_frost_levels)
	# An Overclock bought for a slot with no ability is still written to the ledger.
	player.apply_contextual_upgrade(_choice(overclock, 2))
	overclock_values["empty_slot_2/registry_slot_key"] = registry.get("overclock::slot_2", 0)
	computed["cards/overclock_purchase"] = overclock_values

	# 8. The real Arcane Bolt unlock card through Player.apply_contextual_upgrade.
	player = fx.fresh_player()
	var unlock := load(UNLOCK_CARD) as UpgradeDefinition
	var slot := unlock.ability_data_payload.slot_index
	var unlock_values := {
		"before/ability_in_slot": is_instance_valid(player.ability_container.get_ability_by_slot(slot)),
		"before/pool_offers_unlock": _pool_ids(player, 1).has("upgrade_arcane_bolt"),
	}
	player.apply_contextual_upgrade(_choice(unlock, 0))
	var mounted := player.ability_container.get_ability_by_slot(slot)
	unlock_values["after/ability_in_slot"] = is_instance_valid(mounted)
	unlock_values["after/slot"] = int(slot)
	unlock_values["after/registry_unlock"] = player.run_ledger_component.purchase_registry.get("upgrade_arcane_bolt", 0)
	unlock_values["after/data_path"] = mounted.data.resource_path
	unlock_values["after/display_name"] = mounted.display_name
	unlock_values["after/tags"] = _tag_ints(mounted.tag_component.get_active_tags())
	unlock_values["after/evolution_state"] = int(mounted.evolution_gate_component.current_state)
	unlock_values["after/overclocked"] = mounted.evolution_gate_component.is_permanently_overclocked
	unlock_values["after/infusion_levels"] = mounted.infusion_tracker_component.infusion_levels
	unlock_values.merge(_prefixed("after/stat", _all_stats(mounted.stats_container)))
	unlock_values["after/pool_offers_unlock_at_level_1"] = _pool_ids(player, 1).has("upgrade_arcane_bolt")
	unlock_values["after/pool_offers_unlock_at_level_99"] = _pool_ids(player, 99).has("upgrade_arcane_bolt")
	computed["cards/unlock_card"] = unlock_values


# ---------------------------------------------------------------------------------------------
# 7. Draft pool candidates. generate_selection_pool is deterministic (the random pick happens later, in
#    _roll_random_subset), so the whole candidate set is pinned, never a random pick.
# ---------------------------------------------------------------------------------------------

func _pool_entries(player: Player, level: int) -> Array:
	var pool := fx.get_upgrade_manager().generate_selection_pool(player, level)
	var out: Array = []
	for choice in pool:
		out.append("%s|%s|slot%d|%d/%d" % [
			choice.definition.upgrade_id, choice.target_display_name, choice.target_slot_index,
			choice.source_tracker.current_purchases, choice.source_tracker.max_purchases,
		])
	out.sort()
	return out


func _pool_ids(player: Player, level: int) -> Array:
	var ids: Array = []
	for entry in _pool_entries(player, level):
		ids.append(String(entry).split("|")[0])
	return ids


func _pool_state(state_name: String, player: Player, levels: Array) -> void:
	var values := {}
	for level in levels:
		values["level_%d" % level] = _pool_entries(player, level)
	computed["pool/%s" % state_name] = values


func _section_draft_pool() -> void:
	var core_card := load(CORE_CARD) as UpgradeDefinition
	var overclock := load(OVERCLOCK_CARD) as UpgradeDefinition
	var unlock := load(UNLOCK_CARD) as UpgradeDefinition

	var player := fx.fresh_player()
	_pool_state("fresh_run", player, [1, 99])

	player = fx.fresh_player()
	player.apply_contextual_upgrade(_choice(unlock, 0))
	_pool_state("after_unlock", player, [1, 99])

	# 11. The core Player Movement card leaves the pool at its profile's total_tiers (5).
	player = fx.fresh_player()
	for i in range(4):
		player.run_ledger_component.log_purchase(core_card)
	_pool_state("move_speed_tier_4", player, [4, 5, 99])
	player.run_ledger_component.log_purchase(core_card)
	_pool_state("move_speed_ceiling", player, [5, 6, 99])

	player = fx.fresh_player()
	player.apply_contextual_upgrade(_choice(unlock, 0))
	player.apply_contextual_upgrade(_choice(overclock, 1))
	_pool_state("after_overclock", player, [1, 99])

	player = fx.fresh_player()
	player.apply_contextual_upgrade(_choice(unlock, 0))
	for i in range(5):
		player.run_ledger_component.log_purchase(core_card)
	player.apply_contextual_upgrade(_choice(overclock, 1))
	_pool_state("every_card_exhausted", player, [1, 99])

	# Level gating: the lowest character level at which Player Movement is offered, per tier already bought (-1 = never).
	var gating := {}
	for tier in range(6):
		player = fx.fresh_player()
		for i in range(tier):
			player.run_ledger_component.log_purchase(core_card)
		var first_level := -1
		for level in range(1, 13):
			if _pool_ids(player, level).has("player_move_speed"):
				first_level = level
				break
		gating["tier_%d/first_level_offered" % tier] = first_level
	computed["pool/level_gating_move_speed"] = gating


# ---------------------------------------------------------------------------------------------
# 8. Evolution offers with test-only evolution cards
# ---------------------------------------------------------------------------------------------

func _evolution_card(id: String, evolves_from: AbilityData, recipe: Array[Tags.Type]) -> UpgradeDefinition:
	var card := _card(id, UpgradeDefinition.ScopeType.CHARACTER_CORE)
	card.payload_type = UpgradeDefinition.PayloadType.ABILITY_UNLOCK
	card.evolves_from = evolves_from
	card.recipe_requirements = recipe
	return card


func _ids_of(definitions: Array) -> Array:
	var ids: Array = []
	for definition in definitions:
		ids.append(definition.upgrade_id)
	return ids


func _section_evolution_offer() -> void:
	var manager := fx.get_upgrade_manager()
	var saved_pool := manager.master_upgrade_pool.duplicate()
	var arcane_data := load(Fixtures.ARCANE_BOLT_DATA) as AbilityData
	var fire_frost: Array[Tags.Type] = [Tags.Type.FIRE, Tags.Type.FROST]
	var fire_earth: Array[Tags.Type] = [Tags.Type.FIRE, Tags.Type.EARTH]
	var no_recipe: Array[Tags.Type] = []
	var evo_fire_frost := _evolution_card("test_evo_fire_frost", arcane_data, fire_frost)
	var evo_fire_earth := _evolution_card("test_evo_fire_earth", arcane_data, fire_earth)
	var evo_other_ability := _evolution_card("test_evo_other_ability", AbilityData.new(), fire_frost)
	var evo_no_recipe := _evolution_card("test_evo_no_recipe", arcane_data, no_recipe)
	var test_definitions: Array[UpgradeDefinition] = [evo_fire_frost, evo_fire_earth, evo_other_ability, evo_no_recipe]
	var test_profile := UpgradeBlueprintProfile.new()
	test_profile.definition_bundle = test_definitions
	test_profile.total_tiers = 1
	manager.master_upgrade_pool.append(test_profile)

	var fire := load(FIRE) as UpgradeDefinition
	var frost := load(FROST) as UpgradeDefinition
	var overclock := load(OVERCLOCK_CARD) as UpgradeDefinition
	var cases := {
		"fire2_frost3": [2, 3, "none"],
		"fire3_frost2": [3, 2, "none"],
		"fire3_frost3": [3, 3, "none"],
		"fire3_frost3_evolution_already_bought": [3, 3, "bought"],
		"fire3_frost3_overclocked": [3, 3, "overclocked"],
		"fire5_frost5": [5, 5, "none"],
	}
	for case_name in cases:
		var player := fx.fresh_player()
		var ability := fx.mount_arcane_bolt(player)
		var spec: Array = cases[case_name]
		for i in range(spec[0]):
			player.run_ledger_component.log_slot_specific_purchase(fire, 1)
		for i in range(spec[1]):
			player.run_ledger_component.log_slot_specific_purchase(frost, 1)
		if spec[2] == "bought":
			player.run_ledger_component.log_purchase(evo_fire_frost)
		elif spec[2] == "overclocked":
			player.apply_contextual_upgrade(_choice(overclock, 1))
		var levels := ability.infusion_tracker_component.infusion_levels
		var all_definitions: Array[UpgradeDefinition] = []
		for profile in manager.master_upgrade_pool:
			for definition in profile.definition_bundle:
				all_definitions.append(definition)
		var evaluated := ability.evolution_gate_component.evaluate_evolution_recipes(all_definitions, levels, ability.data)
		var offer := manager._build_offer_choices(player, 1)
		var offer_ids: Array = []
		for choice in offer:
			offer_ids.append(choice.definition.upgrade_id)
		computed["evolution/%s" % case_name] = {
			"infusion_levels": levels,
			"offer_eligible": ability.evolution_gate_component.is_offer_eligible(levels),
			"next_offer_slot": manager._find_next_offer_slot(player),
			"evaluate_returns": _ids_of(evaluated),
			"offer_build_returns": offer_ids,
			"draft_pool_ids_level_99": _pool_ids(player, 99),
		}
	manager.master_upgrade_pool = saved_pool


# ---------------------------------------------------------------------------------------------
# 9. The infusion draft pool (UpgradeManager._generate_infusion_pool), pinned before Task L6b
# ---------------------------------------------------------------------------------------------

func _infusion_pool_values(player: Player) -> Dictionary:
	var pool := fx.get_upgrade_manager()._generate_infusion_pool(player)
	var ids: Array = []
	var entries: Array = []
	for choice in pool:
		ids.append(choice.definition.upgrade_id)
		entries.append("%s|slot%d|%s|%d/%d" % [
			choice.definition.upgrade_id, choice.target_slot_index, choice.target_display_name,
			choice.source_tracker.current_purchases, choice.source_tracker.max_purchases,
		])
	ids.sort()
	entries.sort()
	return {"ids": ids, "entries": entries}


func _section_infusion_pool() -> void:
	var fire := load(FIRE) as UpgradeDefinition
	var frost := load(FROST) as UpgradeDefinition
	var overclock := load(OVERCLOCK_CARD) as UpgradeDefinition

	# a. no abilities mounted
	var player := fx.fresh_player()
	computed["infusion_pool/a_no_abilities"] = _infusion_pool_values(player)

	# b. Arcane Bolt mounted, no infusions
	player = fx.fresh_player()
	fx.mount_arcane_bolt(player)
	computed["infusion_pool/b_arcane_bolt_no_infusions"] = _infusion_pool_values(player)

	# c. Fire at level 3 (the tier 1 soft cap): Fire is not offered, the others are
	player = fx.fresh_player()
	fx.mount_arcane_bolt(player)
	_buy(player.run_ledger_component, FIRE, 1, 3)
	computed["infusion_pool/c_fire_level_3"] = _infusion_pool_values(player)

	# d. two elements active in the slot: a third new element is not offered, the two active ones still are
	player = fx.fresh_player()
	fx.mount_arcane_bolt(player)
	_buy(player.run_ledger_component, FIRE, 1, 1)
	_buy(player.run_ledger_component, FROST, 1, 1)
	computed["infusion_pool/d_two_elements_active"] = _infusion_pool_values(player)

	# e. the same slot as c after Overclock: Fire is offered again
	player = fx.fresh_player()
	fx.mount_arcane_bolt(player)
	_buy(player.run_ledger_component, FIRE, 1, 3)
	player.apply_contextual_upgrade(_choice(overclock, 1))
	computed["infusion_pool/e_fire_level_3_overclocked"] = _infusion_pool_values(player)

	# f. two abilities, one at the cap and the other not: still offered if ANY ability accepts the element
	player = fx.fresh_player()
	fx.mount_arcane_bolt(player)
	_mount(player, 2)
	_buy(player.run_ledger_component, FIRE, 1, 3)
	computed["infusion_pool/f_two_abilities_one_capped"] = _infusion_pool_values(player)

	# f2. both abilities at the cap: Fire is not offered
	_buy(player.run_ledger_component, FIRE, 2, 3)
	computed["infusion_pool/f2_two_abilities_both_capped"] = _infusion_pool_values(player)


# ---------------------------------------------------------------------------------------------
# 10. Draft eligibility of a GLOBAL_TAG_MATCH card: permanent tags only, all four slots (recorded after Task L6b)
# ---------------------------------------------------------------------------------------------

func _section_tag_card_draft() -> void:
	var manager := fx.get_upgrade_manager()
	var saved_pool := manager.master_upgrade_pool.duplicate()
	var tag_card := _stat_card("test_draft_tag_card", UpgradeDefinition.ScopeType.GLOBAL_TAG_MATCH, 0, _modifier(StatModifier.Type.PERCENT, 0.5, Stat.Type.BASE_DAMAGE))
	tag_card.target_tags = [Tags.Type.FIRE]
	var test_definitions: Array[UpgradeDefinition] = [tag_card]
	var test_profile := UpgradeBlueprintProfile.new()
	test_profile.definition_bundle = test_definitions
	manager.master_upgrade_pool.append(test_profile)
	var fire := load(FIRE) as UpgradeDefinition
	var plain_tags: Array[Tags.Type] = [Tags.Type.METAMAGIC, Tags.Type.PROJECTILE]
	var fire_tags: Array[Tags.Type] = [Tags.Type.PROJECTILE, Tags.Type.FIRE]

	var player := fx.fresh_player()
	_mount(player, 1, plain_tags)
	var values := {"no_matching_tag/offered": _pool_ids(player, 99).has("test_draft_tag_card")}
	var ability := player.ability_container.get_ability_by_slot(1)
	ability.tag_component.add_temporary_tag(Tags.Type.FIRE)
	values["temporary_tag_only/offered"] = _pool_ids(player, 99).has("test_draft_tag_card")
	ability.tag_component.remove_temporary_tag(Tags.Type.FIRE)
	_buy(player.run_ledger_component, FIRE, 1, 1)
	values["infusion_tag/offered"] = _pool_ids(player, 99).has("test_draft_tag_card")

	player = fx.fresh_player()
	_mount(player, 3, fire_tags)
	values["base_tag_on_slot_3/offered"] = _pool_ids(player, 99).has("test_draft_tag_card")
	computed["pool/tag_card_eligibility"] = values

	# Four abilities: only slot 4 carries the matching base tag, so the slot range must reach slot 4.
	player = fx.fresh_player()
	_mount(player, 1, plain_tags)
	_mount(player, 2, plain_tags)
	_mount(player, 3, plain_tags)
	_mount(player, 4, fire_tags)
	computed["pool/four_abilities_tag_card_on_slot_4"] = {"level_99": _pool_entries(player, 99)}

	manager.master_upgrade_pool = saved_pool
