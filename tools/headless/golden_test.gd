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
