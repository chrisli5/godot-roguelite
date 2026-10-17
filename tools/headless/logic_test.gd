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


func _section_infusion_tracker() -> void:
	var player := fx.fresh_player()
	var ability := fx.mount_arcane_bolt(player)
	var tr := ability.infusion_tracker_component
	var gate := ability.evolution_gate_component
	var T1 := EvolutionGateComponent.EvolutionState.TIER_1_BASE
	var levels: Array[int] = [3, 3, 0, 0, 0]
	tr.restore_levels(levels)
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
	var tr := ability.infusion_tracker_component
	var gate := ability.evolution_gate_component
	var levels: Array[int] = [3, 3, 0, 0, 0]
	var mgr := fx.get_upgrade_manager()
	emitted.clear()
	var listener := func(o: Array[UpgradeChoice]) -> void: emitted.append(o)
	_eb.upgrade_options_ready.connect(listener)
	tr.restore_levels(levels)
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
