extends Node
## Behavior checks for the headless runner. The test is split into sections; each section builds its own
## fresh state through Fixtures (see fixtures.gd) and frees it, so section order does not matter.

const Fixtures = preload("res://tools/headless/fixtures.gd")

var fails: int = 0
var tree: SceneTree
var world: Node
var fx: Fixtures
var emitted: Array = []
var _eb: Node

func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS  ", msg)
	else:
		fails += 1
		print("FAIL  ", msg)

func run(scene_tree: SceneTree, world_node: Node) -> int:
	tree = scene_tree
	world = world_node
	_eb = tree.root.get_node("EventBus")
	fx = Fixtures.new(tree, world)
	var sections: Array[Callable] = [
		_section_burn_ticks,
		_section_chill,
		_section_temporary_tags,
		_section_duration_zero,
		_section_refresh_ramp_cap,
		_section_death_clears_effects,
		_section_fire_ladder,
		_section_projectile_hitbox,
		_section_area_geometries,
		_section_burst_ledger,
		_section_infusion_tracker,
		_section_offer_draft,
		_section_pending_drafts,
		_section_fissure,
		_section_impact_bursts,
		_section_infusion_level_definition,
		_section_tracker_reads_ledger,
		_section_infusion_category,
		_section_purchase_key,
		_section_run_state_round_trip,
		_section_real_infusion_categories,
		_section_stat_modifier_list,
		_section_real_cards_use_stat_modifiers,
		_section_invalidation_follows_ledger,
		_section_debug_actions,
		_section_debug_infusion_grant,
		_section_state_inspector,
		_section_overclock_from_ledger,
		_section_stack_cap,
		_section_spawn_health,
	]
	for section in sections:
		fx.begin_section()
		await section.call()
		fx.end_section()
	print("LOGICTEST done fails=%d" % fails)
	return 1 if fails > 0 else 0

func _spawn_bat() -> Enemy:
	return fx.spawn_bat()

## Builds an in-memory StatsContainer from {Stat.Type: float}. With a ledger it behaves like an ability lane in `slot`.
func _make_stats(values: Dictionary, slot: int = 0, ledger: RunLedgerComponent = null) -> StatsContainer:
	return fx.make_stats(values, slot, ledger)


var _fissure_hits: Array[int] = []


func _count_fissure_hit(_payload: CombatPayload, index: int) -> void:
	_fissure_hits[index] += 1


## Casts a fissure from `origin` against bats placed at `offsets` and returns how many times each bat was hit.
func _cast_fissure(stats: StatsContainer, origin: Vector2, offsets: Array[Vector2]) -> Array[int]:
	var fissure := FissureGeometry.new()
	world.add_child(fissure)
	fx.track(fissure)
	_fissure_hits.clear()
	var bats: Array[Enemy] = []
	for i in range(offsets.size()):
		var bat := _spawn_bat()
		bat.set_physics_process(false)
		bat.global_position = origin + offsets[i]
		_fissure_hits.append(0)
		bat.hurtbox_component.hit_received.connect(_count_fissure_hit.bind(i))
		bats.append(bat)
	await tree.physics_frame
	await tree.physics_frame
	var payload := CombatPayload.new()
	payload.stats_container_id = stats.get_instance_id()
	fissure.execute_geometry({"origin": origin}, payload)
	var result: Array[int] = _fissure_hits.duplicate()
	for bat in bats:
		bat.queue_free()
	fissure.queue_free()
	return result


func _section_fissure() -> void:
	# Hurtbox circles have radius 10, so a strike of radius R hits a bat whose centre is within R + 10.
	# Strikes sit at +70, +140, +210 on x with radii R, R + 15, R + 30 (R = AOE_RADIUS = 40).
	var origin := Vector2(80000.0, 80000.0)
	var hits := await _cast_fissure(_make_stats({Stat.Type.AOE_RADIUS: 40.0}), origin, [
		Vector2(70, 45), Vector2(70, 52),
		Vector2(140, 62), Vector2(140, 70),
		Vector2(210, 77), Vector2(210, 83),
	])
	check(hits[0] == 1 and hits[1] == 0, "fissure: first strike radius = AOE_RADIUS (40), hit at 45, miss at 52")
	check(hits[2] == 1 and hits[3] == 0, "fissure: second strike at +140 with radius 55 (spacing 70, growth 15)")
	check(hits[4] == 1 and hits[5] == 0, "fissure: third strike at +210 with radius 70 (spacing 70, growth 15)")
	# Without AOE_RADIUS the first strike falls back to starting_radius 30 (hit within 40)
	var fallback_hits := await _cast_fissure(_make_stats({}), origin + Vector2(0, 5000), [Vector2(70, 35), Vector2(70, 45)])
	check(fallback_hits[0] == 1 and fallback_hits[1] == 0, "fissure: no AOE_RADIUS falls back to starting_radius 30")


var _recorded: Dictionary = {}


func _record_hit(payload: CombatPayload, key: int) -> void:
	_recorded[key].append(payload)


func _make_burst(id: StringName, trigger: ImpactBurstDefinition.Trigger, fraction: float = 0.5, bonus: float = 0.0, cap: float = 0.0, radius_multiplier: float = 1.0) -> ImpactBurstDefinition:
	var definition := ImpactBurstDefinition.new()
	definition.burst_id = id
	definition.trigger = trigger
	definition.damage_fraction = fraction
	definition.per_enemy_bonus = bonus
	definition.per_enemy_bonus_cap = cap
	var shape := CircleBurstShape.new()
	shape.radius_multiplier = radius_multiplier
	definition.shape = shape
	return definition


func _burst_payload(stats: StatsContainer, damage: float, definitions: Array[ImpactBurstDefinition], critical: bool = false) -> CombatPayload:
	var payload := CombatPayload.new()
	payload.stats_container_id = stats.get_instance_id()
	payload.final_damage = damage
	payload.is_critical_hit = critical
	payload.impact_bursts = definitions
	return payload


## Spawns stationary bats (1000 hp) at origin + offsets, records every payload they receive, and waits for physics to register them.
func _spawn_burst_bats(origin: Vector2, offsets: Array[Vector2]) -> Array[Enemy]:
	_recorded.clear()
	var bats: Array[Enemy] = []
	for i in range(offsets.size()):
		var bat := _spawn_bat()
		bat.set_physics_process(false)
		bat.health_component.update_max_health(1000.0, true)
		bat.health_component.set_to_full()
		bat.global_position = origin + offsets[i]
		_recorded[i] = []
		bat.hurtbox_component.hit_received.connect(_record_hit.bind(i))
		bats.append(bat)
	await tree.physics_frame
	await tree.physics_frame
	return bats


func _lost(bat: Enemy) -> float:
	return 1000.0 - bat.health_component.current_health


func _free_bats(bats: Array[Enemy]) -> void:
	for bat in bats:
		bat.queue_free()


func _section_impact_bursts() -> void:
	var stats := _make_stats({Stat.Type.AOE_RADIUS: 40.0})
	var on_hit := _make_burst(&"test_on_hit", ImpactBurstDefinition.Trigger.ON_HIT)
	var on_crit := _make_burst(&"test_on_crit", ImpactBurstDefinition.Trigger.ON_CRIT)
	var burn := load("res://resources/status_effects/burn.tres") as StatusEffect

	# --- ON_HIT burst: B in range takes the fraction, C out of range nothing, A only the primary hit; deferred ---
	var bats := await _spawn_burst_bats(Vector2(90000.0, 90000.0), [Vector2(0, 0), Vector2(30, 0), Vector2(100, 0)])
	bats[0].hurtbox_component.take_hit(_burst_payload(stats, 10.0, [on_hit]))
	check(is_equal_approx(_lost(bats[1]), 0.0), "burst deferred: neighbor untouched when take_hit returns")
	await tree.process_frame
	check(is_equal_approx(_lost(bats[1]), 5.0), "burst ON_HIT: neighbor in range takes damage_fraction of the hit (5.0 of 10)")
	check(is_equal_approx(_lost(bats[2]), 0.0), "burst ON_HIT: neighbor out of range takes nothing")
	check(is_equal_approx(_lost(bats[0]), 10.0) and _recorded[0].size() == 1, "burst ON_HIT: primary takes only the primary hit (10.0, once)")
	_free_bats(bats)

	# --- Regression: a payload with no bursts behaves as before ---
	bats = await _spawn_burst_bats(Vector2(90000.0, 91000.0), [Vector2(0, 0), Vector2(30, 0)])
	bats[0].hurtbox_component.take_hit(_burst_payload(stats, 10.0, []))
	await tree.process_frame
	await tree.process_frame
	check(is_equal_approx(_lost(bats[0]), 10.0) and _recorded[0].size() == 1, "no bursts: primary hit unchanged (10.0, once)")
	check(is_equal_approx(_lost(bats[1]), 0.0) and _recorded[1].is_empty(), "no bursts: neighbor untouched")
	_free_bats(bats)

	# --- ON_CRIT burst: fires only on a crit, using the crit hit's final damage ---
	var crit_stats := _make_stats({Stat.Type.AOE_RADIUS: 40.0, Stat.Type.BASE_DAMAGE: 10.0, Stat.Type.CRIT_CHANCE: 1.0, Stat.Type.CRIT_MULTIPLIER: 2.0})
	var plain_stats := _make_stats({Stat.Type.AOE_RADIUS: 40.0, Stat.Type.BASE_DAMAGE: 10.0, Stat.Type.CRIT_CHANCE: 0.0, Stat.Type.CRIT_MULTIPLIER: 2.0})
	var crit_payload := CombatCalculations.generate_hit_payload(world as Node2D, crit_stats, null)
	var plain_payload := CombatCalculations.generate_hit_payload(world as Node2D, plain_stats, null)
	check(crit_payload.is_critical_hit and is_equal_approx(crit_payload.final_damage, 20.0), "cast time: a crit is recorded on the payload (is_critical_hit, damage 20)")
	check(not plain_payload.is_critical_hit and is_equal_approx(plain_payload.final_damage, 10.0), "cast time: a non-crit is recorded (is_critical_hit false, damage 10)")
	var crit_bursts: Array[ImpactBurstDefinition] = [on_crit]
	crit_payload.impact_bursts = crit_bursts
	plain_payload.impact_bursts = crit_bursts
	bats = await _spawn_burst_bats(Vector2(90000.0, 92000.0), [Vector2(0, 0), Vector2(30, 0)])
	bats[0].hurtbox_component.take_hit(crit_payload)
	await tree.process_frame
	check(is_equal_approx(_lost(bats[1]), 10.0), "burst ON_CRIT: a crit hit fires it using the crit damage (0.5 of 20 = 10)")
	_free_bats(bats)
	bats = await _spawn_burst_bats(Vector2(90000.0, 93000.0), [Vector2(0, 0), Vector2(30, 0)])
	bats[0].hurtbox_component.take_hit(plain_payload)
	await tree.process_frame
	await tree.process_frame
	check(is_equal_approx(_lost(bats[1]), 0.0), "burst ON_CRIT: a non-crit hit does not fire it")
	_free_bats(bats)

	# --- No recursion, never crits, no statuses; one burst with two neighbors caught ---
	var status_list: Array[StatusEffect] = [burn]
	var loud := _burst_payload(stats, 20.0, [on_hit], true)
	loud.status_effects_to_apply = status_list
	loud.dot_damage_snapshot = 1.0
	loud.status_duration_snapshot = 3.0
	bats = await _spawn_burst_bats(Vector2(90000.0, 94000.0), [Vector2(0, 0), Vector2(30, 0), Vector2(-30, 0)])
	bats[0].hurtbox_component.take_hit(loud)
	await tree.process_frame
	await tree.process_frame
	await tree.process_frame
	check(_recorded[1].size() == 1 and _recorded[2].size() == 1 and _recorded[0].size() == 1, "burst: exactly one burst, no recursion (each neighbor hit once, primary once)")
	var burst_seen: CombatPayload = _recorded[1][0]
	check(burst_seen.is_burst and burst_seen.impact_bursts.is_empty(), "burst payload: is_burst true and impact_bursts empty")
	check(not burst_seen.is_critical_hit and burst_seen.status_effects_to_apply.is_empty() and is_equal_approx(burst_seen.final_damage, 10.0), "burst payload: never crits, carries no statuses (0.5 of 20 = 10)")
	check(bats[1].status_effect_component._active_effects.is_empty() and bats[2].status_effect_component._active_effects.is_empty(), "burst: neighbors get no status even though the source carried Burn")
	check(bats[0].status_effect_component._active_effects.has("burn") and loud.impact_bursts.size() == 1 and not loud.is_burst, "source payload untouched: primary still gets Burn, bursts and flags intact")
	_free_bats(bats)

	# --- per_enemy_bonus and cap (0.5 * (1 + min(0.2 * n, 0.3))) ---
	var scaled := _make_burst(&"test_scaled", ImpactBurstDefinition.Trigger.ON_HIT, 0.5, 0.2, 0.3)
	bats = await _spawn_burst_bats(Vector2(90000.0, 95000.0), [Vector2(0, 0), Vector2(30, 0)])
	bats[0].hurtbox_component.take_hit(_burst_payload(stats, 10.0, [scaled]))
	await tree.process_frame
	check(is_equal_approx(_lost(bats[1]), 6.0), "burst bonus: 1 caught gives 1 + 0.2 (0.5 * 1.2 * 10 = 6.0)")
	_free_bats(bats)
	bats = await _spawn_burst_bats(Vector2(90000.0, 96000.0), [Vector2(0, 0), Vector2(30, 0), Vector2(-30, 0), Vector2(0, 30)])
	bats[0].hurtbox_component.take_hit(_burst_payload(stats, 10.0, [scaled]))
	await tree.process_frame
	check(is_equal_approx(_lost(bats[1]), 6.5) and is_equal_approx(_lost(bats[2]), 6.5) and is_equal_approx(_lost(bats[3]), 6.5), "burst bonus: 3 caught hits the cap (0.5 * 1.3 * 10 = 6.5 each)")
	_free_bats(bats)

	# --- Missing AOE_RADIUS: no burst, one warning ---
	var no_aoe := _make_stats({})
	check(not CircleBurstShape._warned_missing_radius, "no burst warning issued yet")
	bats = await _spawn_burst_bats(Vector2(90000.0, 97000.0), [Vector2(0, 0), Vector2(30, 0)])
	bats[0].hurtbox_component.take_hit(_burst_payload(no_aoe, 10.0, [on_hit]))
	await tree.process_frame
	await tree.process_frame
	check(is_equal_approx(_lost(bats[1]), 0.0), "burst without AOE_RADIUS: no burst")
	var empty_space := (world as Node2D).get_world_2d().direct_space_state
	var again: Array[HurtboxComponent] = []
	for i in range(3):
		again.append_array(on_hit.shape.find_targets(Vector2.ZERO, no_aoe, empty_space, 0))
	check(again.is_empty() and CircleBurstShape._warned_missing_radius, "burst without AOE_RADIUS: empty on repeated calls, warning flag set (one warning line is counted in the output)")
	_free_bats(bats)

	# --- Triggered from a real physics callback (a CombatVolume entering a hurtbox) ---
	var phys_stats := _make_stats({Stat.Type.AOE_RADIUS: 5.0, Stat.Type.DURATION: 5.0, Stat.Type.PROJECTILE_MOVEMENT_SPEED: 0.0})
	var wide := _make_burst(&"test_wide", ImpactBurstDefinition.Trigger.ON_HIT, 0.5, 0.0, 0.0, 8.0)
	var phys_origin := Vector2(90000.0, 98000.0)
	bats = await _spawn_burst_bats(phys_origin, [Vector2(0, 0), Vector2(30, 0)])
	var projectile := (load("res://components/ability/projectile.tscn") as PackedScene).instantiate() as Projectile
	projectile.initialize_volume(phys_origin, Vector2.RIGHT, 0, _burst_payload(phys_stats, 10.0, [wide]))
	world.get_node("GameWorld/ProjectilesContainer").add_child(projectile)
	fx.track(projectile)
	for i in range(4):
		await tree.physics_frame
	await tree.process_frame
	check(_recorded[0].size() == 1 and is_equal_approx(_lost(bats[0]), 10.0), "physics callback: the volume hit the primary once (10.0)")
	check(is_equal_approx(_lost(bats[1]), 5.0), "physics callback: the burst ran after a real area_entered hit (neighbor took 5.0; no space-state error in the output)")
	_free_bats(bats)


