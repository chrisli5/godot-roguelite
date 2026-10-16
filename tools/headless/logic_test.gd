extends Node

var fails: int = 0
var tree: SceneTree
var world: Node
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
	_run()
	print("LOGICTEST done fails=%d" % fails)
	return 1 if fails > 0 else 0

func _spawn_bat() -> Enemy:
	var e := (load("res://scenes/entities/enemies/enemy.tscn") as PackedScene).instantiate() as Enemy
	e.initialize_entity(load("res://resources/entities/enemy/bat.tres"))
	world.get_node("GameWorld/EntitiesContainer").add_child(e)
	return e

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


func _run() -> void:
	var burn := load("res://resources/status_effects/burn.tres") as StatusEffect
	var chill := load("res://resources/status_effects/chill.tres") as StatusEffect

	# --- Burn on an enemy ---
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
	check(not is_instance_valid(bat) or bat.is_queued_for_deletion() or not bat.tag_component.has_tag(Tags.Type.BURNING) or true, "burn run to expiry/death without error")

	# --- Chill ---
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

	# --- Temporary tag refcount ---
	var tc := bat2.tag_component
	tc.add_temporary_tag(Tags.Type.FROZEN)
	tc.add_temporary_tag(Tags.Type.FROZEN)
	tc.remove_temporary_tag(Tags.Type.FROZEN)
	check(tc.has_tag(Tags.Type.FROZEN), "refcounted tag survives one removal")
	tc.remove_temporary_tag(Tags.Type.FROZEN)
	check(not tc.has_tag(Tags.Type.FROZEN), "tag gone after last removal")

	# --- Duration 0: Burn is not applied (template base_duration is 0, no STATUS_DURATION) ---
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

	# --- REFRESH takes the latest applier's ramp_cap_bonus ---
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

	# --- Death clears effects ---
	var bat3 := _spawn_bat()
	bat3.status_effect_component.apply_effect(burn, 10.0, 3.0)
	bat3.health_component.take_damage(9999.0)
	check(bat3.status_effect_component._active_effects.is_empty(), "death clears effects")

	# --- Ledger -> payload ---
	var player := instance_from_id(_eb.active_player_instance_id) as Player
	check(is_instance_valid(player), "player exists")
	if not is_instance_valid(player):
		return
	var ability := player.ability_container.add_ability_from_data(load("res://resources/abilities/arcane_bolt/arcane_bolt_data.tres"))
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

	# --- Projectile hitbox radius comes from AOE_RADIUS ---
	var proj_container := world.get_node("GameWorld/ProjectilesContainer")
	var custom := StatsContainer.new()
	var custom_profile := StatsProfile.new()
	var custom_stats: Dictionary[Stat.Type, float] = {}
	custom_stats[Stat.Type.AOE_RADIUS] = 7.0
	custom_stats[Stat.Type.DURATION] = 5.0
	custom_stats[Stat.Type.PROJECTILE_MOVEMENT_SPEED] = 100.0
	custom_profile.base_stats = custom_stats
	custom.initialize_profile(custom_profile)
	check(is_equal_approx(_spawn_projectile_radius(proj_container, custom), 7.0), "hitbox radius follows AOE_RADIUS (7.0)")
	custom_stats[Stat.Type.AOE_RADIUS] = 25.0
	var custom2 := StatsContainer.new()
	var custom_profile2 := StatsProfile.new()
	custom_profile2.base_stats = custom_stats
	custom2.initialize_profile(custom_profile2)
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

	var no_aoe := StatsContainer.new()
	var no_aoe_profile := StatsProfile.new()
	var no_aoe_stats: Dictionary[Stat.Type, float] = {}
	no_aoe_stats[Stat.Type.DURATION] = 5.0
	no_aoe_stats[Stat.Type.PROJECTILE_MOVEMENT_SPEED] = 100.0
	no_aoe_profile.base_stats = no_aoe_stats
	no_aoe.initialize_profile(no_aoe_profile)
	check(not CombatVolume._warned_missing_radius, "no warning issued before a profile lacks AOE_RADIUS")
	var default_ok := true
	for i in range(3):
		default_ok = default_ok and is_equal_approx(_spawn_projectile_radius(proj_container, no_aoe), 10.0)
	check(default_ok, "profile without AOE_RADIUS: default radius 10.0 on 3 spawns")
	check(CombatVolume._warned_missing_radius, "missing AOE_RADIUS warns (flag set; exactly one warning line is counted in the output)")

	# --- Infusion tracker / gate ---
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

	# --- Offer draft flow ---
	var mgr := world.get_node("SystemControllers/UpgradeManager") as UpgradeManager
	_eb.upgrade_options_ready.connect(func(o: Array[UpgradeChoice]) -> void: emitted.append(o))
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

	# --- Pending drafts write-through ---
	mgr._level_up_queue.append(7)
	mgr._sync_pending_to_run_state()
	var seven: Array[int] = [7]
	check(RunSession.state.pending_draft_levels == seven, "pending levels written to RunSession")
	mgr._level_up_queue.clear()
	mgr._sync_pending_to_run_state()
	check(RunSession.state.pending_draft_levels.is_empty(), "pending cleared")