## Spawns a Projectile whose payload points at `stats`, returns its hitbox radius, then frees it.
func _spawn_projectile_radius(container: Node, stats: StatsContainer) -> float:
	var payload := CombatPayload.new()
	payload.stats_container_id = stats.get_instance_id()
	return _spawn_projectile_radius_from_payload(container, payload)


func _spawn_projectile_radius_from_payload(container: Node, payload: CombatPayload) -> float:
	var projectile := (load("res://components/ability/projectile.tscn") as PackedScene).instantiate() as Projectile
	projectile.initialize_volume(Vector2(100000.0, 100000.0), Vector2.RIGHT, 0, payload)
	container.add_child(projectile)
	var radius := (projectile.collision_shape.shape as CircleShape2D).radius
	projectile.queue_free()
	return radius


func _section_burn_ticks() -> void:
	var burn := load("res://resources/status_effects/burn.tres") as StatusEffect
	var bat := _spawn_bat()
	var comp := bat.status_effect_component
	bat.health_component.update_max_health(1000.0, true)
	bat.health_component.set_to_full()
	var hp0 := bat.health_component.current_health
	comp.apply_effect(burn, 10.0, 2.0)
	check(bat.tag_component.has_tag(Tags.Type.BURNING), "burn grants BURNING")
	comp._process(0.5)
	var ramp := burn.ramp_bonus_per_second
	var expected := 10.0 * (1.0 + 0.5 * ramp) * 0.5
	check(is_equal_approx(hp0 - bat.health_component.current_health, expected), "first burn tick = %.3f" % expected)
	comp._process(0.5)
	var expected2 := 10.0 * (1.0 + 1.0 * ramp) * 0.5
	check(is_equal_approx(hp0 - bat.health_component.current_health, expected + expected2), "second tick ramps")
	var inst: StatusEffectInstance = comp._active_effects["burn"]
	check(is_equal_approx(inst.get_effective_duration(), 2.0), "duration = template base 0 + bonus 2")
	comp.apply_effect(burn, 10.0, 2.0)
	check(comp._active_effects.size() == 1 and is_equal_approx(inst.elapsed, 1.0), "refresh keeps elapsed, one instance")
	for i in range(12):
		comp._process(0.5)
		if not is_instance_valid(bat) or bat.health_component.current_health <= 0.0:
			break
	check(is_instance_valid(bat) and comp._active_effects.is_empty() and not bat.tag_component.has_tag(Tags.Type.BURNING), "burn run to expiry: effect cleared and BURNING released")


func _section_chill() -> void:
	var chill := load("res://resources/status_effects/chill.tres") as StatusEffect
	var bat2 := _spawn_bat()
	var speed0 := bat2.stats_container.get_final_stat_value(Stat.Type.MOVEMENT_SPEED)
	bat2.status_effect_component.apply_effect(chill, 0.0, 0.0)
	var speed1 := bat2.stats_container.get_final_stat_value(Stat.Type.MOVEMENT_SPEED)
	check(is_equal_approx(speed1, speed0 * 0.7), "chill slows to 70%% (%.1f -> %.1f)" % [speed0, speed1])
	check(bat2.tag_component.has_tag(Tags.Type.CHILLED), "chill grants CHILLED")
	for i in range(8):
		bat2.status_effect_component._process(0.5)
	check(is_equal_approx(bat2.stats_container.get_final_stat_value(Stat.Type.MOVEMENT_SPEED), speed0), "speed restored on expiry")
	check(not bat2.tag_component.has_tag(Tags.Type.CHILLED), "CHILLED removed on expiry")


func _section_temporary_tags() -> void:
	var tc := _spawn_bat().tag_component
	tc.add_temporary_tag(Tags.Type.FROZEN)
	tc.add_temporary_tag(Tags.Type.FROZEN)
	tc.remove_temporary_tag(Tags.Type.FROZEN)
	check(tc.has_tag(Tags.Type.FROZEN), "refcounted tag survives one removal")
	tc.remove_temporary_tag(Tags.Type.FROZEN)
	check(not tc.has_tag(Tags.Type.FROZEN), "tag gone after last removal")


func _section_duration_zero() -> void:
	# Burn is not applied when its template base_duration is 0 and there is no STATUS_DURATION
	var burn := load("res://resources/status_effects/burn.tres") as StatusEffect
	var bat6 := _spawn_bat()
	bat6.health_component.update_max_health(1000.0, true)
	bat6.health_component.set_to_full()
	var hp6 := bat6.health_component.current_health
	bat6.status_effect_component.apply_effect(burn, 10.0, 0.0, 0.0)
	check(bat6.status_effect_component._active_effects.is_empty(), "duration 0: no instance created")
	check(not bat6.tag_component.has_tag(Tags.Type.BURNING), "duration 0: no BURNING tag")
	for i in range(6):
		bat6.status_effect_component._process(0.5)
	check(is_equal_approx(bat6.health_component.current_health, hp6), "duration 0: no ticks, no damage")


func _section_refresh_ramp_cap() -> void:
	# REFRESH takes the latest applier's ramp_cap_bonus
	var burn := load("res://resources/status_effects/burn.tres") as StatusEffect
	var bat7 := _spawn_bat()
	var comp7 := bat7.status_effect_component
	comp7.apply_effect(burn, 10.0, 3.0, 0.1)
	var inst7: StatusEffectInstance = comp7._active_effects["burn"]
	check(is_equal_approx(inst7.ramp_cap_bonus, 0.1), "applied with ramp_cap_bonus 0.1")
	comp7.apply_effect(burn, 10.0, 3.0, 0.3)
	check(comp7._active_effects.size() == 1 and comp7._active_effects["burn"] == inst7 and is_equal_approx(inst7.ramp_cap_bonus, 0.3), "refresh overwrites ramp_cap_bonus with 0.3")
	comp7.apply_effect(burn, 10.0, 3.0, 0.05)
	check(is_equal_approx(inst7.ramp_cap_bonus, 0.05), "refresh takes latest value even when lower (0.05)")
	for i in range(8):
		comp7._process(0.5)
	check(comp7._active_effects.is_empty() and not bat7.tag_component.has_tag(Tags.Type.BURNING), "refreshed burn expires and BURNING is released")


func _section_death_clears_effects() -> void:
	var burn := load("res://resources/status_effects/burn.tres") as StatusEffect
	var bat3 := _spawn_bat()
	bat3.status_effect_component.apply_effect(burn, 10.0, 3.0)
	bat3.health_component.take_damage(9999.0)
	check(bat3.status_effect_component._active_effects.is_empty(), "death clears effects")


func _section_fire_ladder() -> void:
	var burn := load("res://resources/status_effects/burn.tres") as StatusEffect
	var player := fx.fresh_player()
	check(is_instance_valid(player), "player exists")
	if not is_instance_valid(player):
		return
	var ability := fx.mount_arcane_bolt(player)
	check(is_instance_valid(ability), "arcane bolt mounted")
	var fire := load("res://resources/infusions/inf_fire_upgrade_def.tres") as UpgradeDefinition
	var frost := load("res://resources/infusions/inf_frost_upgrade_def.tres") as UpgradeDefinition
	var sc := ability.stats_container
	check(sc.get_status_effects().is_empty(), "no statuses before infusions")
	var p0 := CombatCalculations.generate_hit_payload(player, sc, ability.tag_component)
	check(p0.status_effects_to_apply.is_empty(), "no fire: no status in the payload")
	check(is_equal_approx(p0.dot_damage_snapshot, 0.15) and is_equal_approx(p0.status_duration_snapshot, 0.0), "no fire: base DOT_DAMAGE 0.15, STATUS_DURATION 0")

	# Fire level 1: duration 3.0, cap bonus 0.1, Burn lasts 3.0 s, tick at elapsed 3.0 uses 1.3
	player.run_ledger_component.log_slot_specific_purchase(fire, 1)
	var p1 := CombatCalculations.generate_hit_payload(player, sc, ability.tag_component)
	check(p1.status_effects_to_apply.size() == 1 and is_equal_approx(p1.dot_damage_snapshot, 0.15), "fire L1: burn carried, DOT_DAMAGE unchanged by Fire (0.15)")
	check(is_equal_approx(p1.status_duration_snapshot, 3.0) and is_equal_approx(p1.status_ramp_cap_snapshot, 0.1), "fire L1: STATUS_DURATION 3.0, STATUS_RAMP_CAP 0.1")
	var ticks1: Array = []
	var bat4 := _spawn_bat()
	bat4.health_component.update_max_health(1000.0, true)
	bat4.health_component.set_to_full()
	bat4.status_effect_component.ticked.connect(func(i: StatusEffectInstance, dmg: float) -> void: ticks1.append([i.elapsed, i.get_ramp_multiplier(), dmg]))
	bat4.status_effect_component.apply_effect(burn, p1.dot_damage_snapshot, p1.status_duration_snapshot, p1.status_ramp_cap_snapshot)
	for i in range(6):
		bat4.status_effect_component._process(0.5)
	check(ticks1.size() == 6 and is_equal_approx(ticks1[5][0], 3.0) and is_equal_approx(ticks1[5][1], 1.3) and is_equal_approx(ticks1[5][2], 0.15 * 1.3 * 0.5), "fire L1: tick at elapsed 3.0 has multiplier 1.3")
	check(bat4.status_effect_component._active_effects.is_empty() and not bat4.tag_component.has_tag(Tags.Type.BURNING), "fire L1: burn lasted exactly 3.0 s")

	player.run_ledger_component.log_slot_specific_purchase(fire, 1)
	check(is_equal_approx(sc.get_final_stat_value(Stat.Type.STATUS_DURATION), 6.0) and is_equal_approx(sc.get_final_stat_value(Stat.Type.STATUS_RAMP_CAP), 0.2), "flat modifiers scale with tier: L2 = 6.0 s, 0.2")
	var effs := sc.get_status_effects()
	check(effs.size() == 1 and effs[0].effect_id == "burn", "fire x2 -> single burn (dedup)")
	var p := CombatCalculations.generate_hit_payload(player, sc, ability.tag_component)
	check(p.status_effects_to_apply.size() == 1 and p.dot_damage_snapshot > 0.0, "payload carries burn, dot snapshot %.2f" % p.dot_damage_snapshot)

	# Fire level 3: duration 9.0, cap 0.5 + 0.3 = 0.8, multiplier at elapsed 8.0 is 1.8
	player.run_ledger_component.log_slot_specific_purchase(fire, 1)
	var p3 := CombatCalculations.generate_hit_payload(player, sc, ability.tag_component)
	check(is_equal_approx(p3.status_duration_snapshot, 9.0) and is_equal_approx(p3.status_ramp_cap_snapshot, 0.3), "fire L3: STATUS_DURATION 9.0, STATUS_RAMP_CAP 0.3")
	var ticks3: Array = []
	var bat5 := _spawn_bat()
	bat5.health_component.update_max_health(1000.0, true)
	bat5.health_component.set_to_full()
	bat5.status_effect_component.ticked.connect(func(i: StatusEffectInstance, dmg: float) -> void: ticks3.append([i.elapsed, i.get_ramp_multiplier(), dmg]))
	bat5.status_effect_component.apply_effect(burn, p3.dot_damage_snapshot, p3.status_duration_snapshot, p3.status_ramp_cap_snapshot)
	for i in range(18):
		bat5.status_effect_component._process(0.5)
	check(ticks3.size() == 18 and is_equal_approx(ticks3[15][0], 8.0) and is_equal_approx(ticks3[15][1], 1.8), "fire L3: multiplier at elapsed 8.0 is 1.8")
	check(is_equal_approx(ticks3[17][0], 9.0) and is_equal_approx(ticks3[17][1], 1.8), "fire L3: capped at 1.8 through elapsed 9.0")
	check(bat5.status_effect_component._active_effects.is_empty() and not bat5.tag_component.has_tag(Tags.Type.BURNING), "fire L3: burn lasted exactly 9.0 s")

	player.run_ledger_component.log_slot_specific_purchase(frost, 1)
	p = CombatCalculations.generate_hit_payload(player, sc, ability.tag_component)
	check(p.status_effects_to_apply.size() == 2, "fire + frost -> both statuses")
	var d := p.duplicate() as CombatPayload
	check(d.status_effects_to_apply.size() == 2, "duplicate keeps statuses")


func _section_projectile_hitbox() -> void:
	# Projectile hitbox radius comes from AOE_RADIUS
	var player := fx.fresh_player()
	var ability := fx.mount_arcane_bolt(player)
	var sc := ability.stats_container
	var proj_container := world.get_node("GameWorld/ProjectilesContainer")
	var custom_stats: Dictionary[Stat.Type, float] = {}
	custom_stats[Stat.Type.AOE_RADIUS] = 7.0
	custom_stats[Stat.Type.DURATION] = 5.0
	custom_stats[Stat.Type.PROJECTILE_MOVEMENT_SPEED] = 100.0
	var custom := _make_stats(custom_stats)
	check(is_equal_approx(_spawn_projectile_radius(proj_container, custom), 7.0), "hitbox radius follows AOE_RADIUS (7.0)")
	custom_stats[Stat.Type.AOE_RADIUS] = 25.0
	var custom2 := _make_stats(custom_stats)
	check(is_equal_approx(_spawn_projectile_radius(proj_container, custom2), 25.0), "hitbox radius follows AOE_RADIUS (25.0)")

	var bolt_payload := CombatCalculations.generate_hit_payload(player, sc, ability.tag_component)
	check(is_equal_approx(_spawn_projectile_radius_from_payload(proj_container, bolt_payload), 10.0), "arcane bolt without Earth: radius 10.0")
	var earth := load("res://resources/infusions/inf_earth_upgrade_def.tres") as UpgradeDefinition
	for earth_level in [1, 2, 3]:
		player.run_ledger_component.log_slot_specific_purchase(earth, 1)
		var earth_payload := CombatCalculations.generate_hit_payload(player, sc, ability.tag_component)
		var earth_radius := _spawn_projectile_radius_from_payload(proj_container, earth_payload)
		print("INFO  earth level %d -> radius %.3f" % [earth_level, earth_radius])
		check(is_equal_approx(earth_radius, 10.0 * (1.0 + 0.1 * earth_level)), "arcane bolt with Earth L%d: radius %.1f" % [earth_level, earth_radius])

	var no_aoe_stats: Dictionary[Stat.Type, float] = {}
	no_aoe_stats[Stat.Type.DURATION] = 5.0
	no_aoe_stats[Stat.Type.PROJECTILE_MOVEMENT_SPEED] = 100.0
	var no_aoe := _make_stats(no_aoe_stats)
	check(not CombatVolume._warned_missing_radius, "no warning issued before a profile lacks AOE_RADIUS")
	var default_ok := true
	for i in range(3):
		default_ok = default_ok and is_equal_approx(_spawn_projectile_radius(proj_container, no_aoe), 10.0)
	check(default_ok, "profile without AOE_RADIUS: default radius 10.0 on 3 spawns")
	check(CombatVolume._warned_missing_radius, "missing AOE_RADIUS warns (flag set; exactly one warning line is counted in the output)")


func _section_area_geometries() -> void:
	# Area geometries read AOE_RADIUS (Task H)
	var player := fx.fresh_player()
	var earth := load("res://resources/infusions/inf_earth_upgrade_def.tres") as UpgradeDefinition
	var area_stats := _make_stats({Stat.Type.AOE_RADIUS: 200.0, Stat.Type.QUERY_RADIUS: 150.0})
	var pulse := RadialPulseGeometry.new()
	fx.track(pulse)
	check(is_equal_approx((pulse.get_query_shape(area_stats) as CircleShape2D).radius, 200.0), "radial pulse: query circle = AOE_RADIUS (200)")
	player.run_ledger_component.log_slot_specific_purchase(earth, 2)
	var earth_area_stats := _make_stats({Stat.Type.AOE_RADIUS: 200.0, Stat.Type.QUERY_RADIUS: 150.0}, 2, player.run_ledger_component)
	var earth_pulse_radius := (pulse.get_query_shape(earth_area_stats) as CircleShape2D).radius
	print("INFO  radial pulse with Earth level 1 -> radius %.3f" % earth_pulse_radius)
	check(is_equal_approx(earth_pulse_radius, 220.0), "radial pulse with Earth L1: radius %.1f" % earth_pulse_radius)
	var query_only_stats := _make_stats({Stat.Type.QUERY_RADIUS: 150.0})
	check(not GeometryDriver._warned_area_fallback, "no area fallback warning issued yet")
	var fallback_ok := true
	for i in range(3):
		fallback_ok = fallback_ok and is_equal_approx((pulse.get_query_shape(query_only_stats) as CircleShape2D).radius, 150.0)
	check(fallback_ok, "radial pulse: no AOE_RADIUS falls back to QUERY_RADIUS (150) on 3 calls")
	check(GeometryDriver._warned_area_fallback, "area fallback warns (flag set; exactly one warning line is counted in the output)")

	var sweep := LinearSweepGeometry.new()
	fx.track(sweep)
	var wedge := sweep.get_query_shape(area_stats) as ConvexPolygonShape2D
	check(is_equal_approx(wedge.points[1].length(), 200.0) and is_equal_approx(wedge.points[2].length(), 200.0), "linear sweep: far vertices at AOE_RADIUS (200)")
	var default_wedge := sweep.get_query_shape(_make_stats({})) as ConvexPolygonShape2D
	check(is_equal_approx(default_wedge.points[1].length(), 120.0) and is_equal_approx(default_wedge.points[2].length(), 120.0), "linear sweep: no AOE_RADIUS falls back to strike_length (120)")

	var vortex := ConvergingVortexGeometry.new()
	fx.track(vortex)
	check(is_equal_approx((vortex.get_query_shape(area_stats) as CircleShape2D).radius, 200.0), "converging vortex: query circle = AOE_RADIUS (200)")
	var vortex_origin := Vector2(60000.0, 60000.0)
	var vortex_bat := _spawn_bat()
	vortex_bat.set_physics_process(false)
	vortex_bat.global_position = vortex_origin + Vector2(200.0, 0.0)
	vortex_bat.velocity = Vector2.ZERO
	var vortex_payload := CombatPayload.new()
	vortex_payload.stats_container_id = area_stats.get_instance_id()
	vortex._process_volume_hit(vortex_bat.hurtbox_component, vortex_origin, vortex_payload)
	check(is_equal_approx(vortex_bat.velocity.length(), vortex.horizontal_suction_force), "converging vortex: falloff weight is 0 at distance == AOE_RADIUS (force 450)")
	vortex_bat.velocity = Vector2.ZERO
	vortex_bat.global_position = vortex_origin + Vector2(100.0, 0.0)
	vortex._process_volume_hit(vortex_bat.hurtbox_component, vortex_origin, vortex_payload)
	check(is_equal_approx(vortex_bat.velocity.length(), vortex.horizontal_suction_force * 1.5), "converging vortex: weight 0.5 at half the radius (force 675), never negative")

	var chain := ChainLinkGeometry.new()
	fx.track(chain)
	check(is_equal_approx((chain.get_query_shape(area_stats) as CircleShape2D).radius, 150.0), "chain link: still a QUERY_RADIUS circle (150)")
	for scene_path in [
		"res://components/ability/drivers/geometry/projectile/targeted_projectile_geometry.tscn",
		"res://components/ability/drivers/geometry/projectile/straight_projectile_geometry.tscn",
		"res://components/ability/drivers/geometry/projectile/mouse_aim_projectile_geometry.tscn",
	]:
		var projectile_geometry := (load(scene_path) as PackedScene).instantiate() as GeometryDriver
		fx.track(projectile_geometry)
		var projectile_shape := projectile_geometry.get_query_shape(area_stats) as CircleShape2D
		check(projectile_shape != null and is_equal_approx(projectile_shape.radius, 150.0), "%s: still a QUERY_RADIUS circle (150)" % scene_path.get_file().get_basename())


func _section_burst_ledger() -> void:
	# Impact bursts: ledger resolver, cast-time fill, payload duplicate
	var player := fx.fresh_player()
	var ability := fx.mount_arcane_bolt(player)
	var sc := ability.stats_container
	var shared_a := _make_burst(&"test_shared_burst", ImpactBurstDefinition.Trigger.ON_HIT)
	var shared_b := _make_burst(&"test_shared_burst", ImpactBurstDefinition.Trigger.ON_CRIT)
	var burst_card_a := UpgradeDefinition.new()
	burst_card_a.upgrade_id = "test_burst_card_a"
	burst_card_a.scope = UpgradeDefinition.ScopeType.LOCAL_SLOT
	burst_card_a.restrict_to_slot = 1
	burst_card_a.impact_burst_payload = shared_a
	var burst_card_b := UpgradeDefinition.new()
	burst_card_b.upgrade_id = "test_burst_card_b"
	burst_card_b.scope = UpgradeDefinition.ScopeType.LOCAL_SLOT
	burst_card_b.restrict_to_slot = 1
	burst_card_b.impact_burst_payload = shared_b
	var no_tags: Array[Tags.Type] = []
	check(player.run_ledger_component.get_impact_bursts(1, no_tags).is_empty(), "ledger: no bursts before a burst card is bought")
	player.run_ledger_component.log_purchase(burst_card_a)
	player.run_ledger_component.log_purchase(burst_card_b)
	var slot_bursts := player.run_ledger_component.get_impact_bursts(1, no_tags)
	check(slot_bursts.size() == 1 and slot_bursts[0] == shared_a, "ledger: burst resolves for its slot, deduplicated by burst_id (first in purchase order wins)")
	check(player.run_ledger_component.get_impact_bursts(2, no_tags).is_empty(), "ledger: a slot-1 burst does not leak to slot 2")
	var cast_payload := CombatCalculations.generate_hit_payload(player, sc, ability.tag_component)
	check(cast_payload.impact_bursts.size() == 1 and cast_payload.impact_bursts[0] == shared_a and not cast_payload.is_burst, "cast time: impact_bursts filled from the ledger, is_burst false")
	cast_payload.is_burst = true
	var cast_copy := cast_payload.duplicate() as CombatPayload
	check(cast_copy.impact_bursts.size() == 1 and cast_copy.impact_bursts[0] == shared_a and cast_copy.is_burst, "payload.duplicate keeps impact_bursts and is_burst")


const FIRE_CARD := "res://resources/infusions/inf_fire_upgrade_def.tres"
const FROST_CARD := "res://resources/infusions/inf_frost_upgrade_def.tres"
const LIGHTNING_CARD := "res://resources/infusions/inf_lightning_upgrade_def.tres"
const WIND_CARD := "res://resources/infusions/inf_wind_upgrade_def.tres"
const EARTH_CARD := "res://resources/infusions/inf_earth_upgrade_def.tres"


## Sockets Fire and Frost `count` times each into slot 1 through the ledger.
func _socket_fire_and_frost(player: Player, count: int) -> void:
	var fire := load(FIRE_CARD) as UpgradeDefinition
	var frost := load(FROST_CARD) as UpgradeDefinition
	for i in range(count):
		player.run_ledger_component.log_slot_specific_purchase(fire, 1)
		player.run_ledger_component.log_slot_specific_purchase(frost, 1)


func _infusion_card(id: String, category: UpgradeDefinition.Category, element: Tags.Type) -> UpgradeDefinition:
	var card := UpgradeDefinition.new()
	card.upgrade_id = id
	card.category = category
	card.target_tags = [element]
	return card


func _section_infusion_level_definition() -> void:
	var player := fx.fresh_player()
	var ability := fx.mount_arcane_bolt(player)
	var ledger := player.run_ledger_component
	var fire := load(FIRE_CARD) as UpgradeDefinition
	var frost := load(FROST_CARD) as UpgradeDefinition
	var earth := load(EARTH_CARD) as UpgradeDefinition
	var second_fire := _infusion_card("test_second_fire", UpgradeDefinition.Category.INFUSION, Tags.Type.FIRE)
	for i in range(2):
		ledger.log_slot_specific_purchase(fire, 1)
		ledger.log_slot_specific_purchase(second_fire, 1)
	ledger.log_slot_specific_purchase(fire, 2)
	for i in range(3):
		ledger.log_slot_specific_purchase(earth, 1)
	ledger.log_slot_specific_purchase(frost, 2)
	check(ledger.get_infusion_level(1, Tags.Type.FIRE) == 4 and ledger.get_infusion_level(2, Tags.Type.FIRE) == 1 \
			and ledger.get_infusion_level(1, Tags.Type.EARTH) == 3 and ledger.get_infusion_level(2, Tags.Type.FROST) == 1 \
			and ledger.get_infusion_level(1, Tags.Type.FROST) == 0 and ledger.get_infusion_level(2, Tags.Type.EARTH) == 0,
			"infusion level: sum of the tiers of that element's cards in that slot (duplicates, two cards, two slots)")
	var expected_slot_1: Array[int] = [4, 0, 0, 0, 3]
	check(ledger.get_infusion_levels(1) == expected_slot_1, "infusion levels: slot 1 reads [fire 4, earth 3] from the ledger")
	check(ability.infusion_tracker_component.infusion_levels == expected_slot_1, "infusion level: the ability's tracker reports the same levels as the ledger")


func _section_tracker_reads_ledger() -> void:
	var player := fx.fresh_player()
	var ability := fx.mount_arcane_bolt(player)
	var ledger := player.run_ledger_component
	var tr := ability.infusion_tracker_component
	var fire := load(FIRE_CARD) as UpgradeDefinition
	var T1 := EvolutionGateComponent.EvolutionState.TIER_1_BASE
	var zeros: Array[int] = [0, 0, 0, 0, 0]
	check(tr.infusion_levels == zeros and tr.is_element_socket_allowed(Tags.Type.FIRE, T1, false), "tracker: reads zero from an empty ledger")
	ledger.log_slot_specific_purchase(fire, 1)
	check(tr.infusion_levels[0] == 1 and tr.last_calculated_total_infusions == 1, "tracker holds no data of its own: a purchase made directly through the ledger changes its answer")
	ledger.log_slot_specific_purchase(fire, 1)
	ledger.log_slot_specific_purchase(fire, 1)
	check(not tr.is_element_socket_allowed(Tags.Type.FIRE, T1, false), "tracker: the soft cap follows the ledger level (Fire 3)")
	ledger.restore_state({}, [])
	check(tr.infusion_levels == zeros and tr.is_element_socket_allowed(Tags.Type.FIRE, T1, false), "tracker: clearing the ledger clears what the tracker reports")


func _section_infusion_category() -> void:
	var player := fx.fresh_player()
	var ability := fx.mount_arcane_bolt(player)
	var ledger := player.run_ledger_component
	var prefixed_but_general := _infusion_card("inf_fake", UpgradeDefinition.Category.GENERAL, Tags.Type.FIRE)
	var infusion_without_prefix := _infusion_card("plain_fire", UpgradeDefinition.Category.INFUSION, Tags.Type.FIRE)
	check(not prefixed_but_general.is_infusion() and prefixed_but_general.get_infusion_element() == Tags.Type.NONE, "category: an inf_ id with category GENERAL is not an infusion")
	check(infusion_without_prefix.is_infusion() and infusion_without_prefix.get_infusion_element() == Tags.Type.FIRE, "category: category INFUSION without the inf_ prefix is an infusion")
	ledger.log_slot_specific_purchase(prefixed_but_general, 1)
	ledger.log_slot_specific_purchase(prefixed_but_general, 1)
	check(ledger.get_infusion_level(1, Tags.Type.FIRE) == 0 and not ability.tag_component.has_tag(Tags.Type.FIRE), "category: an inf_ id with category GENERAL adds no level and no element tag")
	ledger.log_slot_specific_purchase(infusion_without_prefix, 1)
	check(ledger.get_infusion_level(1, Tags.Type.FIRE) == 1 and ability.tag_component.has_tag(Tags.Type.FIRE), "category: an INFUSION card without the prefix adds a level and the element tag")


func _section_purchase_key() -> void:
	var cases: Array = [["inf_fire", 1], ["test_burst_card_a", 0], ["a_b_c_9", 4], ["x1_2_3", 12], ["inf_earth", 3], ["overclock", 2]]
	var round_trips := true
	for entry in cases:
		var parsed := PurchaseKey.parse(PurchaseKey.make(entry[0], entry[1]))
		round_trips = round_trips and parsed.get("upgrade_id", "") == entry[0] and parsed.get("slot", -1) == entry[1]
	check(round_trips, "PurchaseKey: parse(make(id, slot)) round-trips ids with underscores and digits")
	check(PurchaseKey.make("inf_fire", 1) == "inf_fire::slot_1", "PurchaseKey: the stored key format is unchanged")
	check(PurchaseKey.parse("player_move_speed").is_empty() and PurchaseKey.parse("x::slot_").is_empty() and PurchaseKey.parse("::slot_1").is_empty() and PurchaseKey.parse("x::slot_a").is_empty(), "PurchaseKey: plain ids and malformed keys do not parse")


func _section_run_state_round_trip() -> void:
	# The same capture and restore a room change or the F3 respawn runs
	var player := fx.fresh_player()
	var ability := fx.mount_arcane_bolt(player)
	var ledger := player.run_ledger_component
	var fire := load(FIRE_CARD) as UpgradeDefinition
	var earth := load(EARTH_CARD) as UpgradeDefinition
	ledger.log_slot_specific_purchase(fire, 1)
	ledger.log_slot_specific_purchase(fire, 1)
	ledger.log_slot_specific_purchase(earth, 1)
	var before: Array[int] = ability.infusion_tracker_component.infusion_levels
	player.capture_run_state()
	check(RunSession.has_player_snapshot() and not RunSession.state.ability_states[1].has("infusion_levels"), "run state: capture writes a snapshot with no separate infusion levels")
	ledger.restore_state({}, [])
	player.ability_container.remove_ability_by_slot(1)
	player._restore_run_state()
	var restored := player.ability_container.get_ability_by_slot(1)
	check(is_instance_valid(restored) and restored.infusion_tracker_component.infusion_levels == before and ledger.get_infusion_levels(1) == before, "run state round trip: levels survive and equal the ledger's")


func _section_real_infusion_categories() -> void:
	var all_infusions := true
	for path in [FIRE_CARD, FROST_CARD, LIGHTNING_CARD, WIND_CARD, EARTH_CARD]:
		var card := load(path) as UpgradeDefinition
		all_infusions = all_infusions and card.category == UpgradeDefinition.Category.INFUSION and card.is_infusion()
	check(all_infusions, "category: the five real infusion definitions all have category INFUSION")


func _section_infusion_tracker() -> void:
	var player := fx.fresh_player()
	var ability := fx.mount_arcane_bolt(player)
	var tr := ability.infusion_tracker_component
	var gate := ability.evolution_gate_component
	var T1 := EvolutionGateComponent.EvolutionState.TIER_1_BASE
	var levels: Array[int] = [3, 3, 0, 0, 0]
	_socket_fire_and_frost(player, 3)
	check(not tr.is_element_socket_allowed(Tags.Type.FIRE, T1, false), "fire at soft cap refused")
	check(tr.is_element_socket_allowed(Tags.Type.FIRE, T1, true), "overclock lifts per-element cap")
	check(not tr.is_element_socket_allowed(Tags.Type.EARTH, T1, true), "overclock keeps element-count limit")
	check(gate.is_offer_eligible(levels), "offer eligible at fire3+frost3")
	check(gate.meets_recipe([Tags.Type.FIRE, Tags.Type.FROST], levels), "recipe fire+frost met")
	check(not gate.meets_recipe([Tags.Type.FIRE, Tags.Type.EARTH], levels), "recipe fire+earth not met")
	check(not gate.meets_recipe([], levels), "empty recipe never met")


func _section_offer_draft() -> void:
	var player := fx.fresh_player()
	var ability := fx.mount_arcane_bolt(player)
	var gate := ability.evolution_gate_component
	var mgr := fx.get_upgrade_manager()
	emitted.clear()
	var listener := func(o: Array[UpgradeChoice]) -> void: emitted.append(o)
	_eb.upgrade_options_ready.connect(listener)
	_socket_fire_and_frost(player, 3)
	check(mgr._find_next_offer_slot(player) == 1, "offer slot found")
	mgr._try_process_next_level_up()
	check(emitted.size() == 1, "offer draft emitted")
	if emitted.size() == 1:
		var opts: Array = emitted[0]
		check(opts.size() == 1 and opts[0].is_forced_offer and opts[0].definition.upgrade_id == "overclock", "offer is only Overclock, forced")
		check(tree.paused, "game tree.paused during offer")
		_eb.upgrade_selected.emit(opts[0])
		check(gate.is_permanently_overclocked, "overclock applied")
		check(player.run_ledger_component.purchase_registry.get("overclock::slot_1", 0) == 1, "overclock logged under slot key")
		check(mgr._find_next_offer_slot(player) == 0, "no re-offer after overclock")
	tree.paused = false
	_eb.upgrade_options_ready.disconnect(listener)


func _section_pending_drafts() -> void:
	fx.fresh_player()
	var mgr := fx.get_upgrade_manager()
	mgr._level_up_queue.append(7)
	mgr._sync_pending_to_run_state()
	var seven: Array[int] = [7]
	check(RunSession.state.pending_draft_levels == seven, "pending levels written to RunSession")
	mgr._level_up_queue.clear()
	mgr._sync_pending_to_run_state()
	check(RunSession.state.pending_draft_levels.is_empty(), "pending cleared")


# ---------------------------------------------------------------------------------------------
# Task L3: UpgradeDefinition.stat_modifiers and its bridge from the old fields
# ---------------------------------------------------------------------------------------------

func _l3_modifier(type: StatModifier.Type, value: float, stat: Stat.Type) -> StatModifier:
	var modifier := StatModifier.new()
	modifier.type = type
	modifier.value = value
	modifier.target_stat_type = stat
	return modifier


func _l3_card(id: String) -> UpgradeDefinition:
	var card := UpgradeDefinition.new()
	card.upgrade_id = id
	card.scope = UpgradeDefinition.ScopeType.LOCAL_SLOT
	card.restrict_to_slot = 1
	return card


func _l3_ledger() -> RunLedgerComponent:
	var ledger := RunLedgerComponent.new()
	fx.track(ledger)
	return ledger


func _section_stat_modifier_list() -> void:
	var no_tags: Array[Tags.Type] = []
	var damage := Stat.Type.BASE_DAMAGE
	var cooldown := Stat.Type.COOLDOWN
	var crit_multiplier := Stat.Type.CRIT_MULTIPLIER
	var untouched := Stat.Type.DURATION

	# Totals from the stat_modifiers list at tiers 1 to 3, for every modifier type.
	var flat := _l3_modifier(StatModifier.Type.FLAT, 2.0, damage)
	var percent := _l3_modifier(StatModifier.Type.PERCENT, 0.1, damage)
	var multiplicative := _l3_modifier(StatModifier.Type.MULTIPLICATIVE, 0.2, crit_multiplier)
	var other_flat := _l3_modifier(StatModifier.Type.FLAT, 0.5, cooldown)
	var new_card := _l3_card("test_l3_new")
	new_card.stat_modifiers = [flat, percent, multiplicative, other_flat]
	var new_ledger := _l3_ledger()
	for tier in [1, 2, 3]:
		new_ledger.log_purchase(new_card)
	check(new_ledger.get_modifier_totals(1, no_tags, damage) == Vector3(6.0, 0.3, 1.0) and is_equal_approx(new_ledger.get_modifier_totals(1, no_tags, crit_multiplier).z, pow(1.2, 3.0)), "stat_modifiers: tier 3 totals are flat 6, percent 0.3 and 1.2^3")

	# StatsContainer dirties the stat of every entry of a card that uses only stat_modifiers.
	var invalidation_card := _l3_card("test_l3_invalidation")
	invalidation_card.stat_modifiers = [flat, other_flat, multiplicative]
	var invalidation_ledger := _l3_ledger()
	var container := fx.make_stats({damage: 1.0, cooldown: 1.0, crit_multiplier: 1.5, untouched: 3.0}, 1, invalidation_ledger)
	invalidation_ledger.log_purchase(invalidation_card)
	check(container.stats[damage].is_dirty and container.stats[cooldown].is_dirty and container.stats[crit_multiplier].is_dirty, "invalidation: every stat targeted by the stat_modifiers list is dirtied")
	check(not container.stats[untouched].is_dirty, "invalidation: a stat no entry targets stays clean")
	check(is_equal_approx(container.get_final_stat_value(damage), 3.0) and is_equal_approx(container.get_final_stat_value(cooldown), 1.5), "invalidation: the next read applies the card")

	# A card with no modifiers at all contributes nothing and dirties nothing.
	var empty_card := _l3_card("test_l3_empty")
	var empty_ledger := _l3_ledger()
	var empty_container := fx.make_stats({damage: 1.0, cooldown: 1.0}, 1, empty_ledger)
	empty_ledger.log_purchase(empty_card)
	check(empty_card.stat_modifiers.is_empty(), "empty card: stat_modifiers is empty")
	check(empty_ledger.get_modifier_totals(1, no_tags, damage) == Vector3(0.0, 0.0, 1.0), "empty card: contributes nothing to totals")
	check(not empty_container.stats[damage].is_dirty and not empty_container.stats[cooldown].is_dirty, "empty card: dirties no stat")

	# Status resolution through the shared helper: two distinct cards, one effect_id, first in purchase order wins.
	var first_status := StatusEffect.new()
	first_status.effect_id = "test_l3_status"
	var second_status := StatusEffect.new()
	second_status.effect_id = "test_l3_status"
	var status_card_a := _l3_card("test_l3_status_a")
	status_card_a.status_effect_payload = first_status
	var status_card_b := _l3_card("test_l3_status_b")
	status_card_b.status_effect_payload = second_status
	var status_ledger := _l3_ledger()
	status_ledger.log_purchase(status_card_b)
	status_ledger.log_purchase(status_card_a)
	var resolved := status_ledger.get_status_effects(1, no_tags)
	check(resolved.size() == 1 and resolved[0] == second_status, "statuses: two cards with one effect_id give the first purchased card's status")
	check(status_ledger.get_status_effects(2, no_tags).is_empty(), "statuses: not offered to another slot")


# ---------------------------------------------------------------------------------------------
# Task L4: the six real cards carry their modifiers in stat_modifiers (structural checks)
# ---------------------------------------------------------------------------------------------

func _section_real_cards_use_stat_modifiers() -> void:
	var paths: Array[String] = [
		"res://resources/infusions/inf_fire_upgrade_def.tres",
		"res://resources/infusions/inf_frost_upgrade_def.tres",
		"res://resources/infusions/inf_earth_upgrade_def.tres",
		"res://resources/infusions/inf_lightning_upgrade_def.tres",
		"res://resources/infusions/inf_wind_upgrade_def.tres",
		"res://resources/entities/player/player_move_speed_upgrade_def.tres",
	]
	for path in paths:
		var card := load(path) as UpgradeDefinition
		var card_name := path.get_file().get_basename()
		check(card != null and not card.stat_modifiers.is_empty(), "%s: stat_modifiers is set" % card_name)


# ---------------------------------------------------------------------------------------------
# Task L6a: stat-card invalidation follows the ledger; stat queries ignore temporary tags
# ---------------------------------------------------------------------------------------------

func _l6_mount(player: Player, slot: int, tags: Array[Tags.Type]) -> Ability:
	var data := (load(Fixtures.ARCANE_BOLT_DATA) as AbilityData).duplicate() as AbilityData
	data.slot_index = slot as AbilityData.Role
	data.structural_tags = tags
	return player.ability_container.add_ability_from_data(data)


func _l6_ints(tags: Array[Tags.Type]) -> Array:
	var out: Array = []
	for tag in tags:
		out.append(int(tag))
	return out


func _section_invalidation_follows_ledger() -> void:
	var damage := Stat.Type.BASE_DAMAGE
	var no_fire: Array[Tags.Type] = [Tags.Type.METAMAGIC, Tags.Type.PROJECTILE]
	var fire_infusion := load(FIRE_CARD) as UpgradeDefinition

	# A slot-specific purchase of a non-infusion card updates the cached stat, whatever the card's scope.
	var scopes := {
		"CHARACTER_CORE": [UpgradeDefinition.ScopeType.CHARACTER_CORE, 0],
		"LOCAL_SLOT restricted to another slot": [UpgradeDefinition.ScopeType.LOCAL_SLOT, 2],
		"LOCAL_SLOT restricted to the same slot": [UpgradeDefinition.ScopeType.LOCAL_SLOT, 1],
	}
	for scope_name in scopes:
		var player := fx.fresh_player()
		var ability := fx.mount_arcane_bolt(player)
		var card := _l3_card("test_l6_slot_specific")
		card.scope = scopes[scope_name][0]
		card.restrict_to_slot = scopes[scope_name][1]
		card.stat_modifiers = [_l3_modifier(StatModifier.Type.PERCENT, 0.5, damage)]
		var before := ability.stats_container.get_final_stat_value(damage)
		player.run_ledger_component.log_slot_specific_purchase(card, 1)
		var cached := ability.stats_container.get_final_stat_value(damage)
		ability.stats_container.invalidate_all_caches()
		var recomputed := ability.stats_container.get_final_stat_value(damage)
		check(is_equal_approx(before, 1.0) and is_equal_approx(cached, 1.5) and is_equal_approx(cached, recomputed), "slot-specific non-infusion card (%s): cached stat equals the recomputed value right after the purchase" % scope_name)

	# No needless invalidation: a card restricted to slot 2, bought plainly, leaves slot 1 clean.
	var other_player := fx.fresh_player()
	var slot_one := fx.mount_arcane_bolt(other_player)
	var slot_two_card := _l3_card("test_l6_slot_two")
	slot_two_card.restrict_to_slot = 2
	slot_two_card.stat_modifiers = [_l3_modifier(StatModifier.Type.PERCENT, 0.5, damage)]
	slot_one.stats_container.get_final_stat_value(damage)
	other_player.run_ledger_component.log_purchase(slot_two_card)
	check(not slot_one.stats_container.stats[damage].is_dirty, "a plain card restricted to slot 2 does not dirty slot 1")
	check(is_equal_approx(slot_one.stats_container.get_final_stat_value(damage), 1.0), "a plain card restricted to slot 2 does not change slot 1")

	# Temporary tags: in the active tags (after the permanent ones), never in the permanent tags.
	var tag_player := fx.fresh_player()
	var tagged := _l6_mount(tag_player, 1, no_fire)
	tag_player.run_ledger_component.log_slot_specific_purchase(fire_infusion, 1)
	var tags := tagged.tag_component
	var permanent_before := _l6_ints(tags.get_permanent_tags())
	tags.add_temporary_tag(Tags.Type.EARTH)
	check(tags.get_active_tags().has(Tags.Type.EARTH) and tags.has_tag(Tags.Type.EARTH), "temporary tag: in the active tags")
	check(not tags.get_permanent_tags().has(Tags.Type.EARTH) and not tags.has_permanent_tag(Tags.Type.EARTH), "temporary tag: not in the permanent tags")
	check(_l6_ints(tags.get_permanent_tags()) == permanent_before and permanent_before == [int(Tags.Type.METAMAGIC), int(Tags.Type.PROJECTILE), int(Tags.Type.FIRE)], "permanent tags are base then infusion tags")
	check(_l6_ints(tags.get_active_tags()) == permanent_before + [int(Tags.Type.EARTH)], "active tags keep the order: base, infusion, temporary")
	tags.remove_temporary_tag(Tags.Type.EARTH)
	check(not tags.get_active_tags().has(Tags.Type.EARTH), "temporary tag: gone from the active tags after remove_temporary_tag")

	# A tag-scoped stat card follows permanent tags only.
	var scoped_player := fx.fresh_player()
	var scoped := _l6_mount(scoped_player, 1, no_fire)
	var tag_card := _l3_card("test_l6_tag_card")
	tag_card.scope = UpgradeDefinition.ScopeType.GLOBAL_TAG_MATCH
	tag_card.target_tags = [Tags.Type.FIRE]
	tag_card.stat_modifiers = [_l3_modifier(StatModifier.Type.PERCENT, 0.5, damage)]
	scoped_player.run_ledger_component.log_purchase(tag_card)
	scoped.tag_component.add_temporary_tag(Tags.Type.FIRE)
	scoped.stats_container.invalidate_all_caches()
	check(is_equal_approx(scoped.stats_container.get_final_stat_value(damage), 1.0), "tag card: a temporary matching tag does not switch it on")
	scoped_player.run_ledger_component.log_slot_specific_purchase(fire_infusion, 1)
	check(is_equal_approx(scoped.stats_container.get_final_stat_value(damage), 1.5), "tag card: a permanent matching tag (infusion) switches it on")
	scoped.tag_component.remove_temporary_tag(Tags.Type.FIRE)
	var fire_base: Array[Tags.Type] = [Tags.Type.PROJECTILE, Tags.Type.FIRE]
	var base_ability := _l6_mount(scoped_player, 3, fire_base)
	base_ability.stats_container.invalidate_all_caches()
	check(is_equal_approx(base_ability.stats_container.get_final_stat_value(damage), 1.5), "tag card: a permanent matching tag (base tag) switches it on")

	# Statuses and bursts ignore a temporary matching tag.
	var granted_player := fx.fresh_player()
	var granted := _l6_mount(granted_player, 1, no_fire)
	var tag_status := StatusEffect.new()
	tag_status.effect_id = "test_l6_status"
	var tag_burst := ImpactBurstDefinition.new()
	tag_burst.burst_id = &"test_l6_burst"
	var grant_card := _l3_card("test_l6_grant_card")
	grant_card.scope = UpgradeDefinition.ScopeType.GLOBAL_TAG_MATCH
	grant_card.target_tags = [Tags.Type.EARTH]
	grant_card.status_effect_payload = tag_status
	grant_card.impact_burst_payload = tag_burst
	granted_player.run_ledger_component.log_purchase(grant_card)
	granted.tag_component.add_temporary_tag(Tags.Type.EARTH)
	check(granted.stats_container.get_status_effects().is_empty(), "status card: a temporary matching tag does not grant the status")
	check(granted.stats_container.get_impact_bursts().is_empty(), "burst card: a temporary matching tag does not grant the burst")
	granted.tag_component.remove_temporary_tag(Tags.Type.EARTH)
	var earth_base: Array[Tags.Type] = [Tags.Type.PROJECTILE, Tags.Type.EARTH]
	var permanent_ability := _l6_mount(granted_player, 3, earth_base)
	check(permanent_ability.stats_container.get_status_effects().size() == 1 and permanent_ability.stats_container.get_impact_bursts().size() == 1, "status and burst cards: a permanent matching tag grants them")

	# An infusion purchase still invalidates every cache of its slot.
	var infusion_player := fx.fresh_player()
	var infused := fx.mount_arcane_bolt(infusion_player)
	infused.stats_container.get_final_stat_value(damage)
	check(not infused.stats_container.stats[damage].is_dirty, "infusion test setup: the stat is clean after a read")
	infusion_player.run_ledger_component.log_slot_specific_purchase(fire_infusion, 1)
	check(infused.stats_container.stats[damage].is_dirty, "an infusion purchase still dirties every stat of its slot")


# ---------------------------------------------------------------------------------------------
# Task N1: the debug panel's actions (DebugActions, DebugStatusWatcher, DebugHub)
# ---------------------------------------------------------------------------------------------

const DBG_OVERCLOCK_CARD := "res://resources/infusions/overclock_upgrade_def.tres"
const DBG_UNLOCK_CARD := "res://resources/abilities/arcane_bolt/arcane_bolt_upgrade_def.tres"
const DBG_MOVE_SPEED_CARD := "res://resources/entities/player/player_move_speed_upgrade_def.tres"


func _dbg_choice(definition: UpgradeDefinition, slot: int) -> UpgradeChoice:
	var tracker := UpgradeTracker.new()
	tracker.definition = definition
	tracker.max_purchases = 5
	var choice := UpgradeChoice.new()
	choice.source_tracker = tracker
	choice.target_slot_index = slot
	return choice


## Everything an infusion grant could change in `slot`, for before / after comparisons.
func _dbg_snapshot(player: Player, slot: int) -> Dictionary:
	var ledger := player.run_ledger_component
	var ability := player.ability_container.get_ability_by_slot(slot)
	var snap := {
		"registry": ledger.purchase_registry.duplicate(),
		"active_upgrades": ledger.active_upgrades.size(),
		"levels": ledger.get_infusion_levels(slot),
	}
	if is_instance_valid(ability):
		var tags := ability.tag_component.get_permanent_tags()
		snap["tags"] = _l6_ints(tags)
		snap["overclocked"] = ability.evolution_gate_component.is_permanently_overclocked
		snap["state"] = int(ability.evolution_gate_component.current_state)
		snap["duration_total"] = ledger.get_modifier_totals(slot, tags, Stat.Type.STATUS_DURATION)
		snap["ramp_total"] = ledger.get_modifier_totals(slot, tags, Stat.Type.STATUS_RAMP_CAP)
		snap["statuses"] = ledger.get_status_effects(slot, tags).size()
	return snap


func _section_debug_actions() -> void:
	var manager := fx.get_upgrade_manager()
	var core_card := load(DBG_MOVE_SPEED_CARD) as UpgradeDefinition
	var unlock_card := load(DBG_UNLOCK_CARD) as UpgradeDefinition

	# grantable_cards: includes the plain cards, excludes infusion / Overclock / evolution cards, no duplicate ids.
	var ids: Array[String] = []
	var excluded_found := false
	for entry in DebugActions.grantable_cards(manager):
		var definition: UpgradeDefinition = entry["definition"]
		ids.append(definition.upgrade_id)
		excluded_found = excluded_found or definition.is_infusion() or definition.payload_type == UpgradeDefinition.PayloadType.ABILITY_OVERCLOCK
	check(ids.has("player_move_speed") and ids.has("upgrade_arcane_bolt"), "grantable cards: include Player Movement and the Arcane Bolt unlock")
	check(not excluded_found and not ids.has("overclock") and not ids.has("inf_fire"), "grantable cards: no infusion or Overclock card")

	var saved_pool := manager.master_upgrade_pool.duplicate()
	var test_evolution := UpgradeDefinition.new()
	test_evolution.upgrade_id = "test_debug_evolution"
	test_evolution.payload_type = UpgradeDefinition.PayloadType.ABILITY_UNLOCK
	test_evolution.evolves_from = AbilityData.new()
	var test_unlock := UpgradeDefinition.new()
	test_unlock.upgrade_id = "test_debug_plain_unlock"
	test_unlock.payload_type = UpgradeDefinition.PayloadType.ABILITY_UNLOCK
	var extra_definitions: Array[UpgradeDefinition] = [test_evolution, test_unlock, core_card]
	var extra_profile := UpgradeBlueprintProfile.new()
	extra_profile.definition_bundle = extra_definitions
	manager.master_upgrade_pool.append(extra_profile)
	var with_extras: Array[String] = []
	for entry in DebugActions.grantable_cards(manager):
		with_extras.append(entry["definition"].upgrade_id)
	manager.master_upgrade_pool = saved_pool
	var unique_ids := true
	for id in with_extras:
		unique_ids = unique_ids and with_extras.count(id) == 1
	check(not with_extras.has("test_debug_evolution"), "grantable cards: an evolution card is excluded")
	check(with_extras.has("test_debug_plain_unlock"), "grantable cards: an unlock card without evolves_from is included")
	check(unique_ids, "grantable cards: no duplicate ids even when a card is in two profiles")

	# grant_card: a plain card raises its registry tier and its stat; the unlock mounts Arcane Bolt in slot 1.
	var player := fx.fresh_player()
	var speed_before := player.stats_container.get_final_stat_value(Stat.Type.MOVEMENT_SPEED)
	var tier_before: int = player.run_ledger_component.purchase_registry.get("player_move_speed", 0)
	DebugActions.grant_card(player, core_card, 5)
	check(player.run_ledger_component.purchase_registry.get("player_move_speed", 0) == tier_before + 1, "grant_card: Player Movement's plain registry tier goes up by 1")
	check(player.stats_container.get_final_stat_value(Stat.Type.MOVEMENT_SPEED) > speed_before, "grant_card: Player Movement raises the movement speed stat")
	DebugActions.grant_card(player, unlock_card, 1)
	var mounted := player.ability_container.get_ability_by_slot(1)
	check(is_instance_valid(mounted) and mounted.display_name == "Arcane Bolt", "grant_card: the Arcane Bolt unlock mounts Arcane Bolt in slot 1")

	# level_up: the progression component reports 100.0 experience. The player's progression is restored afterwards.
	player = fx.fresh_player()
	var progression := player.progression_component
	var saved_level := progression.current_level
	var saved_xp := progression.current_xp
	var saved_total := progression.total_accumulated_xp
	var gained: Array[float] = []
	var on_gained := func(amount: float, _total: float) -> void: gained.append(amount)
	progression.experience_gained.connect(on_gained)
	DebugActions.level_up(player)
	progression.experience_gained.disconnect(on_gained)
	progression.restore_state(saved_level, saved_xp, saved_total)
	check(gained.has(100.0), "level_up: experience_gained fires with 100.0")

	# apply_status_to_nearest
	var burn := load("res://resources/status_effects/burn.tres") as StatusEffect
	var detached: Array[Dictionary] = []
	for node in tree.root.find_children("*", "Enemy", true, false):
		detached.append({"enemy": node, "parent": node.get_parent()})
		node.get_parent().remove_child(node)
	check(not DebugActions.apply_status_to_nearest(tree, burn, 5.0, 3.0), "apply_status_to_nearest: false when there is no enemy")
	check(not DebugActions.apply_status_to_nearest(tree, null, 5.0, 3.0), "apply_status_to_nearest: false without an effect")
	var bat := _spawn_bat()
	check(DebugActions.apply_status_to_nearest(tree, burn, 5.0, 3.0), "apply_status_to_nearest: true with an enemy")
	check(bat.tag_component.has_tag(Tags.Type.BURNING), "apply_status_to_nearest: the enemy is burning")

	# DebugStatusWatcher.enabled silences the status lines
	await tree.process_frame
	await tree.process_frame
	DebugStatusWatcher.enabled = true
	var lines_before := DebugStatusWatcher.lines_logged
	DebugActions.apply_status_to_nearest(tree, burn, 5.0, 3.0)
	check(DebugStatusWatcher.lines_logged > lines_before, "status watcher: a refresh is logged while enabled")
	DebugStatusWatcher.enabled = false
	var lines_silent := DebugStatusWatcher.lines_logged
	DebugActions.apply_status_to_nearest(tree, burn, 5.0, 3.0)
	check(DebugStatusWatcher.lines_logged == lines_silent, "status watcher: nothing is logged while disabled")
	DebugStatusWatcher.enabled = true

	for item in detached:
		if is_instance_valid(item["enemy"]) and is_instance_valid(item["parent"]):
			item["parent"].add_child(item["enemy"])

	# The hub exists in the world, starts hidden, and F1 toggles it and rebuilds the grant list.
	var hub := world.get_node_or_null("DebugHub") as DebugHub
	check(hub != null and not hub.visible, "debug hub: exists in the world and starts hidden")
	if hub != null:
		var f1 := InputEventKey.new()
		f1.keycode = KEY_F1
		f1.pressed = true
		hub._unhandled_input(f1)
		check(hub.visible, "debug hub: F1 opens it")
		await tree.process_frame
		check(hub._grant_list.get_child_count() == DebugActions.grantable_cards(manager).size(), "debug hub: the grant list is rebuilt on open")
		hub._unhandled_input(f1)
		check(not hub.visible, "debug hub: F1 closes it")


func _section_debug_infusion_grant() -> void:
	var manager := fx.get_upgrade_manager()
	var fire := load(FIRE_CARD) as UpgradeDefinition
	var frost := load(FROST_CARD) as UpgradeDefinition
	var earth := load(EARTH_CARD) as UpgradeDefinition
	var overclock := load(DBG_OVERCLOCK_CARD) as UpgradeDefinition
	var fire_element := int(Tags.Type.FIRE)

	check(DebugActions.grantable_infusions(manager).size() == 5, "grantable infusions: the five real infusion cards")

	# 1. A legal grant
	var player := fx.fresh_player()
	var ability := fx.mount_arcane_bolt(player)
	var ledger := player.run_ledger_component
	check(DebugActions.grant_infusion(player, manager, fire, fire_element, 1) == "", "infusion grant: Fire into an empty slot is accepted")
	check(ledger.get_infusion_level(1, Tags.Type.FIRE) == 1, "infusion grant: the Fire level in the slot is +1")
	check(ability.tag_component.get_permanent_tags().has(Tags.Type.FIRE), "infusion grant: the slot gained the Fire tag")
	var burn_found := false
	for effect in ledger.get_status_effects(1, ability.tag_component.get_permanent_tags()):
		burn_found = burn_found or effect.effect_id == "burn"
	check(burn_found, "infusion grant: the slot now carries Burn")
	var granted_snapshot := _dbg_snapshot(player, 1)

	# 2. The same choice applied by hand gives the same state
	player = fx.fresh_player()
	fx.mount_arcane_bolt(player)
	var tracker := UpgradeTracker.new()
	tracker.definition = fire
	tracker.max_purchases = 5
	var by_hand := UpgradeChoice.new()
	by_hand.source_tracker = tracker
	by_hand.target_slot_index = 1
	player.apply_contextual_upgrade(by_hand)
	check(_dbg_snapshot(player, 1) == granted_snapshot, "infusion grant: identical ledger, levels, tags and totals to applying the choice by hand")

	# 3. Soft cap: the 4th Fire is refused and nothing changes
	player = fx.fresh_player()
	ability = fx.mount_arcane_bolt(player)
	for i in range(3):
		DebugActions.grant_infusion(player, manager, fire, fire_element, 1)
	var capped_snapshot := _dbg_snapshot(player, 1)
	var cap_reason := DebugActions.grant_infusion(player, manager, fire, fire_element, 1)
	check(capped_snapshot["levels"][0] == 3, "infusion grant: three Fire grants reach the soft cap of 3")
	check(not cap_reason.is_empty(), "infusion grant: a 4th Fire at the soft cap is refused with a reason")
	check(_dbg_snapshot(player, 1) == capped_snapshot, "infusion grant: a refused grant changes nothing")

	# 4. Element-count limit
	player = fx.fresh_player()
	fx.mount_arcane_bolt(player)
	DebugActions.grant_infusion(player, manager, fire, fire_element, 1)
	DebugActions.grant_infusion(player, manager, frost, int(Tags.Type.FROST), 1)
	var two_active := _dbg_snapshot(player, 1)
	check(not DebugActions.grant_infusion(player, manager, earth, int(Tags.Type.EARTH), 1).is_empty(), "infusion grant: a third new element is refused")
	check(_dbg_snapshot(player, 1) == two_active, "infusion grant: the refused third element changes nothing")
	check(DebugActions.grant_infusion(player, manager, fire, fire_element, 1) == "", "infusion grant: an element already present is still accepted")

	# 5. Overclock lifts the per-element cap to 15
	player = fx.fresh_player()
	fx.mount_arcane_bolt(player)
	for i in range(3):
		DebugActions.grant_infusion(player, manager, fire, fire_element, 1)
	player.apply_contextual_upgrade(_dbg_choice(overclock, 1))
	var accepted_above_cap := true
	for i in range(12):
		accepted_above_cap = accepted_above_cap and DebugActions.grant_infusion(player, manager, fire, fire_element, 1) == ""
	check(accepted_above_cap and player.run_ledger_component.get_infusion_level(1, Tags.Type.FIRE) == 15, "infusion grant: an Overclocked slot accepts Fire from 3 up to 15")
	var at_hard_cap := _dbg_snapshot(player, 1)
	check(not DebugActions.grant_infusion(player, manager, fire, fire_element, 1).is_empty() and _dbg_snapshot(player, 1) == at_hard_cap, "infusion grant: Fire 16 is refused and changes nothing")

	# 6. Empty and out-of-range slots
	player = fx.fresh_player()
	fx.mount_arcane_bolt(player)
	var before_bad := _dbg_snapshot(player, 1)
	for bad_slot in [2, 0, 5]:
		check(not DebugActions.grant_infusion(player, manager, fire, fire_element, bad_slot).is_empty(), "infusion grant: slot %d is refused with a reason" % bad_slot)
	check(_dbg_snapshot(player, 1) == before_bad and player.run_ledger_component.purchase_registry.is_empty(), "infusion grant: refused slots change nothing")

	# 7. can_grant_infusion is read-only
	player = fx.fresh_player()
	fx.mount_arcane_bolt(player)
	DebugActions.grant_infusion(player, manager, fire, fire_element, 1)
	var before_query := _dbg_snapshot(player, 1)
	DebugActions.can_grant_infusion(player, fire, fire_element, 1)
	DebugActions.can_grant_infusion(player, earth, int(Tags.Type.EARTH), 2)
	DebugActions.can_grant_infusion(player, earth, int(Tags.Type.EARTH), 0)
	check(_dbg_snapshot(player, 1) == before_query, "can_grant_infusion: leaves the ledger and the ability unchanged")

	# 8. Offer re-check: a grant that reaches the soft cap brings the forced offer draft.
	# Each accepted grant queues a deferred offer check, so let the earlier grants' checks run first.
	await tree.process_frame
	player = fx.fresh_player()
	ability = fx.mount_arcane_bolt(player)
	ledger = player.run_ledger_component
	for i in range(2):
		ledger.log_slot_specific_purchase(fire, 1)
	for i in range(3):
		ledger.log_slot_specific_purchase(frost, 1)
	emitted.clear()
	var listener := func(options: Array[UpgradeChoice]) -> void: emitted.append(options)
	_eb.upgrade_options_ready.connect(listener)
	check(not ability.evolution_gate_component.is_offer_eligible(ability.infusion_tracker_component.infusion_levels), "offer re-check: not eligible before the grant")
	DebugActions.grant_infusion(player, manager, fire, fire_element, 1)
	check(ability.evolution_gate_component.is_offer_eligible(ability.infusion_tracker_component.infusion_levels), "offer re-check: eligible after the grant reaches the soft cap")
	await tree.process_frame
	await tree.process_frame
	check(emitted.size() == 1 and emitted[0].size() > 0 and emitted[0][0].is_forced_offer, "offer re-check: the forced offer draft is presented after the grant")
	# While a draft is on screen, recheck_offers changes nothing
	var queue_before := manager._level_up_queue.duplicate()
	var presenting_before := manager._presenting_level
	var offer_flag_before := manager._is_offer_draft
	emitted.clear()
	manager.recheck_offers()
	await tree.process_frame
	await tree.process_frame
	check(emitted.is_empty() and manager._level_up_queue == queue_before and manager._presenting_level == presenting_before and manager._is_offer_draft == offer_flag_before and manager._is_presenting_ui, "offer re-check: does nothing while a draft is on screen")
	_eb.upgrade_options_ready.disconnect(listener)
	tree.paused = false

	# 9. A refused grant does not re-check offers (the slot is offer-eligible, so a re-check would present a draft)
	player = fx.fresh_player()
	ability = fx.mount_arcane_bolt(player)
	ledger = player.run_ledger_component
	for i in range(3):
		ledger.log_slot_specific_purchase(fire, 1)
		ledger.log_slot_specific_purchase(frost, 1)
	emitted.clear()
	var refused_listener := func(options: Array[UpgradeChoice]) -> void: emitted.append(options)
	_eb.upgrade_options_ready.connect(refused_listener)
	check(not DebugActions.grant_infusion(player, manager, fire, fire_element, 1).is_empty(), "refused grant: Fire 4 is refused")
	await tree.process_frame
	await tree.process_frame
	check(emitted.is_empty() and not manager._is_presenting_ui, "refused grant: no offer re-check ran")
	_eb.upgrade_options_ready.disconnect(refused_listener)

	# The panel's grant button runs the same code and reports the result
	player = fx.fresh_player()
	fx.mount_arcane_bolt(player)
	var hub := world.get_node_or_null("DebugHub") as DebugHub
	if hub != null:
		hub._refresh()
		var fire_index := -1
		for i in range(hub._element_picker.item_count):
			if hub._element_picker.get_item_text(i) == "FIRE":
				fire_index = i
		hub._element_picker.select(fire_index)
		hub._slot_picker.select(0)
		hub._on_grant_infusion_pressed()
		check(hub._infusion_result.text.begins_with("OK") and player.run_ledger_component.get_infusion_level(1, Tags.Type.FIRE) == 1, "debug hub: the grant button reports OK and grants")
		hub._slot_picker.select(1)
		hub._on_grant_infusion_pressed()
		check(hub._infusion_result.text.begins_with("Refused"), "debug hub: an empty slot is reported as refused")


# ---------------------------------------------------------------------------------------------
# Task N2: the Inspect tab (StateInspector, DebugHitRecorder, StatusEffectComponent.get_active_instances)
# ---------------------------------------------------------------------------------------------

## Every stat of `container` as [is_dirty, current_value, base_value, transient count], keyed by stat name.
func _insp_stat_state(container: StatsContainer) -> Dictionary:
	var state := {}
	for stat_type in container.stats:
		var stat: Stat = container.stats[stat_type]
		state[int(stat_type)] = [stat.is_dirty, stat.current_value, stat.base_value, stat.transient_modifiers.size()]
	return state


func _insp_row(rows: Array, stat_name: String) -> Dictionary:
	for row in rows:
		if row["name"] == stat_name:
			return row
	return {}


func _insp_all_states(rows: Array) -> Array:
	var states: Array = []
	for row in rows:
		states.append(row["cache_state"])
	return states


func _section_state_inspector() -> void:
	var manager := fx.get_upgrade_manager()
	var fire := load(FIRE_CARD) as UpgradeDefinition
	var frost := load(FROST_CARD) as UpgradeDefinition
	var burn := load("res://resources/status_effects/burn.tres") as StatusEffect
	var fire_tags: Array[Tags.Type] = [Tags.Type.PROJECTILE, Tags.Type.FIRE]

	var player := fx.fresh_player()
	var ability := fx.mount_arcane_bolt(player)
	var ledger := player.run_ledger_component

	# 2. Cache states: clean caches are "ok"; after invalidate_all_caches every ledger-backed row is "dirty".
	for stat_type in player.stats_container.stats:
		player.stats_container.get_final_stat_value(stat_type)
	for stat_type in ability.stats_container.stats:
		ability.stats_container.get_final_stat_value(stat_type)
	var description := StateInspector.describe(player, null, {})
	var all_ok := true
	for state in _insp_all_states(description["player"]["stats"]) + _insp_all_states(description["slots"][0]["stats"]):
		all_ok = all_ok and state == "ok"
	check(all_ok, "inspector: freshly read caches are all ok")

	# 1. Read-only: a stat left dirty stays dirty, nothing changes, no stat signal fires
	player.stats_container.invalidate_all_caches()
	ability.stats_container.invalidate_all_caches()
	var signal_count := [0]
	var count_signal := func(_a = null, _b = null) -> void: signal_count[0] += 1
	player.stats_container.stat_updated.connect(count_signal)
	ability.stats_container.stat_updated.connect(count_signal)
	for stat in player.stats_container.stats.values():
		stat.value_changed.connect(count_signal)
	for stat in ability.stats_container.stats.values():
		stat.value_changed.connect(count_signal)
	var before_core := _insp_stat_state(player.stats_container)
	var before_ability := _insp_stat_state(ability.stats_container)
	var before_registry := ledger.purchase_registry.duplicate()
	var before_upgrades := ledger.active_upgrades.size()
	description = StateInspector.describe(player, null, {})
	check(_insp_stat_state(player.stats_container) == before_core and _insp_stat_state(ability.stats_container) == before_ability, "inspector: describe leaves every stat's dirty flag, value, base and transient count unchanged")
	check(ledger.purchase_registry == before_registry and ledger.active_upgrades.size() == before_upgrades, "inspector: describe leaves the ledger unchanged")
	check(signal_count[0] == 0, "inspector: describe fires no stat_updated or value_changed signal")
	check(ability.stats_container.stats[Stat.Type.BASE_DAMAGE].is_dirty and _insp_row(description["slots"][0]["stats"], "BASE_DAMAGE")["cache_state"] == "dirty", "inspector: a stat left dirty stays dirty and its row says dirty")
	player.stats_container.stat_updated.disconnect(count_signal)
	ability.stats_container.stat_updated.disconnect(count_signal)
	for stat in player.stats_container.stats.values():
		stat.value_changed.disconnect(count_signal)
	for stat in ability.stats_container.stats.values():
		stat.value_changed.disconnect(count_signal)

	# 2b. A clean stat with a wrong cached value is a MISMATCH
	for stat_type in ability.stats_container.stats:
		ability.stats_container.get_final_stat_value(stat_type)
	var cooldown_stat: Stat = ability.stats_container.stats[Stat.Type.COOLDOWN]
	var real_cooldown := cooldown_stat.current_value
	cooldown_stat.current_value = real_cooldown + 5.0
	description = StateInspector.describe(player, null, {})
	check(_insp_row(description["slots"][0]["stats"], "COOLDOWN")["cache_state"] == "MISMATCH", "inspector: a clean stat with a wrong cached value says MISMATCH")
	check(StateInspector.to_text(description).contains("MISMATCH"), "inspector: to_text contains MISMATCH")
	cooldown_stat.current_value = real_cooldown
	description = StateInspector.describe(player, null, {})
	check(_insp_row(description["slots"][0]["stats"], "COOLDOWN")["cache_state"] == "ok", "inspector: the row is ok again after restoring the value")

	# 3. Totals shown equal the ledger's
	DebugActions.grant_infusion(player, manager, fire, int(Tags.Type.FIRE), 1)
	for stat_type in ability.stats_container.stats:
		ability.stats_container.get_final_stat_value(stat_type)
	description = StateInspector.describe(player, null, {})
	var duration_totals := ledger.get_modifier_totals(1, ability.tag_component.get_permanent_tags(), Stat.Type.STATUS_DURATION)
	var duration_row := _insp_row(description["slots"][0]["stats"], "STATUS_DURATION")
	check(duration_row["flat"] == duration_totals.x and duration_row["percent"] == duration_totals.y and duration_row["multiplicative"] == duration_totals.z, "inspector: the shown totals equal ledger.get_modifier_totals")
	check(duration_row["cache_state"] == "ok" and is_equal_approx(duration_row["cached"], 3.0), "inspector: the Fire grant shows in the stat row and the cache is ok")

	# 4. Infusion levels, applying cards, resolved statuses and tags after a Fire grant
	var slot_one: Dictionary = description["slots"][0]
	check(slot_one["infusion_levels"] == ["FIRE 1"], "inspector: shows Fire level 1")
	check(slot_one["cards"].size() == 1 and slot_one["cards"][0]["name"] == "Fire Infusion" and slot_one["cards"][0]["tier"] == 1 and slot_one["cards"][0]["category"] == "INFUSION", "inspector: lists the Fire card with its tier and category")
	check(slot_one["statuses"] == ["burn"], "inspector: lists the Burn effect_id")
	check(slot_one["permanent_tags"].has("FIRE") and slot_one["active_tags"].has("FIRE"), "inspector: the Fire tag is in the permanent and active tags")

	# 5. Offer eligibility equals the gate's own predicate, below and at the soft cap
	var gate := ability.evolution_gate_component
	check(slot_one["offer_eligible"] == gate.is_offer_eligible(ledger.get_infusion_levels(1)) and not slot_one["offer_eligible"], "inspector: offer eligibility below the soft cap matches the gate")
	for i in range(2):
		ledger.log_slot_specific_purchase(fire, 1)
	for i in range(3):
		ledger.log_slot_specific_purchase(frost, 1)
	description = StateInspector.describe(player, null, {})
	check(description["slots"][0]["offer_eligible"] == gate.is_offer_eligible(ledger.get_infusion_levels(1)) and description["slots"][0]["offer_eligible"], "inspector: offer eligibility at the soft cap matches the gate")

	# 6. Empty slots
	check(description["slots"][1]["empty"] and StateInspector.to_text(description).contains("Slot 2: empty"), "inspector: an empty slot prints Slot 2: empty")
	check(StateInspector.to_text(StateInspector.describe(null, null, {})) == "no player", "inspector: no player gives a plain message")

	# 11. to_text is deterministic
	check(StateInspector.to_text(description) == StateInspector.to_text(description), "inspector: to_text gives identical text for the same description")

	# 7. StatusEffectComponent.get_active_instances
	var bat := _spawn_bat()
	var component := bat.status_effect_component
	check(component.get_active_instances().is_empty(), "get_active_instances: empty on a fresh component")
	component.apply_effect(burn, 5.0, 3.0)
	var instances := component.get_active_instances()
	check(instances.size() == 1 and instances[0].template.effect_id == burn.effect_id, "get_active_instances: returns the Burn instance after apply_effect")
	instances.clear()
	check(component.get_active_instances().size() == 1, "get_active_instances: changing the returned array leaves the component unchanged")

	# 8. The nearest enemy's status rows match the live instance
	description = StateInspector.describe(player, bat, {})
	var live := component.get_active_instances()[0]
	var enemy_status: Dictionary = description["enemy"]["statuses"][0]
	check(enemy_status["effect_id"] == live.template.effect_id and enemy_status["time_remaining"] == live.time_remaining and enemy_status["stacks"] == live.stacks and enemy_status["dot_damage"] == live.dot_damage and enemy_status["duration_bonus"] == live.duration_bonus, "inspector: the enemy's status row matches its live instance")
	check(StateInspector.to_text(description).contains("Nearest enemy: %s" % bat.name), "inspector: the text names the nearest enemy")

	# 9. Hit recorder (the hub's own recorder in the world)
	var hub := world.get_node_or_null("DebugHub") as DebugHub
	check(hub != null and is_instance_valid(hub._hit_recorder), "hit recorder: the hub owns one")
	if hub != null:
		var recorder := hub._hit_recorder
		recorder.clear()
		var second := _l6_mount(player, 2, fire_tags)
		await tree.process_frame
		await tree.process_frame
		var payload := CombatPayload.new()
		payload.stats_container_id = ability.stats_container.get_instance_id()
		payload.final_damage = 7.0
		payload.is_critical_hit = true
		payload.dot_damage_snapshot = 2.5
		var payload_statuses: Array[StatusEffect] = [burn]
		payload.status_effects_to_apply = payload_statuses
		bat.hurtbox_component.take_hit(payload)
		var hits := recorder.get_hits()
		check(hits.size() == 1 and hits.has(1), "hit recorder: one entry, for slot 1")
		if hits.has(1):
			check(hits[1]["final_damage"] == 7.0 and hits[1]["is_critical_hit"] and hits[1]["status_ids"] == [burn.effect_id] and hits[1]["dot_damage_snapshot"] == 2.5 and hits[1]["is_burst"] == false, "hit recorder: the entry has the right damage, crit, status ids and snapshot")
		payload.final_damage = 99.0
		check(recorder.get_hits()[1]["final_damage"] == 7.0, "hit recorder: changing the original payload later does not change the record")
		var returned := recorder.get_hits()
		returned[1]["final_damage"] = 123.0
		check(recorder.get_hits()[1]["final_damage"] == 7.0, "hit recorder: the getter returns a copy")

		var stranger := CombatPayload.new()
		stranger.stats_container_id = 4242
		stranger.final_damage = 55.0
		bat.hurtbox_component.take_hit(stranger)
		check(recorder.get_hits().size() == 1 and recorder.get_hits()[1]["final_damage"] == 7.0, "hit recorder: a hit from an unrelated source records nothing")

		var replacement := CombatPayload.new()
		replacement.stats_container_id = ability.stats_container.get_instance_id()
		replacement.final_damage = 8.0
		bat.hurtbox_component.take_hit(replacement)
		check(recorder.get_hits().size() == 1 and recorder.get_hits()[1]["final_damage"] == 8.0, "hit recorder: a second hit from the same slot replaces the first")

		var other_slot := CombatPayload.new()
		other_slot.stats_container_id = second.stats_container.get_instance_id()
		other_slot.final_damage = 9.0
		other_slot.is_burst = true
		bat.hurtbox_component.take_hit(other_slot)
		var both := recorder.get_hits()
		check(both.size() == 2 and both[1]["final_damage"] == 8.0 and both[2]["final_damage"] == 9.0 and both[2]["is_burst"], "hit recorder: hits from two slots keep both (a burst payload is recorded too)")

		# The text shows the last hit with its age
		var shown_hits := recorder.get_hits()
		shown_hits[1]["age_s"] = 1.5
		var hit_text := StateInspector.to_text(StateInspector.describe(player, null, shown_hits))
		check(hit_text.contains("damage 8.00") and hit_text.contains("(1.5 s ago)"), "inspector: the text shows the last hit with its age")
		check(StateInspector.to_text(StateInspector.describe(player, null, {})).contains("Last hit: no hit recorded"), "inspector: a slot without a recorded hit says so")

		# 10. The hub: three tabs, and refresh fills the Inspect view
		var titles: Array[String] = []
		for i in range(hub._tabs.get_tab_count()):
			titles.append(hub._tabs.get_tab_title(i))
		check(titles == ["Run", "Combat", "Inspect"], "debug hub: has the Run, Combat and Inspect tabs")
		hub._refresh()
		check(not hub._inspect_view.text.is_empty() and hub._inspect_view.text.contains("Slot 1"), "debug hub: refresh fills the Inspect view with the state")
		check(not hub._inspect_view.editable, "debug hub: the Inspect view is read-only")
		hub._inspect_view.text = "stale"
		hub._tabs.current_tab = 2
		check(hub._inspect_view.text.contains("Slot 1"), "debug hub: selecting the Inspect tab refreshes it")
		hub._tabs.current_tab = 0
		var saved_player_id: int = _eb.active_player_instance_id
		_eb.active_player_instance_id = 0
		hub._refresh_inspector()
		var no_player_text := hub._inspect_view.text
		_eb.active_player_instance_id = saved_player_id
		check(no_player_text == "no player", "debug hub: refreshing without a player shows a plain message and does not error")


# ---------------------------------------------------------------------------------------------
# Task O: Overclock is derived from the run ledger (no stored flag on the gate)
# ---------------------------------------------------------------------------------------------

func _section_overclock_from_ledger() -> void:
	var player := fx.fresh_player()
	var ability := fx.mount_arcane_bolt(player)
	var ledger := player.run_ledger_component
	var gate := ability.evolution_gate_component
	var tracker := ability.infusion_tracker_component
	var overclock := load(DBG_OVERCLOCK_CARD) as UpgradeDefinition
	var fire := load(FIRE_CARD) as UpgradeDefinition
	var T1 := EvolutionGateComponent.EvolutionState.TIER_1_BASE

	# a. A fresh ability is not overclocked.
	check(not gate.is_permanently_overclocked, "overclock ledger: a fresh ability is not overclocked")

	# b. A direct ledger purchase is enough; the cap lifts.
	_socket_fire_and_frost(player, 3)
	check(not tracker.is_element_socket_allowed(Tags.Type.FIRE, T1, gate.is_permanently_overclocked), "overclock ledger: fire at the soft cap is refused before Overclock")
	ledger.log_slot_specific_purchase(overclock, 1)
	check(gate.is_permanently_overclocked, "overclock ledger: a ledger purchase overclocks the gate")
	check(tracker.is_element_socket_allowed(Tags.Type.FIRE, T1, gate.is_permanently_overclocked), "overclock ledger: the tracker accepts Fire at level 3 once overclocked")

	# c. Another slot is not affected.
	var other_data := (load(fx.ARCANE_BOLT_DATA) as AbilityData).duplicate() as AbilityData
	other_data.slot_index = 2 as AbilityData.Role
	var other := player.ability_container.add_ability_from_data(other_data)
	check(is_instance_valid(other) and not other.evolution_gate_component.is_permanently_overclocked, "overclock ledger: a second ability in slot 2 is not overclocked")

	# d. A plain purchase overclocks nothing.
	var plain_player := fx.fresh_player()
	var plain_ability := fx.mount_arcane_bolt(plain_player)
	plain_player.run_ledger_component.log_purchase(overclock)
	check(not plain_ability.evolution_gate_component.is_permanently_overclocked and not plain_player.run_ledger_component.is_overclocked(1), "overclock ledger: a plain log_purchase overclocks nothing")

	# e. Clearing the ledger clears the flag.
	player = fx.fresh_player()
	ability = fx.mount_arcane_bolt(player)
	ledger = player.run_ledger_component
	gate = ability.evolution_gate_component
	ledger.log_slot_specific_purchase(overclock, 1)
	check(gate.is_permanently_overclocked, "overclock ledger: overclocked before the clear")
	ledger.restore_state({}, [])
	check(not gate.is_permanently_overclocked, "overclock ledger: clearing the ledger clears the flag")

	# f. Round trip through the run state.
	ledger.log_slot_specific_purchase(overclock, 1)
	player.capture_run_state()
	ledger.restore_state({}, [])
	player.ability_container.remove_ability_by_slot(1)
	player._restore_run_state()
	var restored := player.ability_container.get_ability_by_slot(1)
	check(is_instance_valid(restored) and restored.evolution_gate_component.is_permanently_overclocked, "overclock ledger: run state round trip keeps the slot overclocked")
	check(is_instance_valid(restored) and not restored.export_runtime_state().has("overclocked"), "overclock ledger: the exported state has no overclocked key")

	# g. Current behavior: an Overclock bought for an empty slot applies to an ability mounted there later.
	player = fx.fresh_player()
	player.run_ledger_component.log_slot_specific_purchase(overclock, 2)
	var late_data := (load(fx.ARCANE_BOLT_DATA) as AbilityData).duplicate() as AbilityData
	late_data.slot_index = 2 as AbilityData.Role
	var late := player.ability_container.add_ability_from_data(late_data)
	check(is_instance_valid(late) and late.evolution_gate_component.is_permanently_overclocked, "overclock ledger: an Overclock bought for an empty slot overclocks an ability mounted there later (current behavior)")

	# h. A gate with no ledger is never overclocked.
	var bare_gate := EvolutionGateComponent.new()
	fx.track(bare_gate)
	check(not bare_gate.is_permanently_overclocked, "overclock ledger: a gate with no ledger reports false")
	bare_gate.configure_slot_context(1)
	check(not bare_gate.is_permanently_overclocked, "overclock ledger: a gate configured with a null ledger reports false")

	# i. restore_state sets the evolution state only.
	player = fx.fresh_player()
	ability = fx.mount_arcane_bolt(player)
	ability.evolution_gate_component.restore_state(EvolutionGateComponent.EvolutionState.TIER_2_EVOLVED)
	check(ability.evolution_gate_component.current_state == EvolutionGateComponent.EvolutionState.TIER_2_EVOLVED and not ability.evolution_gate_component.is_permanently_overclocked, "overclock ledger: restore_state sets the evolution state only")


func _stack_bat() -> Enemy:
	var bat := _spawn_bat()
	bat.health_component.update_max_health(100000.0, true)
	bat.health_component.set_to_full()
	return bat


## Expected Burn tick damage after `elapsed` seconds with no ramp cap bonus: dot * ramp * interval * stacks.
func _stack_expected_tick(burn: StatusEffect, dot: float, elapsed: float, stacks: int) -> float:
	var ramp := 1.0 + minf(elapsed * burn.ramp_bonus_per_second, burn.ramp_max_bonus)
	return dot * ramp * burn.tick_interval * stacks


func _section_stack_cap() -> void:
	var burn := load("res://resources/status_effects/burn.tres") as StatusEffect
	var chill := load("res://resources/status_effects/chill.tres") as StatusEffect

	# a. Bonus 0: REFRESH is unchanged (one stack, tick = dot * ramp * interval).
	var bat_a := _stack_bat()
	var comp_a := bat_a.status_effect_component
	var ticks_a: Array[float] = []
	comp_a.ticked.connect(func(_i: StatusEffectInstance, dmg: float) -> void: ticks_a.append(dmg))
	for i in range(5):
		comp_a.apply_effect(burn, 10.0, 10.0, 0.0, 0.0)
	var inst_a: StatusEffectInstance = comp_a._active_effects["burn"]
	check(inst_a.stacks == 1 and inst_a.get_stack_cap() == 1, "stack cap: bonus 0, five Burn applications stay at 1 stack")
	comp_a._process(0.5)
	check(ticks_a.size() == 1 and is_equal_approx(ticks_a[0], _stack_expected_tick(burn, 10.0, 0.5, 1)), "stack cap: bonus 0, tick damage = dot * ramp * interval")

	# b. Bonus 2: cap 3, tick damage scales with stacks, every application resets the timer, elapsed keeps running.
	var bat_b := _stack_bat()
	var comp_b := bat_b.status_effect_component
	var ticks_b: Array[float] = []
	comp_b.ticked.connect(func(_i: StatusEffectInstance, dmg: float) -> void: ticks_b.append(dmg))
	for i in range(5):
		comp_b.apply_effect(burn, 10.0, 10.0, 0.0, 2.0)
	var inst_b: StatusEffectInstance = comp_b._active_effects["burn"]
	check(inst_b.stacks == 3 and inst_b.get_stack_cap() == 3, "stack cap: bonus 2, five applications give 3 stacks (cap 3)")
	comp_b._process(0.5)
	check(ticks_b.size() == 1 and is_equal_approx(ticks_b[0], _stack_expected_tick(burn, 10.0, 0.5, 3)), "stack cap: bonus 2, tick damage = dot * ramp * interval * 3")
	comp_b._process(1.0)
	check(is_equal_approx(inst_b.time_remaining, 8.5), "stack cap: the timer ran down before the re-apply")
	comp_b.apply_effect(burn, 10.0, 10.0, 0.0, 2.0)
	check(is_equal_approx(inst_b.time_remaining, 10.0) and is_equal_approx(inst_b.elapsed, 1.5) and inst_b.stacks == 3, "stack cap: a re-apply resets the timer, elapsed keeps running, stacks stay at the cap")

	# c. The latest applier's dot_damage wins and the stacks are kept.
	var bat_c := _stack_bat()
	var comp_c := bat_c.status_effect_component
	for i in range(3):
		comp_c.apply_effect(burn, 5.0, 10.0, 0.0, 2.0)
	var inst_c: StatusEffectInstance = comp_c._active_effects["burn"]
	comp_c.apply_effect(burn, 8.0, 10.0, 0.0, 2.0)
	check(is_equal_approx(inst_c.dot_damage, 8.0) and inst_c.stacks == 3, "stack cap: the latest dot_damage snapshot wins and the stacks are kept")

	# d. Stacks never decrease on a re-apply (current behavior): a lower bonus leaves the stacks above the new cap.
	var bat_d := _stack_bat()
	var comp_d := bat_d.status_effect_component
	for i in range(4):
		comp_d.apply_effect(burn, 10.0, 10.0, 0.0, 3.0)
	var inst_d: StatusEffectInstance = comp_d._active_effects["burn"]
	check(inst_d.stacks == 4, "stack cap: bonus 3 builds 4 stacks")
	comp_d.apply_effect(burn, 10.0, 10.0, 0.0, 0.0)
	check(inst_d.stacks == 4 and is_equal_approx(inst_d.stack_cap_bonus, 0.0) and inst_d.get_stack_cap() == 1, "stack cap: an application with bonus 0 keeps 4 stacks (no decrease) and sets stack_cap_bonus to 0")
	comp_d.apply_effect(burn, 10.0, 10.0, 0.0, 0.0)
	check(inst_d.stacks == 4, "stack cap: no further stack is added above the cap")

	# e. After expiry a new application starts at 1 stack.
	var bat_e := _stack_bat()
	var comp_e := bat_e.status_effect_component
	for i in range(3):
		comp_e.apply_effect(burn, 10.0, 1.0, 0.0, 2.0)
	check(comp_e._active_effects["burn"].stacks == 3, "stack cap: three stacks before expiry")
	comp_e._process(0.5)
	comp_e._process(0.5)
	check(comp_e._active_effects.is_empty(), "stack cap: the effect expired")
	comp_e.apply_effect(burn, 10.0, 1.0, 0.0, 2.0)
	check(comp_e._active_effects["burn"].stacks == 1, "stack cap: after expiry a new application starts at 1 stack")

	# f. A non-ticking template (Chill) ignores the bonus.
	var bat_f := _stack_bat()
	var comp_f := bat_f.status_effect_component
	for i in range(3):
		comp_f.apply_effect(chill, 0.0, 3.0, 0.0, 3.0)
	var inst_f: StatusEffectInstance = comp_f._active_effects["chill"]
	check(chill.tick_interval <= 0.0 and inst_f.stacks == 1 and inst_f.get_stack_cap() == 1, "stack cap: Chill (non-ticking) with bonus 3 stays at 1 stack")

	# g. The cast snapshot follows a test-only LOCAL_SLOT card; the real Fire card does not touch the stat.
	var player := fx.fresh_player()
	var ability := fx.mount_arcane_bolt(player)
	var sc := ability.stats_container
	var fire := load(FIRE_CARD) as UpgradeDefinition
	var stack_card := _l3_card("test_stack_bonus")
	stack_card.stat_modifiers.append(_l3_modifier(StatModifier.Type.FLAT, 1.0, Stat.Type.STATUS_STACK_BONUS))
	var ledger := player.run_ledger_component
	ledger.log_slot_specific_purchase(fire, 1)
	var p0 := CombatCalculations.generate_hit_payload(player, sc, ability.tag_component)
	check(is_equal_approx(p0.status_stack_bonus_snapshot, 0.0) and p0.status_effects_to_apply.size() == 1, "stack cap: Fire alone leaves the snapshot at 0.0 (Burn is carried)")
	for tier in range(1, 4):
		ledger.log_slot_specific_purchase(stack_card, 1)
		var payload := CombatCalculations.generate_hit_payload(player, sc, ability.tag_component)
		check(is_equal_approx(payload.status_stack_bonus_snapshot, float(tier)), "stack cap: the test card at tier %d gives snapshot %d.0" % [tier, tier])
		if tier == 3:
			var copy := payload.duplicate() as CombatPayload
			check(is_equal_approx(copy.status_stack_bonus_snapshot, 3.0), "stack cap: the snapshot survives payload.duplicate")

	# h. A STACK template with a tick interval adds the bonus to max_stacks.
	var stack_effect := StatusEffect.new()
	stack_effect.effect_id = "test_stack_effect"
	stack_effect.stacking = StatusEffect.StackingPolicy.STACK
	stack_effect.max_stacks = 3
	stack_effect.tick_interval = 0.5
	var stack_inst := StatusEffectInstance.new(stack_effect, 1)
	check(stack_inst.get_stack_cap() == 3, "stack cap: a STACK template with max_stacks 3 has cap 3 with bonus 0")
	stack_inst.stack_cap_bonus = 2.0
	check(stack_inst.get_stack_cap() == 5, "stack cap: a STACK template with max_stacks 3 has cap 5 with bonus 2")

	# i. DebugActions passes the bonus through.
	var detached: Array[Dictionary] = []
	for node in tree.root.find_children("*", "Enemy", true, false):
		detached.append({"enemy": node, "parent": node.get_parent()})
		node.get_parent().remove_child(node)
	var bat_i := _stack_bat()
	for i in range(3):
		DebugActions.apply_status_to_nearest(tree, burn, 5.0, 3.0, 2.0)
	var inst_i: StatusEffectInstance = bat_i.status_effect_component._active_effects.get("burn")
	check(inst_i != null and inst_i.stacks == 3, "stack cap: apply_status_to_nearest with bonus 2, called 3 times, gives 3 stacks")
	for item in detached:
		if is_instance_valid(item["enemy"]) and is_instance_valid(item["parent"]):
			item["parent"].add_child(item["enemy"])

	# j. Guards.
	check(burn.stacking == StatusEffect.StackingPolicy.REFRESH and burn.max_stacks == 1, "stack cap: the real burn.tres is still REFRESH with max_stacks 1")
	var fire_touches_stack := false
	for modifier in fire.stat_modifiers:
		fire_touches_stack = fire_touches_stack or modifier.target_stat_type == Stat.Type.STATUS_STACK_BONUS
	check(not fire_touches_stack, "stack cap: the real Fire card has no modifier on STATUS_STACK_BONUS")
	check(int(Stat.Type.STATUS_STACK_BONUS) == 20, "stack cap: STATUS_STACK_BONUS is appended as integer 20")


func _section_spawn_health() -> void:
	# A throwaway profile and EnemyData: the loaded resources are cached and must not be changed.
	var shipped := load("res://resources/entities/enemy/bat.tres") as EnemyData
	var values: Dictionary[Stat.Type, float] = {}
	for stat_type in shipped.stats_profile.base_stats:
		values[stat_type] = shipped.stats_profile.base_stats[stat_type]
	values[Stat.Type.MAX_HEALTH] = 37.0
	var profile := StatsProfile.new()
	profile.base_stats = values
	var data := shipped.duplicate() as EnemyData
	data.stats_profile = profile
	var probe := HealthComponent.new()
	var default_pool := probe.max_health
	probe.free()
	check(not is_equal_approx(default_pool, 37.0), "spawn health: the test profile's 37 differs from the component default (%.0f)" % default_pool)
	var bat := fx.spawn_bat(data)
	var health := bat.health_component
	check(is_equal_approx(health.max_health, 37.0), "spawn health: max health is 37 from a profile that differs from the component default")
	check(is_equal_approx(health.current_health, 37.0), "spawn health: a new enemy starts at 37, the profile value, not the component default")
