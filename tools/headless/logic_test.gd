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
		_section_burst_cap,
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
		_section_strongest_dot,
		_section_per_hit_crit,
		_section_spawn_health,
		_section_plasma_evolution,
		_section_lightning_crit_multiplier,
		_section_burst_extensions,
		_section_burst_status_filter,
		_section_compound_offer,
		_section_magma,
		_section_storm_strike,
		_section_shock,
		_section_superconduct,
		_section_blizzard,
		_section_lingering_zone,
		_section_geometry_contract,
		_section_speed_reach_bonus,
		_section_geometry_standardization,
		_section_stepped_delivery,
		_section_indirect_scaling,
		_section_lightning_earth_indirect,
		_section_status_sources,
		_section_status_magnitude,
		_section_all_match_tags,
		_section_burst_stat_inheritance,
		_section_burst_gating_synthetic,
		_section_health_bar,
		_section_error_guard,
	]
	for section in sections:
		await fx.run_section(section, check)
	fx.finish_guard()
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
	var crit_hit := CombatCalculations.resolve_hit_crit(crit_payload)
	check(crit_hit != crit_payload and crit_hit.is_critical_hit and is_equal_approx(crit_hit.final_damage, 20.0) and not crit_payload.is_critical_hit and is_equal_approx(crit_payload.final_damage, 10.0), "hit time: a forced crit resolves to a copy with is_critical_hit and damage 20, the cast payload stays 10")
	check(CombatCalculations.resolve_hit_crit(plain_payload) == plain_payload and not plain_payload.is_critical_hit and is_equal_approx(plain_payload.final_damage, 10.0), "hit time: a forced non-crit resolves to the same payload (is_critical_hit false, damage 10)")
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


## Lands `hits` primary hits of `payload` on bats[0] and waits for the deferred bursts to run.
## Returns how many burst hits the neighbor (bats[1]) received.
func _burst_hits_on_neighbor(payload: CombatPayload, y: float, hits: int) -> int:
	var bats := await _spawn_burst_bats(Vector2(90000.0, y), [Vector2(0, 0), Vector2(30, 0)])
	for i in range(hits):
		bats[0].hurtbox_component.take_hit(payload)
	await tree.process_frame
	await tree.process_frame
	var seen: int = _recorded[1].size()
	_free_bats(bats)
	return seen


func _section_burst_cap() -> void:
	var stats := _make_stats({Stat.Type.AOE_RADIUS: 40.0})
	var capped := _make_burst(&"cap_three", ImpactBurstDefinition.Trigger.ON_HIT)
	capped.max_per_cast = 3
	var single := _make_burst(&"cap_one", ImpactBurstDefinition.Trigger.ON_HIT)
	single.max_per_cast = 1
	var unlimited := _make_burst(&"cap_none", ImpactBurstDefinition.Trigger.ON_HIT)
	var burn := load("res://resources/status_effects/burn.tres") as StatusEffect

	var cast_a := CombatCalculations.generate_hit_payload(world as Node2D, stats, null)
	var cast_b := CombatCalculations.generate_hit_payload(world as Node2D, stats, null)
	check(cast_a.cast_id != 0 and cast_b.cast_id != cast_a.cast_id, "cast id: every generated payload gets a new nonzero cast_id")
	check(cast_a.cast_budget != null and cast_b.cast_budget != cast_a.cast_budget, "cast budget: every generated payload gets its own budget")
	var fallback := CombatCalculations.generate_hit_payload(null, null, null)
	check(fallback.cast_id != 0 and fallback.cast_budget != null, "cast budget: the no-stats fallback payload gets a cast_id and budget too")
	var budget := CastBudget.new()
	check(budget.try_spend(1, 2) and budget.try_spend(1, 2) and not budget.try_spend(1, 2) and budget.count_of(1) == 2, "CastBudget: spends up to max_count, then refuses without changing the count")
	check(budget.try_spend(2, 0) and budget.try_spend(2, 0) and budget.count_of(2) == 2, "CastBudget: max_count 0 never refuses but still counts")

	# --- cap 3: five qualifying hits from one cast spawn 3 bursts ---
	cast_a.impact_bursts = [capped]
	check(await _burst_hits_on_neighbor(cast_a, 101000.0, 5) == 3, "burst cap 3: five qualifying hits spawn 3 bursts")
	check(cast_a.cast_budget.count_of(capped.get_instance_id()) == 3, "burst cap 3: the cast's budget recorded 3 spends")

	# --- a second cast (new payload) gets a fresh budget ---
	cast_b.impact_bursts = [capped]
	check(await _burst_hits_on_neighbor(cast_b, 102000.0, 5) == 3, "burst cap: a second cast has a fresh budget (3 bursts again)")

	# --- two definitions in one cast are counted separately ---
	var cast_c := CombatCalculations.generate_hit_payload(world as Node2D, stats, null)
	cast_c.impact_bursts = [capped, single]
	check(await _burst_hits_on_neighbor(cast_c, 103000.0, 5) == 4, "burst cap: cap 3 and cap 1 in one cast count separately (3 + 1 = 4)")

	# --- max_per_cast 0 spawns on every hit as before ---
	var cast_d := CombatCalculations.generate_hit_payload(world as Node2D, stats, null)
	cast_d.impact_bursts = [unlimited]
	check(await _burst_hits_on_neighbor(cast_d, 104000.0, 5) == 5, "burst cap: max_per_cast 0 spawns on every hit (5 of 5)")

	# --- a null budget is unlimited, even with a cap set ---
	var no_budget := _burst_payload(stats, 10.0, [single])
	check(no_budget.cast_budget == null and await _burst_hits_on_neighbor(no_budget, 105000.0, 4) == 4, "burst cap: a null budget means unlimited (4 of 4 despite cap 1)")

	# --- a hit failing required_target_tag does not spend budget ---
	var tagged := _make_burst(&"cap_tagged", ImpactBurstDefinition.Trigger.ON_HIT)
	tagged.max_per_cast = 1
	tagged.required_target_tag = Tags.Type.BURNING
	var cast_e := CombatCalculations.generate_hit_payload(world as Node2D, stats, null)
	cast_e.impact_bursts = [tagged]
	check(await _burst_hits_on_neighbor(cast_e, 106000.0, 3) == 0 and cast_e.cast_budget.count_of(tagged.get_instance_id()) == 0, "burst cap: hits failing required_target_tag spawn nothing and spend nothing")
	var bats := await _spawn_burst_bats(Vector2(90000.0, 107000.0), [Vector2(0, 0), Vector2(30, 0)])
	bats[0].tag_component.add_temporary_tag(Tags.Type.BURNING)
	bats[0].hurtbox_component.take_hit(cast_e)
	bats[0].hurtbox_component.take_hit(cast_e)
	await tree.process_frame
	await tree.process_frame
	check(_recorded[1].size() == 1 and cast_e.cast_budget.count_of(tagged.get_instance_id()) == 1, "burst cap: once the tag is present the burst fires, and only up to its cap (1)")
	_free_bats(bats)

	# --- duplicated payloads share the budget and the cast id ---
	var copy := cast_a.duplicate() as CombatPayload
	check(copy.cast_budget == cast_a.cast_budget and copy.cast_id == cast_a.cast_id and copy.cast_id != 0, "payload.duplicate shares the CastBudget by reference and keeps cast_id")
	check(copy.impact_bursts.size() == 1 and copy.impact_bursts[0].get_instance_id() == capped.get_instance_id(), "payload.duplicate keeps the same definition instance (the budget key is stable)")

	# --- a skipped burst applies none of its statuses ---
	var status_burst := _make_burst(&"cap_status", ImpactBurstDefinition.Trigger.ON_HIT)
	status_burst.max_per_cast = 1
	status_burst.carried_status_tags = [Tags.Type.BURNING]
	var status_list: Array[StatusEffect] = [burn]
	var cast_f := CombatCalculations.generate_hit_payload(world as Node2D, stats, null)
	cast_f.impact_bursts = [status_burst]
	cast_f.status_effects_to_apply = status_list
	cast_f.dot_damage_snapshot = 1.0
	cast_f.status_duration_snapshot = 3.0
	bats = await _spawn_burst_bats(Vector2(90000.0, 108000.0), [Vector2(0, 0), Vector2(30, 0), Vector2(5000, 0), Vector2(5030, 0)])
	bats[0].hurtbox_component.take_hit(cast_f)
	bats[2].hurtbox_component.take_hit(cast_f)
	await tree.process_frame
	await tree.process_frame
	check(bats[1].status_effect_component._active_effects.has("burn"), "burst cap: the burst that fired applied its status (neighbor burns)")
	check(bats[3].status_effect_component._active_effects.is_empty() and is_equal_approx(_lost(bats[3]), 0.0), "burst cap: the skipped burst applied no status and no damage")
	_free_bats(bats)

	# --- a burst-copy payload keeps the budget and carries no bursts, so it never spends ---
	var spent_before: int = cast_f.cast_budget.count_of(status_burst.get_instance_id())
	bats = await _spawn_burst_bats(Vector2(90000.0, 109000.0), [Vector2(0, 0), Vector2(30, 0)])
	var burst_copy := cast_f.duplicate() as CombatPayload
	var no_bursts: Array[ImpactBurstDefinition] = []
	burst_copy.impact_bursts = no_bursts
	burst_copy.is_burst = true
	bats[0].hurtbox_component.take_hit(burst_copy)
	await tree.process_frame
	check(burst_copy.cast_budget == cast_f.cast_budget and cast_f.cast_budget.count_of(status_burst.get_instance_id()) == spent_before, "burst copy: keeps the cast's budget and spends nothing")
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
	check(p.status_effects_to_apply.size() == 1 and p.status_effects_to_apply[0] == burn, "fire + frost, no compound card -> Burn only (Task AO: Frost carries no status)")
	var d := p.duplicate() as CombatPayload
	check(d.status_effects_to_apply.size() == 1 and d.status_effects_to_apply[0] == burn, "duplicate keeps statuses")


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
	var earth_area_stats := _make_stats({Stat.Type.AOE_RADIUS: 200.0, Stat.Type.QUERY_RADIUS: 150.0, Stat.Type.REACH_BONUS: 0.0}, 2, player.run_ledger_component)
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
	check(enemy_status["effect_id"] == live.template.effect_id and enemy_status["time_remaining"] == live.time_remaining and enemy_status["dot_damage"] == live.dot_damage and enemy_status["duration_bonus"] == live.duration_bonus, "inspector: the enemy's status row matches its live instance")
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


func _tough_bat() -> Enemy:
	var bat := _spawn_bat()
	bat.health_component.update_max_health(100000.0, true)
	bat.health_component.set_to_full()
	return bat


## A cast payload with the crit snapshots set the way generate_hit_payload would, for the per-hit roll.
func _crit_payload(stats: StatsContainer, damage: float, chance: float, multiplier: float, definitions: Array[ImpactBurstDefinition] = [], share: float = 0.0) -> CombatPayload:
	var payload := _burst_payload(stats, damage, definitions)
	payload.crit_chance_snapshot = chance
	payload.crit_multiplier_snapshot = multiplier
	payload.crit_dot_share_snapshot = share
	payload.cast_budget = CastBudget.new()
	return payload


## Task AL: every hit rolls its own crit in HurtboxComponent.take_hit, from the cast's snapshots.
func _section_per_hit_crit() -> void:
	var burn := load("res://resources/status_effects/burn.tres") as StatusEffect
	var burn_list: Array[StatusEffect] = [burn]
	var stats := _make_stats({Stat.Type.AOE_RADIUS: 40.0})
	var none: Array[ImpactBurstDefinition] = []

	# a. generate_hit_payload never rolls: damage is base * scale, the DoT snapshot is unscaled by the share.
	var player := fx.fresh_player()
	var values: Dictionary = {
		Stat.Type.BASE_DAMAGE: 10.0, Stat.Type.CRIT_CHANCE: 1.0, Stat.Type.CRIT_MULTIPLIER: 2.0,
		Stat.Type.DOT_DAMAGE: 4.0, Stat.Type.STATUS_DURATION: 6.0, Stat.Type.STATUS_RAMP_CAP: 0.3,
		Stat.Type.COOLDOWN: 1.875, Stat.Type.SPEED_BONUS: -0.1, Stat.Type.CRIT_DOT_SHARE: 1.0, Stat.Type.AOE_RADIUS: 40.0,
	}
	var lane := _indirect_lane(player, values, 2, 2)
	var never_rolls := true
	for i in range(20):
		var cast := CombatCalculations.generate_hit_payload(null, lane, null)
		never_rolls = never_rolls and not cast.is_critical_hit and is_equal_approx(cast.final_damage, 11.7) and is_equal_approx(cast.dot_damage_snapshot, 4.68)
	check(never_rolls, "per-hit crit: generate_hit_payload never rolls (20 casts at chance 1.0: not critical, damage base * scale 11.7, DoT 4.68 unscaled by the share)")
	var snap := CombatCalculations.generate_hit_payload(null, lane, null)
	check(is_equal_approx(snap.crit_chance_snapshot, 1.0) and is_equal_approx(snap.crit_multiplier_snapshot, 2.0) and is_equal_approx(snap.crit_dot_share_snapshot, 1.0), "per-hit crit: the cast stores the chance, multiplier and share snapshots")
	fx.reset_player_state()

	# b. Chance 1.0 crits every hit, 0.0 none, 0.5 some. Four tough bats take the hits.
	var rates := {}
	for chance in [1.0, 0.0, 0.5]:
		var counts := [0, 0]
		var shared := _crit_payload(stats, 1.0, chance, 2.0)
		var hits_per_bat := 5 if chance != 0.5 else 50
		for b in range(4):
			var bat := _tough_bat()
			bat.hurtbox_component.hit_received.connect(func(p: CombatPayload) -> void:
				counts[0] += 1
				if p.is_critical_hit:
					counts[1] += 1)
			for h in range(hits_per_bat):
				bat.hurtbox_component.take_hit(shared)
		rates[chance] = counts
	check(rates[1.0][0] == 20 and rates[1.0][1] == 20, "per-hit crit: chance 1.0 crits every hit (20 of 20)")
	check(rates[0.0][0] == 20 and rates[0.0][1] == 0, "per-hit crit: chance 0.0 crits no hit (0 of 20)")
	check(rates[0.5][0] == 200 and rates[0.5][1] > 0 and rates[0.5][1] < 200, "per-hit crit: chance 0.5 over 200 hits gives a mix (%d crits)" % rates[0.5][1])

	# c. A crit hit deals base * multiplier; the shared cast payload is untouched.
	var bats := await _spawn_burst_bats(Vector2(72000.0, 72000.0), [Vector2(0, 0)])
	var cast_c := _crit_payload(stats, 10.0, 1.0, 2.0)
	bats[0].hurtbox_component.take_hit(cast_c)
	check(is_equal_approx(_lost(bats[0]), 20.0) and _recorded[0].size() == 1 and _recorded[0][0].is_critical_hit and is_equal_approx(_recorded[0][0].final_damage, 20.0), "per-hit crit: a crit hit deals base * multiplier (20) and hit_received sees the flag")
	check(not cast_c.is_critical_hit and is_equal_approx(cast_c.final_damage, 10.0) and _recorded[0][0] != cast_c, "per-hit crit: the shared cast payload is untouched after take_hit")
	_free_bats(bats)

	# d. ON_CRIT bursts fire only for critting hits, capped by max_per_cast; the burst includes the hit's crit.
	var on_crit := _make_burst(&"pc_on_crit", ImpactBurstDefinition.Trigger.ON_CRIT, 0.5)
	var crit_list: Array[ImpactBurstDefinition] = [on_crit]
	check(await _burst_hits_on_neighbor(_crit_payload(stats, 1.0, 0.0, 2.0, crit_list), 136000.0, 3) == 0, "per-hit crit: an ON_CRIT burst never fires when no hit crits")
	var capped := _make_burst(&"pc_on_crit_cap", ImpactBurstDefinition.Trigger.ON_CRIT, 0.5)
	capped.max_per_cast = 2
	var capped_list: Array[ImpactBurstDefinition] = [capped]
	check(await _burst_hits_on_neighbor(_crit_payload(stats, 1.0, 1.0, 2.0, capped_list), 137000.0, 4) == 2, "per-hit crit: four critting hits spend an ON_CRIT burst capped at 2 per cast")
	bats = await _spawn_burst_bats(Vector2(138000.0, 72000.0), [Vector2(0, 0), Vector2(30, 0)])
	bats[0].hurtbox_component.take_hit(_crit_payload(stats, 10.0, 1.0, 2.0, crit_list))
	await tree.process_frame
	await tree.process_frame
	check(is_equal_approx(_lost(bats[1]), 10.0), "per-hit crit: a burst's damage includes the hit's crit (0.5 of 20 = 10)")
	_free_bats(bats)
	bats = await _spawn_burst_bats(Vector2(139000.0, 72000.0), [Vector2(0, 0), Vector2(30, 0)])
	var mixed := _crit_payload(stats, 1.0, 0.5, 2.0, crit_list)
	for h in range(60):
		bats[0].hurtbox_component.take_hit(mixed)
	await tree.process_frame
	await tree.process_frame
	var crit_hits := 0
	for seen in _recorded[0]:
		if seen.is_critical_hit:
			crit_hits += 1
	check(crit_hits > 0 and crit_hits < 60 and _recorded[1].size() == crit_hits, "per-hit crit: at chance 0.5 the ON_CRIT burst fires once per critting hit (%d crits, %d bursts)" % [crit_hits, _recorded[1].size()])
	_free_bats(bats)

	# e. A burst payload and a zone payload never roll, even with a crit snapshot of 1.0.
	var burst_flag := _crit_payload(stats, 10.0, 1.0, 2.0)
	burst_flag.is_burst = true
	check(CombatCalculations.resolve_hit_crit(burst_flag) == burst_flag, "per-hit crit: resolve_hit_crit returns an is_burst payload unchanged")
	var on_hit := _make_burst(&"pc_on_hit", ImpactBurstDefinition.Trigger.ON_HIT, 0.5)
	var hit_list: Array[ImpactBurstDefinition] = [on_hit]
	bats = await _spawn_burst_bats(Vector2(140000.0, 72000.0), [Vector2(0, 0), Vector2(30, 0)])
	bats[0].hurtbox_component.take_hit(_crit_payload(stats, 10.0, 1.0, 2.0, hit_list))
	await tree.process_frame
	await tree.process_frame
	check(_recorded[1].size() == 1 and _recorded[1][0].is_burst and not _recorded[1][0].is_critical_hit and is_equal_approx(_lost(bats[1]), 10.0), "per-hit crit: a burst hit does not roll its own crit (0.5 of the crit's 20 = 10, not 20)")
	_free_bats(bats)
	LingeringZone.reset_registry()
	var origin := Vector2(141000.0, 72000.0)
	var zone_bats := await _spawn_burst_bats(origin, [Vector2(0, 0)])
	var zone_def := _zone_burst(&"pc_zone", load(TEST_LINGERING_ZONE) as PackedScene)
	var zone_payload := _zone_payload(stats, zone_def, burn_list, 5.0)
	zone_payload.crit_chance_snapshot = 1.0
	zone_payload.crit_multiplier_snapshot = 2.0
	await _spawn_zone(zone_def, zone_payload, origin)
	await tree.create_timer(0.5).timeout
	var zone_clean: bool = _recorded[0].size() >= 1
	for seen in _recorded[0]:
		zone_clean = zone_clean and seen.is_burst and not seen.is_critical_hit
	check(zone_clean, "per-hit crit: every hit a lingering zone delivers is a burst payload that never crits")
	await tree.create_timer(0.6).timeout
	_free_bats(zone_bats)

	# f. Plasma: CRIT_DOT_SHARE scales only the critting hit's Burn, and a later plain refresh does not downgrade it.
	var burn_cast := func(chance: float) -> CombatPayload:
		var payload := _crit_payload(stats, 1.0, chance, 2.0, none, 1.0)
		payload.dot_damage_snapshot = 4.0
		payload.status_duration_snapshot = 6.0
		payload.status_effects_to_apply = burn_list
		return payload
	bats = await _spawn_burst_bats(Vector2(142000.0, 72000.0), [Vector2(0, 0), Vector2(200, 0)])
	bats[0].hurtbox_component.take_hit(burn_cast.call(1.0))
	bats[1].hurtbox_component.take_hit(burn_cast.call(0.0))
	var crit_burn: StatusEffectInstance = bats[0].status_effect_component._active_effects.get("burn")
	var plain_burn: StatusEffectInstance = bats[1].status_effect_component._active_effects.get("burn")
	check(crit_burn != null and plain_burn != null and is_equal_approx(crit_burn.dot_damage, 8.0) and is_equal_approx(plain_burn.dot_damage, 4.0), "per-hit crit: the critting hit's Burn is 4 * (1 + 1 * 1) = 8, a plain hit's stays 4")
	bats[0].hurtbox_component.take_hit(burn_cast.call(0.0))
	check(bats[0].status_effect_component._active_effects.get("burn") == crit_burn and is_equal_approx(crit_burn.dot_damage, 8.0), "per-hit crit: a later non-crit refresh does not downgrade the stronger Burn")
	_free_bats(bats)

	# g. One chain cast at chance 0.5 gives a mix of crits, and each target's Burn follows its own flag.
	var chain := ChainLinkGeometry.new()
	chain.max_bounces = 40
	world.add_child(chain)
	fx.track(chain)
	var chain_bats: Array[Enemy] = []
	var flags := {}
	for i in range(41):
		var bat := _tough_bat()
		bat.set_physics_process(false)
		bat.global_position = Vector2(143000.0 + 100.0 * i, 72000.0)
		bat.hurtbox_component.hit_received.connect((func(p: CombatPayload, index: int) -> void: flags[index] = p.is_critical_hit).bind(i))
		chain_bats.append(bat)
	await tree.physics_frame
	await tree.physics_frame
	var chain_payload: CombatPayload = burn_cast.call(0.5)
	chain_payload.stats_container_id = _make_stats({Stat.Type.CHAIN_RADIUS: 150.0}).get_instance_id()
	chain.execute_geometry({"hit_nodes": [chain_bats[0].hurtbox_component]}, chain_payload)
	var crits := 0
	var burns_follow := true
	for i in range(chain_bats.size()):
		var live: StatusEffectInstance = chain_bats[i].status_effect_component._active_effects.get("burn")
		var crit_flag: bool = flags.get(i, false)
		if crit_flag:
			crits += 1
		burns_follow = burns_follow and live != null and is_equal_approx(live.dot_damage, 8.0 if crit_flag else 4.0)
	check(flags.size() == 41 and crits > 0 and crits < 41, "per-hit crit: one chain cast of 41 hits at chance 0.5 mixes crits and plain hits (%d crits)" % crits)
	check(burns_follow, "per-hit crit: along the chain each target's Burn is 8 when its hit crit and 4 when it did not")
	check(is_equal_approx(chain_payload.dot_damage_snapshot, 4.0) and not chain_payload.is_critical_hit, "per-hit crit: the chain's shared payload keeps the unscaled DoT and no crit")

	# h. The debug hit recorder shows the per-hit flag.
	var hub := world.get_node_or_null("DebugHub") as DebugHub
	if hub != null and is_instance_valid(hub._hit_recorder):
		var recorder := hub._hit_recorder
		recorder.clear()
		var ability := fx.mount_arcane_bolt(fx.fresh_player())
		var rec_bat := _tough_bat()
		await tree.process_frame
		await tree.process_frame
		var rec_payload := CombatCalculations.generate_hit_payload(null, ability.stats_container, null)
		rec_payload.crit_chance_snapshot = 1.0
		rec_payload.crit_multiplier_snapshot = 2.0
		rec_bat.hurtbox_component.take_hit(rec_payload)
		var recorded_hits := recorder.get_hits()
		check(recorded_hits.has(1) and recorded_hits[1]["is_critical_hit"] and is_equal_approx(recorded_hits[1]["final_damage"], rec_payload.final_damage * 2.0) and not rec_payload.is_critical_hit, "per-hit crit: the hit recorder shows the per-hit flag and the resolved damage")
	else:
		check(false, "per-hit crit: the hub's hit recorder is available")
	await tree.physics_frame


## A StatusEffectComponent on its own (no entity), tracked so the section frees it.
func _bare_status_component() -> StatusEffectComponent:
	var component := StatusEffectComponent.new()
	tree.root.add_child(component)
	fx.track(component)
	return component


func _section_strongest_dot() -> void:
	var burn := load("res://resources/status_effects/burn.tres") as StatusEffect
	var chill := load("res://resources/status_effects/chill.tres") as StatusEffect

	# a. A weaker but longer re-apply keeps the stronger snapshot and refreshes the timer. Elapsed (the ramp) keeps running.
	var comp := _bare_status_component()
	var refreshed := [0]
	comp.refreshed.connect(func(_instance: StatusEffectInstance) -> void: refreshed[0] += 1)
	var ticks: Array[float] = []
	comp.ticked.connect(func(_instance: StatusEffectInstance, dmg: float) -> void: ticks.append(dmg))
	comp.apply_effect(burn, 10.0, 10.0, 0.2)
	var inst: StatusEffectInstance = comp._active_effects["burn"]
	comp._process(0.25)
	comp.apply_effect(burn, 6.0, 20.0, 0.0)
	check(comp._active_effects["burn"] == inst and comp.get_active_instances().size() == 1, "strongest dot: a re-apply keeps the one instance")
	check(is_equal_approx(inst.dot_damage, 10.0) and is_equal_approx(inst.duration_bonus, 10.0) and is_equal_approx(inst.ramp_cap_bonus, 0.2), "strongest dot: a weaker re-apply keeps the existing snapshot as a unit")
	check(is_equal_approx(inst.time_remaining, 20.0) and is_equal_approx(inst.elapsed, 0.25), "strongest dot: a weaker but longer re-apply refreshes the timer and keeps elapsed")
	comp._process(0.25)
	check(ticks.size() == 1 and is_equal_approx(ticks[0], 10.0 * 1.05 * burn.tick_interval), "strongest dot: tick damage after a weaker re-apply is still the stronger dot * ramp * interval")

	# b. A stronger re-apply adopts the whole new snapshot, but a shorter one never shortens the timer.
	var left := inst.time_remaining
	comp.apply_effect(burn, 12.0, 7.0, 0.3)
	check(is_equal_approx(inst.dot_damage, 12.0) and is_equal_approx(inst.duration_bonus, 7.0) and is_equal_approx(inst.ramp_cap_bonus, 0.3), "strongest dot: a stronger re-apply adopts the new snapshot as a unit")
	check(is_equal_approx(inst.time_remaining, left) and is_equal_approx(inst.elapsed, 0.5), "strongest dot: a stronger but shorter re-apply does not shorten the timer, elapsed survives")

	# c. A tie takes the newer application.
	comp.apply_effect(burn, 12.0, 9.0, 0.1)
	check(is_equal_approx(inst.dot_damage, 12.0) and is_equal_approx(inst.duration_bonus, 9.0) and is_equal_approx(inst.ramp_cap_bonus, 0.1), "strongest dot: a tie adopts the newer snapshot")

	# d. A weaker, shorter application changes nothing but still emits refreshed.
	comp.apply_effect(burn, 1.0, 1.0, 0.0)
	check(is_equal_approx(inst.dot_damage, 12.0) and is_equal_approx(inst.duration_bonus, 9.0) and is_equal_approx(inst.ramp_cap_bonus, 0.1) and is_equal_approx(inst.time_remaining, left) and is_equal_approx(inst.elapsed, 0.5), "strongest dot: a weaker, shorter application never shortens the timer or changes the snapshot")
	check(refreshed[0] == 4, "strongest dot: refreshed fires on every re-apply (%d of 4)" % refreshed[0])

	# e. Tick damage = dot_damage * ramp * interval (elapsed 1.0 gives ramp 1.1).
	comp._process(0.5)
	check(ticks.size() == 2 and is_equal_approx(ticks[1], 12.0 * 1.1 * burn.tick_interval), "strongest dot: tick damage is dot_damage * ramp * interval")

	# f. Chill (non-ticking) is still latest-wins, even when weaker and shorter.
	var comp_f := _bare_status_component()
	comp_f.apply_effect(chill, 4.0, 5.0)
	var chill_inst: StatusEffectInstance = comp_f._active_effects["chill"]
	comp_f._process(1.0)
	comp_f.apply_effect(chill, 1.0, 2.0)
	check(chill.tick_interval <= 0.0 and is_equal_approx(chill_inst.dot_damage, 1.0) and is_equal_approx(chill_inst.duration_bonus, 2.0), "strongest dot: Chill adopts the latest application even when weaker")
	check(is_equal_approx(chill_inst.time_remaining, chill_inst.get_effective_duration()), "strongest dot: Chill's timer resets to the latest effective duration")

	# g. Different effect ids are independent.
	var comp_g := _bare_status_component()
	var other := StatusEffect.new()
	other.effect_id = "test_dot"
	other.base_duration = 0.0
	other.tick_interval = 0.5
	comp_g.apply_effect(burn, 10.0, 10.0)
	comp_g.apply_effect(other, 3.0, 5.0)
	var burn_g: StatusEffectInstance = comp_g._active_effects["burn"]
	var other_g: StatusEffectInstance = comp_g._active_effects["test_dot"]
	comp_g.apply_effect(burn, 50.0, 10.0)
	check(comp_g.get_active_instances().size() == 2 and is_equal_approx(burn_g.dot_damage, 50.0) and is_equal_approx(other_g.dot_damage, 3.0) and is_equal_approx(other_g.time_remaining, 5.0), "strongest dot: two different effect ids are independent")

	# h. The instance has no stack state left, and the retired stat keeps its stored integer.
	var stack_props := false
	for property in inst.get_property_list():
		stack_props = stack_props or property["name"] == "stacks" or property["name"] == "stack_cap_bonus"
	check(not stack_props and not inst.has_method("get_stack_cap") and not inst.has_method("refresh_modifier_values"), "strongest dot: StatusEffectInstance has no stacks property")
	check(int(Stat.Type.STATUS_STACK_BONUS) == 20, "strongest dot: the deprecated STATUS_STACK_BONUS keeps integer 20")

	# i. A lingering zone with a weaker snapshot does not downgrade a stronger Burn (and does not shorten it).
	LingeringZone.reset_registry()
	var origin := Vector2(71000.0, 71000.0)
	var zone_bats := await _spawn_burst_bats(origin, [Vector2(0, 0)])
	var zone_comp := zone_bats[0].status_effect_component
	var zone_refreshed := [0]
	zone_comp.refreshed.connect(func(_instance: StatusEffectInstance) -> void: zone_refreshed[0] += 1)
	zone_comp.apply_effect(burn, 20.0, 10.0, 0.0)
	var strong: StatusEffectInstance = zone_comp._active_effects["burn"]
	var zone_stats := _make_stats({Stat.Type.AOE_RADIUS: 10.0})
	var burn_list: Array[StatusEffect] = [burn]
	var zone_def := _zone_burst(&"test_zone_burst", load(TEST_LINGERING_ZONE) as PackedScene)
	await _spawn_zone(zone_def, _zone_payload(zone_stats, zone_def, burn_list, 5.0), origin)
	await tree.create_timer(0.5).timeout
	check(zone_refreshed[0] >= 1, "strongest dot: the weaker zone did re-apply Burn (refreshed %d times)" % zone_refreshed[0])
	check(zone_comp._active_effects.get("burn") == strong and is_equal_approx(strong.dot_damage, 20.0) and is_equal_approx(strong.duration_bonus, 10.0) and strong.time_remaining > 8.0, "strongest dot: a zone with a weaker snapshot does not downgrade or shorten a stronger Burn")
	await tree.create_timer(0.6).timeout
	_free_bats(zone_bats)
	await tree.physics_frame # end in the physics phase, like the other await sections


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


const ARC_BOLT_DATA := "res://resources/abilities/arc_bolt/arc_bolt_data.tres"
const ARC_BOLT_STATS := "res://resources/abilities/arc_bolt/arc_bolt_stats.tres"
const ARC_BOLT_CARD := "res://resources/abilities/arc_bolt/arc_bolt_evolution_upgrade_def.tres"
const ARCANE_BOLT_STATS := "res://resources/abilities/arcane_bolt/arcane_bolt_stats.tres"


## One test hit (cast, then the per-hit roll) with a crit that is forced on or off. `share` null leaves CRIT_DOT_SHARE out of the profile.
func _plasma_cast(crit_chance: float, share: Variant) -> CombatPayload:
	var values: Dictionary = {
		Stat.Type.BASE_DAMAGE: 2.0,
		Stat.Type.CRIT_CHANCE: crit_chance,
		Stat.Type.CRIT_MULTIPLIER: 1.5,
		Stat.Type.DOT_DAMAGE: 4.0,
		Stat.Type.STATUS_DURATION: 6.0,
		Stat.Type.STATUS_RAMP_CAP: 0.3,
	}
	if share != null:
		values[Stat.Type.CRIT_DOT_SHARE] = share
	return CombatCalculations.resolve_hit_crit(CombatCalculations.generate_hit_payload(null, _make_stats(values), null))


## Buys `count` Fire and `count` of `other_card` for slot 1 through the ledger.
func _plasma_socket(player: Player, other_card: UpgradeDefinition, count: int) -> void:
	var fire := load(FIRE_CARD) as UpgradeDefinition
	for i in range(count):
		player.run_ledger_component.log_slot_specific_purchase(fire, 1)
		player.run_ledger_component.log_slot_specific_purchase(other_card, 1)


## Fresh player with Arcane Bolt, Fire 3 and Lightning 3 in slot 1, with the real Arc Bolt card applied.
func _plasma_evolved_player() -> Player:
	var player := fx.fresh_player()
	fx.mount_arcane_bolt(player)
	_plasma_socket(player, load(LIGHTNING_CARD) as UpgradeDefinition, 3)
	var offer := fx.get_upgrade_manager()._build_offer_choices(player, 1)
	player.apply_contextual_upgrade(offer[0])
	return player


func _section_plasma_evolution() -> void:
	var T2 := EvolutionGateComponent.EvolutionState.TIER_2_EVOLVED
	var mgr := fx.get_upgrade_manager()
	var fire := load(FIRE_CARD) as UpgradeDefinition
	var frost := load(FROST_CARD) as UpgradeDefinition
	var lightning := load(LIGHTNING_CARD) as UpgradeDefinition

	# a. The cast rule.
	var crit_full := _plasma_cast(1.0, 1.0)
	var crit_absent := _plasma_cast(1.0, null)
	check(is_equal_approx(crit_full.dot_damage_snapshot, 4.0 * 1.5), "plasma cast: a crit with share 1.0 gives dot * crit_mult")
	check(is_equal_approx(_plasma_cast(1.0, 0.5).dot_damage_snapshot, 4.0 * (1.0 + 0.5 * 0.5)), "plasma cast: a crit with share 0.5 gives dot * (1 + 0.5 * (mult - 1))")
	check(is_equal_approx(_plasma_cast(1.0, 2.0).dot_damage_snapshot, 4.0 * 2.0), "plasma cast: a crit with share 2.0 doubles the bonus")
	check(is_equal_approx(_plasma_cast(0.0, 1.0).dot_damage_snapshot, 4.0), "plasma cast: a non-crit leaves the snapshot unchanged")
	check(is_equal_approx(_plasma_cast(1.0, 0.0).dot_damage_snapshot, 4.0), "plasma cast: share 0 leaves the snapshot unchanged on a crit")
	check(is_equal_approx(crit_absent.dot_damage_snapshot, 4.0), "plasma cast: a profile without CRIT_DOT_SHARE leaves the snapshot unchanged on a crit")
	check(crit_full.is_critical_hit and crit_absent.is_critical_hit and is_equal_approx(crit_full.final_damage, crit_absent.final_damage) and is_equal_approx(crit_full.final_damage, 3.0), "plasma cast: final_damage is identical with and without the share")
	check(is_equal_approx(crit_full.status_duration_snapshot, 6.0) and is_equal_approx(crit_full.status_ramp_cap_snapshot, 0.3), "plasma cast: the other two snapshots are unchanged by the share")

	# b. The real evolution path.
	var player := fx.fresh_player()
	fx.mount_arcane_bolt(player)
	_plasma_socket(player, lightning, 3)
	check(mgr._find_next_offer_slot(player) == 1, "plasma evolution: the offer slot is 1 with Fire 3 + Lightning 3")
	var offer := mgr._build_offer_choices(player, 1)
	check(offer.size() == 2 and offer[0].definition.upgrade_id == "evolve_arc_bolt" and offer[1].definition.payload_type == UpgradeDefinition.PayloadType.ABILITY_OVERCLOCK, "plasma evolution: the offer is the evolution card first, then Overclock")

	var frost_player := fx.fresh_player()
	fx.mount_arcane_bolt(frost_player)
	_plasma_socket(frost_player, frost, 3)
	var frost_offer := mgr._build_offer_choices(frost_player, 1)
	check(mgr._find_next_offer_slot(frost_player) == 1 and frost_offer.size() == 1 and frost_offer[0].definition.payload_type == UpgradeDefinition.PayloadType.ABILITY_OVERCLOCK, "plasma evolution: Fire 3 + Frost 3 still offers only Overclock")

	player = fx.fresh_player()
	var ability := fx.mount_arcane_bolt(player)
	var ledger := player.run_ledger_component
	var sc := ability.stats_container
	var crit_before := sc.get_final_stat_value(Stat.Type.CRIT_CHANCE)
	_plasma_socket(player, lightning, 3)
	var crit_with_lightning := sc.get_final_stat_value(Stat.Type.CRIT_CHANCE)
	check(crit_with_lightning > crit_before, "plasma evolution: Lightning raises CRIT_CHANCE before the evolution")
	offer = mgr._build_offer_choices(player, 1)
	player.apply_contextual_upgrade(offer[0])
	var gate := ability.evolution_gate_component
	var tracker := ability.infusion_tracker_component
	check(ability.data.resource_path == ARC_BOLT_DATA, "plasma evolution: the ability's data is arc_bolt_data")
	check(gate.current_state == T2, "plasma evolution: the gate state is TIER_2_EVOLVED")
	check(ability.geometry_driver is ChainLinkGeometry and ability.payload_driver == null, "plasma evolution: the geometry driver is a ChainLinkGeometry and there is no payload driver")
	var base_tags: Array[Tags.Type] = ability.tag_component.base_tags
	check(base_tags.size() == 2 and base_tags.has(Tags.Type.METAMAGIC) and base_tags.has(Tags.Type.AOE), "plasma evolution: the base tags are exactly METAMAGIC and AOE")
	var permanent := ability.tag_component.get_permanent_tags()
	check(permanent.size() == 4 and permanent.has(Tags.Type.FIRE) and permanent.has(Tags.Type.LIGHTNING) and not permanent.has(Tags.Type.PROJECTILE), "plasma evolution: the permanent tags are the base tags plus the Fire and Lightning infusion tags, no PROJECTILE")
	check(is_equal_approx(sc.get_final_stat_value(Stat.Type.CRIT_DOT_SHARE), 1.0), "plasma evolution: CRIT_DOT_SHARE reads 1.0")
	check(ledger.get_infusion_level(1, Tags.Type.FIRE) == 3 and ledger.get_infusion_level(1, Tags.Type.LIGHTNING) == 3, "plasma evolution: Fire and Lightning stay at 3 and 3")
	check(is_equal_approx(sc.get_final_stat_value(Stat.Type.STATUS_DURATION), 9.0), "plasma evolution: STATUS_DURATION is still 9.0")
	check(is_equal_approx(sc.get_final_stat_value(Stat.Type.CRIT_CHANCE), crit_with_lightning), "plasma evolution: CRIT_CHANCE is unchanged by the evolution")
	check(mgr._find_next_offer_slot(player) == 0, "plasma evolution: the evolved ability is not offer-eligible again")
	check(ledger.purchase_registry.get("evolve_arc_bolt", 0) == 1, "plasma evolution: the evolution card is logged once")
	check(tracker.is_element_socket_allowed(Tags.Type.FIRE, gate.current_state, gate.is_permanently_overclocked), "plasma evolution: Fire is accepted at level 3")
	ledger.log_slot_specific_purchase(fire, 1)
	check(tracker.is_element_socket_allowed(Tags.Type.FIRE, gate.current_state, gate.is_permanently_overclocked), "plasma evolution: Fire is accepted at level 4")
	ledger.log_slot_specific_purchase(fire, 1)
	check(not tracker.is_element_socket_allowed(Tags.Type.FIRE, gate.current_state, gate.is_permanently_overclocked), "plasma evolution: Fire at level 5 is refused (soft cap 5)")
	check(tracker.is_element_socket_allowed(Tags.Type.FROST, gate.current_state, gate.is_permanently_overclocked), "plasma evolution: a third element is accepted")
	for i in range(5):
		ledger.log_slot_specific_purchase(frost, 1)
	check(not tracker.is_element_socket_allowed(Tags.Type.WIND, gate.current_state, gate.is_permanently_overclocked), "plasma evolution: a fourth element is refused")
	for i in range(2):
		ledger.log_slot_specific_purchase(lightning, 1)
	check(mgr._find_next_offer_slot(player) == 1, "plasma evolution: three elements at level 5 make the evolved ability offer-eligible")
	var again := mgr._build_offer_choices(player, 1)
	var evolution_again := false
	for choice in again:
		evolution_again = evolution_again or choice.definition.upgrade_id == "evolve_arc_bolt"
	check(not evolution_again and again.size() == 1 and again[0].definition.payload_type == UpgradeDefinition.PayloadType.ABILITY_OVERCLOCK, "plasma evolution: the evolution card is not offered again")

	# c. Persistence.
	player = _plasma_evolved_player()
	player.capture_run_state()
	player.run_ledger_component.restore_state({}, [])
	player.ability_container.remove_ability_by_slot(1)
	player._restore_run_state()
	var restored := player.ability_container.get_ability_by_slot(1)
	check(is_instance_valid(restored) and restored.data.resource_path == ARC_BOLT_DATA, "plasma persistence: the restored ability has arc_bolt_data")
	check(is_instance_valid(restored) and restored.evolution_gate_component.current_state == T2, "plasma persistence: the restored gate state is TIER_2_EVOLVED")
	check(is_instance_valid(restored) and is_equal_approx(restored.stats_container.get_final_stat_value(Stat.Type.CRIT_DOT_SHARE), 1.0), "plasma persistence: CRIT_DOT_SHARE reads 1.0 after the restore")

	# d. Chain link carries Burn along the line: the first target plus max_bounces (4) bats, not the sixth.
	var burn := load("res://resources/status_effects/burn.tres") as StatusEffect
	var origin := Vector2(60000.0, 60000.0)
	var chain := ChainLinkGeometry.new()
	world.add_child(chain)
	fx.track(chain)
	var bats: Array[Enemy] = []
	for i in range(6):
		var bat := _tough_bat()
		bat.set_physics_process(false)
		bat.global_position = origin + Vector2(100.0 * i, 0.0)
		bats.append(bat)
	await tree.physics_frame
	await tree.physics_frame
	var chain_payload := CombatPayload.new()
	chain_payload.stats_container_id = _make_stats({Stat.Type.CHAIN_RADIUS: 150.0}).get_instance_id()
	chain_payload.final_damage = 0.1
	chain_payload.dot_damage_snapshot = 5.0
	chain_payload.status_duration_snapshot = 3.0
	chain_payload.status_effects_to_apply.append(burn)
	chain.execute_geometry({"hit_nodes": [bats[0].hurtbox_component]}, chain_payload)
	var burning: Array[bool] = []
	for bat in bats:
		burning.append(bat.status_effect_component._active_effects.has("burn"))
	check(burning[0] and burning[1] and burning[2] and burning[3] and burning[4], "plasma chain: bats 1 to 5 end with Burn (first target plus four bounces)")
	check(not burning[5], "plasma chain: bat 6 has no Burn")

	# e. Guards.
	var arcane_profile := load(ARCANE_BOLT_STATS) as StatsProfile
	var arc_profile := load(ARC_BOLT_STATS) as StatsProfile
	check(not arcane_profile.base_stats.has(Stat.Type.CRIT_DOT_SHARE), "plasma guards: the shipped Arcane Bolt profile has no CRIT_DOT_SHARE key")
	check(arc_profile.base_stats.get(Stat.Type.CRIT_DOT_SHARE, 0.0) > 0.0, "plasma guards: the Arc Bolt profile's CRIT_DOT_SHARE is above 0")
	var all_positive := true
	for stat_type in [Stat.Type.CHAIN_RADIUS, Stat.Type.QUERY_RADIUS, Stat.Type.BASE_DAMAGE, Stat.Type.COOLDOWN, Stat.Type.DOT_DAMAGE]:
		all_positive = all_positive and arc_profile.base_stats.get(stat_type, 0.0) > 0.0
	check(all_positive, "plasma guards: the Arc Bolt profile has CHAIN_RADIUS, QUERY_RADIUS, BASE_DAMAGE, COOLDOWN and DOT_DAMAGE above 0")
	var targets_share := false
	for path in [FIRE_CARD, FROST_CARD, LIGHTNING_CARD, WIND_CARD, EARTH_CARD, DBG_MOVE_SPEED_CARD, DBG_OVERCLOCK_CARD, ARC_BOLT_CARD]:
		for modifier in (load(path) as UpgradeDefinition).stat_modifiers:
			targets_share = targets_share or modifier.target_stat_type == Stat.Type.CRIT_DOT_SHARE
	for path in ["res://resources/status_effects/burn.tres", "res://resources/status_effects/chill.tres"]:
		for modifier in (load(path) as StatusEffect).stat_modifiers:
			targets_share = targets_share or modifier.target_stat_type == Stat.Type.CRIT_DOT_SHARE
	check(not targets_share, "plasma guards: no real card, Burn or Chill modifier targets CRIT_DOT_SHARE")
	check(not Tags.Type.keys().has("PLASMA") and Tags.Type.size() == 22, "plasma guards: Tags.Type has no PLASMA entry and has 22 entries (SHOCKED added in Task AX)")
	check(int(Stat.Type.CRIT_DOT_SHARE) == 21, "plasma guards: CRIT_DOT_SHARE is appended as integer 21")


func _section_lightning_crit_multiplier() -> void:
	var lightning := load(LIGHTNING_CARD) as UpgradeDefinition
	var chance_step := 0.03
	var mult_step := 0.15

	# a. The real card: CRIT_CHANCE first (unchanged), then CRIT_MULTIPLIER.
	var mods := lightning.stat_modifiers
	check(mods.size() == 2, "lightning crit mult: the real card has exactly two modifiers")
	check(mods.size() == 2 and mods[0].target_stat_type == Stat.Type.CRIT_CHANCE and is_equal_approx(mods[0].value, chance_step), "lightning crit mult: the first modifier is CRIT_CHANCE, still 0.03")
	check(mods.size() == 2 and mods[1].target_stat_type == Stat.Type.CRIT_MULTIPLIER and is_equal_approx(mods[1].value, mult_step), "lightning crit mult: the second modifier is CRIT_MULTIPLIER, 0.15")
	if mods.size() != 2:
		return
	chance_step = mods[0].value
	mult_step = mods[1].value

	# b and c. Levels 0 to 3 in slot 1; a second ability in slot 2 is unaffected.
	var player := fx.fresh_player()
	var ability := fx.mount_arcane_bolt(player)
	var second_data := (load(fx.ARCANE_BOLT_DATA) as AbilityData).duplicate() as AbilityData
	second_data.slot_index = 2 as AbilityData.Role
	var second := player.ability_container.add_ability_from_data(second_data)
	var ledger := player.run_ledger_component
	for level in range(0, 4):
		if level > 0:
			ledger.log_slot_specific_purchase(lightning, 1)
		check(is_equal_approx(ability.stats_container.get_final_stat_value(Stat.Type.CRIT_MULTIPLIER), 1.5 + mult_step * level), "lightning crit mult: Lightning %d gives CRIT_MULTIPLIER %.2f" % [level, 1.5 + mult_step * level])
		check(is_equal_approx(ability.stats_container.get_final_stat_value(Stat.Type.CRIT_CHANCE), 0.05 + chance_step * level), "lightning crit mult: Lightning %d gives CRIT_CHANCE %.2f" % [level, 0.05 + chance_step * level])
	check(is_instance_valid(second) and is_equal_approx(second.stats_container.get_final_stat_value(Stat.Type.CRIT_MULTIPLIER), 1.5), "lightning crit mult: a slot 2 ability without Lightning stays at 1.5")

	# d. A forced-crit cast with Lightning 3.
	var cast_player := fx.fresh_player()
	var cast_ledger := cast_player.run_ledger_component
	for i in range(3):
		cast_ledger.log_slot_specific_purchase(lightning, 1)
	var cast_stats := _make_stats({
		Stat.Type.BASE_DAMAGE: 2.0,
		Stat.Type.CRIT_CHANCE: 1.0,
		Stat.Type.CRIT_MULTIPLIER: 1.5,
		Stat.Type.DOT_DAMAGE: 4.0,
		Stat.Type.CRIT_DOT_SHARE: 1.0,
	}, 1, cast_ledger)
	var payload := CombatCalculations.resolve_hit_crit(CombatCalculations.generate_hit_payload(null, cast_stats, null))
	var multiplier := 1.5 + mult_step * 3.0
	# Task AU: Lightning 3 also adds its indirect damage scale (CRIT_CHANCE 1.09 * 1.0, clamped to +50%), applied before the crit multiplier.
	check(is_equal_approx(payload.damage_scale, 1.5), "lightning crit mult: Lightning 3 with CRIT_CHANCE 1.09 gives damage_scale 1.5 (clamped)")
	check(payload.is_critical_hit and is_equal_approx(payload.final_damage, 2.0 * payload.damage_scale * multiplier), "lightning crit mult: a forced crit with Lightning 3 deals BASE_DAMAGE * damage_scale * 1.95")
	check(is_equal_approx(payload.dot_damage_snapshot, 4.0 * payload.damage_scale * (1.0 + (multiplier - 1.0) * 1.0)), "lightning crit mult: the Burn snapshot (scaled) follows the ledger-driven multiplier (share 1.0)")

	# e. The evolved Arc Bolt at Lightning 5.
	var evolved := _plasma_evolved_player()
	var arc := evolved.ability_container.get_ability_by_slot(1)
	for i in range(2):
		evolved.run_ledger_component.log_slot_specific_purchase(lightning, 1)
	check(is_instance_valid(arc) and is_equal_approx(arc.stats_container.get_final_stat_value(Stat.Type.CRIT_MULTIPLIER), 1.5 + mult_step * 5.0), "lightning crit mult: the evolved Arc Bolt at Lightning 5 reads CRIT_MULTIPLIER 2.25")
	check(is_instance_valid(arc) and is_equal_approx(arc.stats_container.get_final_stat_value(Stat.Type.CRIT_CHANCE), 0.05 + chance_step * 5.0), "lightning crit mult: the evolved Arc Bolt at Lightning 5 reads CRIT_CHANCE 0.05 + 0.15")

	# f. Guards.
	var others_clean := true
	for path in [FIRE_CARD, FROST_CARD, WIND_CARD, EARTH_CARD, DBG_MOVE_SPEED_CARD, DBG_OVERCLOCK_CARD]:
		for modifier in (load(path) as UpgradeDefinition).stat_modifiers:
			others_clean = others_clean and modifier.target_stat_type != Stat.Type.CRIT_MULTIPLIER
	check(others_clean, "lightning crit mult: Fire, Frost, Wind, Earth, Player Movement and Overclock have no CRIT_MULTIPLIER modifier")
	var lightning_clean := true
	for modifier in lightning.stat_modifiers:
		lightning_clean = lightning_clean and modifier.target_stat_type != Stat.Type.CRIT_DOT_SHARE and modifier.target_stat_type != Stat.Type.BASE_DAMAGE and modifier.target_stat_type != Stat.Type.DOT_DAMAGE
	check(lightning_clean, "lightning crit mult: the Lightning card has no modifier on CRIT_DOT_SHARE, BASE_DAMAGE or DOT_DAMAGE")


const TEST_BURST_EFFECT := "res://tools/headless/test_burst_effect.tscn"


## A test burst with the Task U fields. `shaped` false makes an effect-only burst.
func _ext_burst(id: StringName, fraction: float, carried: Array[Tags.Type], tag: Tags.Type = Tags.Type.NONE, shaped: bool = true, trigger: ImpactBurstDefinition.Trigger = ImpactBurstDefinition.Trigger.ON_HIT) -> ImpactBurstDefinition:
	var definition := _make_burst(id, trigger, fraction)
	definition.carried_status_tags = carried
	definition.required_target_tag = tag
	if not shaped:
		definition.shape = null
	return definition


func _ext_payload(stats: StatsContainer, damage: float, definition: ImpactBurstDefinition, effects: Array[StatusEffect] = []) -> CombatPayload:
	var bursts: Array[ImpactBurstDefinition] = [definition]
	var payload := _burst_payload(stats, damage, bursts)
	payload.status_effects_to_apply = effects
	payload.dot_damage_snapshot = 5.0
	payload.status_duration_snapshot = 3.0
	payload.status_ramp_cap_snapshot = 0.1
	return payload


func _section_burst_extensions() -> void:
	var stats := _make_stats({Stat.Type.AOE_RADIUS: 40.0})
	var burn := load("res://resources/status_effects/burn.tres") as StatusEffect
	var chill := load("res://resources/status_effects/chill.tres") as StatusEffect
	var burn_list: Array[StatusEffect] = [burn]
	var chill_list: Array[StatusEffect] = [chill]

	# a. Defaults: damage and no status.
	var plain := _ext_burst(&"test_ext_plain", 0.5, [])
	var bats := await _spawn_burst_bats(Vector2(70000.0, 70000.0), [Vector2(0, 0), Vector2(30, 0)])
	bats[0].hurtbox_component.take_hit(_ext_payload(stats, 10.0, plain, burn_list))
	await tree.process_frame
	await tree.process_frame
	check(is_equal_approx(_lost(bats[1]), 5.0) and bats[1].status_effect_component._active_effects.is_empty(), "burst ext: the defaults deal damage and apply no status to the neighbor")
	check(bats[0].status_effect_component._active_effects.has("burn"), "burst ext: the primary still gets the cast Burn")
	_free_bats(bats)

	# b. carried_status_tags [BURNING]: the neighbor gets Burn with the exact snapshots.
	var carrying := _ext_burst(&"test_ext_carry", 0.5, [Tags.Type.BURNING])
	bats = await _spawn_burst_bats(Vector2(70000.0, 71000.0), [Vector2(0, 0), Vector2(30, 0)])
	var primary_refreshed := [0]
	var neighbor_refreshed := [0]
	bats[0].status_effect_component.refreshed.connect(func(_instance: StatusEffectInstance) -> void: primary_refreshed[0] += 1)
	bats[1].status_effect_component.refreshed.connect(func(_instance: StatusEffectInstance) -> void: neighbor_refreshed[0] += 1)
	bats[0].hurtbox_component.take_hit(_ext_payload(stats, 10.0, carrying, burn_list))
	await tree.process_frame
	await tree.process_frame
	var neighbor_burn: StatusEffectInstance = bats[1].status_effect_component._active_effects.get("burn")
	check(neighbor_burn != null and is_equal_approx(neighbor_burn.dot_damage, 5.0) and is_equal_approx(neighbor_burn.duration_bonus, 3.0) and is_equal_approx(neighbor_burn.ramp_cap_bonus, 0.1), "burst ext: the neighbor Burn carries the cast dot, duration and ramp cap")
	var primary_burn: StatusEffectInstance = bats[0].status_effect_component._active_effects.get("burn")
	check(primary_burn != null and primary_refreshed[0] == 0 and neighbor_burn != null and neighbor_refreshed[0] == 0, "burst ext: the primary got no second application (no refresh) and the neighbor got its first")
	var seen: CombatPayload = _recorded[1][0]
	check(seen.is_burst and not seen.is_critical_hit and seen.impact_bursts.is_empty() and seen.status_effects_to_apply.size() == 1, "burst ext: the burst payload is is_burst, no crit, no bursts, and keeps the cast status")
	check(_recorded[0].size() == 1 and _recorded[1].size() == 1, "burst ext: no recursion (primary hit once, neighbor once)")
	_free_bats(bats)

	# c. damage_fraction 0 (a status-only burst), also with final_damage 0.
	var status_only := _ext_burst(&"test_ext_status_only", 0.0, [Tags.Type.BURNING])
	bats = await _spawn_burst_bats(Vector2(70000.0, 72000.0), [Vector2(0, 0), Vector2(30, 0)])
	bats[0].hurtbox_component.take_hit(_ext_payload(stats, 10.0, status_only, burn_list))
	await tree.process_frame
	await tree.process_frame
	check(bats[1].status_effect_component._active_effects.has("burn") and is_equal_approx(_lost(bats[1]), 0.0), "burst ext: damage_fraction 0 gives the neighbor Burn and no health loss")
	_free_bats(bats)
	bats = await _spawn_burst_bats(Vector2(70000.0, 73000.0), [Vector2(0, 0), Vector2(30, 0)])
	bats[0].hurtbox_component.take_hit(_ext_payload(stats, 0.0, status_only, burn_list))
	await tree.process_frame
	await tree.process_frame
	check(bats[1].status_effect_component._active_effects.has("burn") and is_equal_approx(_lost(bats[1]), 0.0) and is_equal_approx(_lost(bats[0]), 0.0), "burst ext: final_damage 0 with a status-only burst changes no health")
	_free_bats(bats)

	# d. The required tag is checked before the hit own statuses.
	var needs_chill := _ext_burst(&"test_ext_needs_chill", 0.5, [], Tags.Type.CHILLED)
	bats = await _spawn_burst_bats(Vector2(70000.0, 74000.0), [Vector2(0, 0), Vector2(30, 0)])
	bats[0].hurtbox_component.take_hit(_ext_payload(stats, 10.0, needs_chill))
	await tree.process_frame
	await tree.process_frame
	check(is_equal_approx(_lost(bats[1]), 0.0), "burst ext: an un-chilled primary does not fire a CHILLED burst")
	_free_bats(bats)
	bats = await _spawn_burst_bats(Vector2(70000.0, 75000.0), [Vector2(0, 0), Vector2(30, 0)])
	bats[0].status_effect_component.apply_effect(chill, 0.0, 3.0, 0.0)
	bats[0].hurtbox_component.take_hit(_ext_payload(stats, 10.0, needs_chill))
	await tree.process_frame
	await tree.process_frame
	check(is_equal_approx(_lost(bats[1]), 5.0), "burst ext: a chilled primary fires a CHILLED burst")
	_free_bats(bats)
	bats = await _spawn_burst_bats(Vector2(70000.0, 76000.0), [Vector2(0, 0), Vector2(30, 0)])
	bats[0].hurtbox_component.take_hit(_ext_payload(stats, 10.0, needs_chill, chill_list))
	await tree.process_frame
	await tree.process_frame
	check(bats[0].tag_component.has_tag(Tags.Type.CHILLED) and is_equal_approx(_lost(bats[1]), 0.0), "burst ext: the hit own Chill does not count (the first hit does not fire, the primary is chilled afterwards)")
	bats[0].hurtbox_component.take_hit(_ext_payload(stats, 10.0, needs_chill, chill_list))
	await tree.process_frame
	await tree.process_frame
	check(is_equal_approx(_lost(bats[1]), 5.0), "burst ext: the second hit fires the CHILLED burst")
	_free_bats(bats)
	var always := _ext_burst(&"test_ext_always", 0.5, [])
	bats = await _spawn_burst_bats(Vector2(70000.0, 77000.0), [Vector2(0, 0), Vector2(30, 0)])
	bats[0].hurtbox_component.take_hit(_ext_payload(stats, 10.0, always))
	await tree.process_frame
	await tree.process_frame
	check(is_equal_approx(_lost(bats[1]), 5.0), "burst ext: a NONE condition always fires")
	var ownerless := HurtboxComponent.new()
	fx.track(ownerless)
	var both: Array[ImpactBurstDefinition] = [needs_chill, always]
	var qualifying := ownerless._get_qualifying_bursts(_burst_payload(stats, 10.0, both))
	check(qualifying.size() == 1 and qualifying[0] == always, "burst ext: a hurtbox with no owner entity fails a non-NONE condition and passes NONE")
	_free_bats(bats)

	# e. ON_CRIT plus a condition: both are required.
	var crit_chill := _ext_burst(&"test_ext_crit_chill", 0.5, [], Tags.Type.CHILLED, true, ImpactBurstDefinition.Trigger.ON_CRIT)
	var crit_list: Array[ImpactBurstDefinition] = [crit_chill]
	bats = await _spawn_burst_bats(Vector2(70000.0, 78000.0), [Vector2(0, 0)])
	var hurtbox := bats[0].hurtbox_component
	var crit_payload := _burst_payload(stats, 10.0, crit_list, true)
	var plain_payload := _burst_payload(stats, 10.0, crit_list, false)
	check(hurtbox._get_qualifying_bursts(crit_payload).is_empty(), "burst ext: a crit on an un-chilled primary does not qualify")
	bats[0].status_effect_component.apply_effect(chill, 0.0, 3.0, 0.0)
	check(hurtbox._get_qualifying_bursts(plain_payload).is_empty(), "burst ext: a non-crit on a chilled primary does not qualify")
	check(hurtbox._get_qualifying_bursts(crit_payload).size() == 1, "burst ext: a crit on a chilled primary qualifies")
	_free_bats(bats)

	# f. A chilled primary killed by the hit still fires the burst.
	bats = await _spawn_burst_bats(Vector2(70000.0, 79000.0), [Vector2(0, 0), Vector2(30, 0)])
	bats[0].health_component.update_max_health(20.0, true)
	bats[0].health_component.set_to_full()
	bats[0].status_effect_component.apply_effect(chill, 0.0, 3.0, 0.0)
	var neighbor := bats[1]
	bats[0].hurtbox_component.take_hit(_ext_payload(stats, 100.0, needs_chill))
	await tree.process_frame
	await tree.process_frame
	check(is_equal_approx(_lost(neighbor), 50.0), "burst ext: a chilled primary killed by the hit still fires the burst (50 of 100)")
	neighbor.queue_free()

	# g. Effect-only burst (no shape).
	var effect_scene := load(TEST_BURST_EFFECT) as PackedScene
	var origin := Vector2(70000.0, 80000.0)
	var effect_only := _ext_burst(&"test_ext_effect_only", 0.5, [], Tags.Type.NONE, false)
	effect_only.effect_scene = effect_scene
	_clear_test_effects()
	bats = await _spawn_burst_bats(origin, [Vector2(0, 0)])
	var source := _ext_payload(stats, 10.0, effect_only)
	bats[0].hurtbox_component.take_hit(source)
	await tree.process_frame
	await tree.process_frame
	var got: CombatPayload = TestBurstEffect.received[0] if TestBurstEffect.received.size() == 1 else null
	check(TestBurstEffect.instances.size() == 1 and TestBurstEffect.instances[0].global_position.is_equal_approx(origin), "burst ext: an effect-only burst spawns its effect once at the primary position")
	check(got != null and got != source and is_equal_approx(got.dot_damage_snapshot, 5.0) and is_equal_approx(got.status_duration_snapshot, 3.0), "burst ext: the effect got a copy of the payload with the same snapshots")
	check(source.impact_bursts.size() == 1 and not source.is_burst and is_equal_approx(source.final_damage, 10.0), "burst ext: the source payload is unchanged")
	check(is_equal_approx(_lost(bats[0]), 10.0) and _recorded[0].size() == 1, "burst ext: an effect-only burst deals no damage (the primary only took its own hit)")
	_free_bats(bats)
	_clear_test_effects()

	# h. Shaped burst: the effect only when something is caught.
	var shaped_effect := _ext_burst(&"test_ext_shaped_effect", 0.5, [])
	shaped_effect.effect_scene = effect_scene
	bats = await _spawn_burst_bats(Vector2(70000.0, 81000.0), [Vector2(0, 0)])
	bats[0].hurtbox_component.take_hit(_ext_payload(stats, 10.0, shaped_effect))
	await tree.process_frame
	await tree.process_frame
	check(TestBurstEffect.instances.is_empty() and TestBurstEffect.received.is_empty(), "burst ext: a shaped burst that catches nothing spawns no effect")
	_free_bats(bats)
	bats = await _spawn_burst_bats(Vector2(70000.0, 82000.0), [Vector2(0, 0), Vector2(30, 0)])
	bats[0].hurtbox_component.take_hit(_ext_payload(stats, 10.0, shaped_effect))
	await tree.process_frame
	await tree.process_frame
	check(TestBurstEffect.instances.size() == 1 and TestBurstEffect.received.size() == 1, "burst ext: a shaped burst that catches a target spawns the effect once, configured")
	_free_bats(bats)
	_clear_test_effects()

	# i. A scene that is not a BurstEffect spawns as before.
	var plain_node := Node2D.new()
	plain_node.name = "test_plain_effect"
	var plain_scene := PackedScene.new()
	plain_scene.pack(plain_node)
	plain_node.free()
	var plain_effect := _ext_burst(&"test_ext_plain_effect", 0.5, [])
	plain_effect.effect_scene = plain_scene
	bats = await _spawn_burst_bats(Vector2(70000.0, 83000.0), [Vector2(0, 0), Vector2(30, 0)])
	bats[0].hurtbox_component.take_hit(_ext_payload(stats, 10.0, plain_effect))
	await tree.process_frame
	await tree.process_frame
	var spawned := tree.root.find_child("test_plain_effect", true, false)
	check(spawned != null and is_equal_approx(_lost(bats[1]), 5.0), "burst ext: a non-BurstEffect effect scene is spawned as before")
	if spawned != null:
		spawned.queue_free()
	_free_bats(bats)

	# j. Guards: the only shipped bursts are Task AE's two, and neither uses the extension fields.
	var users: Array[String] = []
	var burst_ids: Array[String] = []
	var uses_extension := 0
	for path in _list_tres("res://resources"):
		var resource := load(path)
		if resource is UpgradeDefinition and (resource as UpgradeDefinition).impact_burst_payload != null:
			users.append((resource as UpgradeDefinition).upgrade_id)
		if resource is ImpactBurstDefinition:
			var shipped := resource as ImpactBurstDefinition
			burst_ids.append(String(shipped.burst_id))
			if shipped.burst_id != &"shatter" and shipped.burst_id != &"magma_lava" and shipped.burst_id != &"blizzard_vortex" and (not shipped.carried_status_tags.is_empty() or shipped.required_target_tag != Tags.Type.NONE or shipped.per_enemy_bonus != 0.0):
				uses_extension += 1
	users.sort()
	burst_ids.sort()
	check(users == ["compound_blizzard_evolve", "compound_blizzard_overclock", "compound_magma_evolve", "compound_magma_overclock", "compound_shatter_evolve", "compound_shatter_overclock", "compound_storm_evolve", "compound_storm_overclock"], "burst ext guards: only the eight compound cards (Shatter, Magma, Storm, Blizzard) carry an impact_burst_payload (found %s)" % str(users))
	check(burst_ids == ["blizzard_vortex", "magma_lava", "shatter", "storm_strike"] and uses_extension == 0, "burst ext guards: the only shipped ImpactBurstDefinitions are blizzard_vortex, magma_lava, shatter and storm_strike, and only the first three use the extension fields (found %s)" % str(burst_ids))


func _section_burst_status_filter() -> void:
	var stats := _make_stats({Stat.Type.AOE_RADIUS: 40.0})
	var burn := load("res://resources/status_effects/burn.tres") as StatusEffect
	var chill := load("res://resources/status_effects/chill.tres") as StatusEffect
	var untagged := StatusEffect.new()
	untagged.effect_id = "test_untagged"
	var both_list: Array[StatusEffect] = [burn, chill]
	var origin := Vector2(70000.0, 120000.0)

	# a. Empty list: the neighbor's burst hit carries nothing; the primary still gets the cast's statuses.
	var none_def := _ext_burst(&"test_filter_none", 0.5, [])
	var bats := await _spawn_burst_bats(origin, [Vector2(0, 0), Vector2(30, 0)])
	bats[0].hurtbox_component.take_hit(_ext_payload(stats, 10.0, none_def, both_list))
	await tree.process_frame
	await tree.process_frame
	var burst_seen: CombatPayload = _recorded[1][0] if _recorded[1].size() == 1 else null
	check(burst_seen != null and burst_seen.status_effects_to_apply.is_empty() and bats[1].status_effect_component._active_effects.is_empty(), "burst filter: an empty list carries no status")
	check(bats[0].status_effect_component._active_effects.has("burn") and bats[0].status_effect_component._active_effects.has("chill"), "burst filter: the primary still gets both cast statuses")
	_free_bats(bats)

	# b. [BURNING] carries Burn only. c. [CHILLED] carries Chill only. d. Both carry both.
	var cases := [
		{"tags": [Tags.Type.BURNING], "ids": ["burn"], "label": "[BURNING]"},
		{"tags": [Tags.Type.CHILLED], "ids": ["chill"], "label": "[CHILLED]"},
		{"tags": [Tags.Type.BURNING, Tags.Type.CHILLED], "ids": ["burn", "chill"], "label": "both tags"},
	]
	var row := 1
	for case in cases:
		var tag_list: Array[Tags.Type] = []
		tag_list.assign(case["tags"])
		var definition := _ext_burst(StringName("test_filter_%d" % row), 0.5, tag_list)
		bats = await _spawn_burst_bats(origin + Vector2(0, 1000.0 * row), [Vector2(0, 0), Vector2(30, 0)])
		var source := _ext_payload(stats, 10.0, definition, both_list)
		bats[0].hurtbox_component.take_hit(source)
		await tree.process_frame
		await tree.process_frame
		var carried_ids: Array[String] = []
		var snapshots_match := false
		if _recorded[1].size() == 1:
			var seen: CombatPayload = _recorded[1][0]
			for status in seen.status_effects_to_apply:
				carried_ids.append(status.effect_id)
			snapshots_match = is_equal_approx(seen.dot_damage_snapshot, source.dot_damage_snapshot) and is_equal_approx(seen.status_duration_snapshot, source.status_duration_snapshot) and is_equal_approx(seen.status_ramp_cap_snapshot, source.status_ramp_cap_snapshot)
		var expected_ids: Array[String] = []
		expected_ids.assign(case["ids"])
		var neighbor_effects: Dictionary = bats[1].status_effect_component._active_effects
		check(carried_ids == expected_ids and neighbor_effects.size() == expected_ids.size(), "burst filter: %s carries exactly %s (carried %s)" % [case["label"], str(expected_ids), str(carried_ids)])
		check(snapshots_match, "burst filter: %s keeps the cast snapshots on the burst payload" % case["label"])
		check(source.status_effects_to_apply.size() == 2 and source.status_effects_to_apply[0] == burn and source.status_effects_to_apply[1] == chill, "burst filter: %s leaves the source payload statuses untouched" % case["label"])
		_free_bats(bats)
		row += 1

	# e. A status with no granted_tags is never carried, whatever the list holds.
	var all_tags: Array[Tags.Type] = [Tags.Type.BURNING, Tags.Type.CHILLED, Tags.Type.NONE]
	var all_def := _ext_burst(&"test_filter_untagged", 0.5, all_tags)
	var untagged_list: Array[StatusEffect] = [untagged]
	check(untagged.granted_tags.is_empty() and ImpactBurst.carried_statuses(all_def, untagged_list).is_empty(), "burst filter: a status with no granted_tags is never carried")

	# f. carried_statuses ignores null entries, returns a new array and does not mutate its input.
	var with_null: Array[StatusEffect] = [null, burn, null, chill]
	var carried := ImpactBurst.carried_statuses(all_def, with_null)
	check(carried.size() == 2 and carried[0] == burn and carried[1] == chill and with_null.size() == 4 and with_null[1] == burn, "burst filter: carried_statuses skips null entries and leaves its input alone")
	check(not is_same(carried, with_null), "burst filter: carried_statuses returns a new array")

	# g. A lingering zone's payload is filtered by the same list.
	_clear_test_effects()
	var effect_scene := load(TEST_BURST_EFFECT) as PackedScene
	var burn_only: Array[Tags.Type] = [Tags.Type.BURNING]
	var zone_def := _ext_burst(&"test_filter_zone", 0.0, burn_only, Tags.Type.NONE, false)
	zone_def.effect_scene = effect_scene
	var zone_source := _ext_payload(stats, 10.0, zone_def, both_list)
	ImpactBurst.run(zone_def, zone_source, origin + Vector2(0, 9000.0), 0, tree.root.get_world_2d())
	var zone_seen: CombatPayload = TestBurstEffect.received[0] if TestBurstEffect.received.size() == 1 else null
	check(zone_seen != null and zone_seen.status_effects_to_apply.size() == 1 and zone_seen.status_effects_to_apply[0] == burn and zone_seen.is_burst and zone_seen.impact_bursts.is_empty() and not zone_seen.is_critical_hit, "burst filter: the effect payload carries only the listed statuses and keeps is_burst, no bursts, no crit")
	check(is_equal_approx(zone_seen.dot_damage_snapshot, 5.0) and is_equal_approx(zone_seen.status_duration_snapshot, 3.0) and is_equal_approx(zone_seen.status_ramp_cap_snapshot, 0.1), "burst filter: the effect payload keeps the cast snapshots")
	check(zone_source.status_effects_to_apply.size() == 2, "burst filter: the effect's source payload keeps both statuses")
	_clear_test_effects()

	var zone_scene := load(TEST_LINGERING_ZONE) as PackedScene
	LingeringZone.reset_registry()
	var chill_only: Array[Tags.Type] = [Tags.Type.CHILLED]
	var real_zone_def := _ext_burst(&"test_filter_real_zone", 0.0, chill_only, Tags.Type.NONE, false)
	real_zone_def.effect_scene = zone_scene
	bats = await _spawn_burst_bats(origin + Vector2(0, 10000.0), [Vector2(0, 0)])
	var zone := await _spawn_zone(real_zone_def, _zone_payload(stats, real_zone_def, both_list), origin + Vector2(0, 10000.0))
	await tree.create_timer(0.15).timeout
	var zone_effects: Dictionary = bats[0].status_effect_component._active_effects
	check(zone != null and zone_effects.has("chill") and not zone_effects.has("burn"), "burst filter: a lingering zone applies only the listed status (Chill, not Burn)")
	_free_bats(bats)
	if is_instance_valid(zone):
		zone.queue_free()
	await tree.process_frame
	LingeringZone.reset_registry()


const SHATTER_EVOLVE_CARD := "res://resources/compounds/shatter_evolution_upgrade_def.tres"
const SHATTER_OVERCLOCK_CARD := "res://resources/compounds/shatter_overclock_upgrade_def.tres"
const SHATTER_BURST := "res://resources/bursts/shatter.tres"
const ARCANE_BOLT_DATA_PATH := "res://resources/abilities/arcane_bolt/arcane_bolt_data.tres"


## Fresh player with Arcane Bolt and `count` levels of each of two infusion cards in slot 1.
func _socket_pair(first: UpgradeDefinition, second: UpgradeDefinition, count: int) -> Player:
	var player := fx.fresh_player()
	fx.mount_arcane_bolt(player)
	for i in range(count):
		player.run_ledger_component.log_slot_specific_purchase(first, 1)
		player.run_ledger_component.log_slot_specific_purchase(second, 1)
	return player


func _offer_ids(offer: Array[UpgradeChoice]) -> Array[String]:
	var ids: Array[String] = []
	for choice in offer:
		ids.append(choice.definition.upgrade_id)
	return ids


func _section_compound_offer() -> void:
	var T1 := EvolutionGateComponent.EvolutionState.TIER_1_BASE
	var T2 := EvolutionGateComponent.EvolutionState.TIER_2_EVOLVED
	var mgr := fx.get_upgrade_manager()
	var fire := load(FIRE_CARD) as UpgradeDefinition
	var frost := load(FROST_CARD) as UpgradeDefinition
	var lightning := load(LIGHTNING_CARD) as UpgradeDefinition
	var wind := load(WIND_CARD) as UpgradeDefinition
	var earth := load(EARTH_CARD) as UpgradeDefinition
	var evolve_card := load(SHATTER_EVOLVE_CARD) as UpgradeDefinition
	var overclock_card := load(SHATTER_OVERCLOCK_CARD) as UpgradeDefinition
	var shatter := load(SHATTER_BURST) as ImpactBurstDefinition

	# a. Data.
	check(evolve_card.is_compound_card() and overclock_card.is_compound_card() and evolve_card.payload_type == UpgradeDefinition.PayloadType.ABILITY_UNLOCK and overclock_card.payload_type == UpgradeDefinition.PayloadType.ABILITY_OVERCLOCK, "compound data: both Shatter cards are compound cards (evolution = ABILITY_UNLOCK, Overclock = ABILITY_OVERCLOCK)")
	check(evolve_card.compound_pair == overclock_card.compound_pair and evolve_card.compound_pair.has(Tags.Type.FROST) and evolve_card.compound_pair.has(Tags.Type.EARTH) and evolve_card.impact_burst_payload == shatter and overclock_card.impact_burst_payload == shatter, "compound data: both cards name Frost + Earth and carry the same shatter burst")
	check(evolve_card.evolves_from == null and evolve_card.ability_data_payload == null and not (load(DBG_OVERCLOCK_CARD) as UpgradeDefinition).is_compound_card() and not earth.is_compound_card(), "compound data: the evolution card has no evolves_from or ability data; the generic Overclock and infusion cards are not compound cards")
	check(shatter.burst_id == &"shatter" and shatter.trigger == ImpactBurstDefinition.Trigger.ON_HIT and shatter.required_target_tag == Tags.Type.CHILLED and shatter.carried_status_tags == [Tags.Type.CHILLED] and is_equal_approx(shatter.damage_fraction, 0.5) and is_equal_approx(shatter.per_enemy_bonus, 0.0) and shatter.unlock_level == 1 and shatter.max_per_cast == 2 and is_equal_approx((shatter.shape as CircleBurstShape).radius_multiplier, 8.0), "compound data: the shatter burst definition (ON_HIT, CHILLED target, carries CHILLED, 0.5, cap 2, radius 8)")

	# b. Pair detection.
	var player := _socket_pair(frost, earth, 3)
	var ability := player.ability_container.get_ability_by_slot(1)
	var pair := mgr.get_compound_pair(ability)
	check(pair.size() == 2 and pair.has(Tags.Type.FROST) and pair.has(Tags.Type.EARTH), "compound pair: Frost 3 + Earth 3 at tier 1 gives the pair")
	# The fixture's player is one shared object: each scenario below resets it and builds its own state.
	player = _socket_pair(frost, frost, 0)
	for i in range(3):
		player.run_ledger_component.log_slot_specific_purchase(frost, 1)
	check(mgr.get_compound_pair(player.ability_container.get_ability_by_slot(1)).is_empty(), "compound pair: one element gives none")
	player = _socket_pair(frost, earth, 3)
	for i in range(3):
		player.run_ledger_component.log_slot_specific_purchase(fire, 1)
	check(mgr.get_compound_pair(player.ability_container.get_ability_by_slot(1)).is_empty(), "compound pair: three elements give none")
	player = _socket_pair(frost, earth, 2)
	check(mgr.get_compound_pair(player.ability_container.get_ability_by_slot(1)).is_empty(), "compound pair: two elements below level 3 give none")
	check(mgr.get_compound_pair(null).is_empty(), "compound pair: a null ability gives none")
	player = _socket_pair(frost, earth, 3)
	ability = player.ability_container.get_ability_by_slot(1)

	# c. The offer for Frost 3 + Earth 3.
	check(mgr._find_next_offer_slot(player) == 1, "compound offer: Frost 3 + Earth 3 makes slot 1 offer-eligible")
	var offer := mgr._build_offer_choices(player, 1)
	check(_offer_ids(offer) == ["compound_shatter_evolve", "compound_shatter_overclock"], "compound offer: exactly Evolve + Shatter and Overclock + Shatter, no generic Overclock (got %s)" % str(_offer_ids(offer)))
	check(offer.size() == 2 and offer[0].is_forced_offer and offer[0].target_slot_index == 1 and offer[1].target_slot_index == 1, "compound offer: both cards are forced offers for slot 1")

	# d. Unchanged offers.
	var arc_player := _socket_pair(fire, lightning, 3)
	var arc_offer := mgr._build_offer_choices(arc_player, 1)
	check(arc_offer.size() == 2 and arc_offer[0].definition.upgrade_id == "evolve_arc_bolt" and arc_offer[1].definition.upgrade_id == "overclock", "compound offer: Fire 3 + Lightning 3 still offers Arc Bolt and the generic Overclock")
	var fire_frost := _socket_pair(fire, frost, 3)
	var fire_frost_offer := mgr._build_offer_choices(fire_frost, 1)
	check(fire_frost_offer.size() == 1 and fire_frost_offer[0].definition.upgrade_id == "overclock", "compound offer: Fire 3 + Frost 3 still offers only the generic Overclock")

	# e. Never in level-up drafts or the debug grant list; an already-bought card for the slot is not re-offered.
	var leaked := false
	for choice in mgr.generate_selection_pool(player, 99):
		leaked = leaked or choice.definition.is_compound_card()
	check(not leaked, "compound pool: neither compound card appears in generate_selection_pool")
	var grantable_leak := false
	for entry in DebugActions.grantable_cards(mgr):
		grantable_leak = grantable_leak or (entry["definition"] as UpgradeDefinition).is_compound_card()
	check(not grantable_leak, "compound pool: neither compound card appears in grantable_cards")

	# f. Apply Evolve + Shatter.
	player = _socket_pair(frost, earth, 3)
	ability = player.ability_container.get_ability_by_slot(1)
	var tags: Array[Tags.Type] = ability.tag_component.get_permanent_tags()
	var ledger := player.run_ledger_component
	player.apply_contextual_upgrade(offer[0])
	var gate := ability.evolution_gate_component
	var tracker := ability.infusion_tracker_component
	var slot_key := PurchaseKey.make("compound_shatter_evolve", 1)
	check(gate.current_state == T2, "compound evolve: the gate state is TIER_2_EVOLVED")
	check(ledger.purchase_registry.has(slot_key) and not ledger.purchase_registry.has("compound_shatter_evolve"), "compound evolve: the slot-specific key exists and the plain key does not")
	var bursts := ledger.get_impact_bursts(1, tags)
	check(bursts.has(shatter) and not ledger.get_impact_bursts(2, tags).has(shatter), "compound evolve: slot 1 resolves the shatter burst and slot 2 does not (Earth's own explosion also resolves for slot 1)")
	check(not ledger.is_overclocked(1) and ability.data.resource_path == ARCANE_BOLT_DATA_PATH, "compound evolve: not overclocked and the ability data is unchanged (no swap)")
	check(mgr.get_compound_pair(ability).is_empty() and mgr._find_next_offer_slot(player) == 0, "compound evolve: no pair and no further offer at tier 2")
	check(tracker.is_element_socket_allowed(Tags.Type.WIND, gate.current_state, gate.is_permanently_overclocked), "compound evolve: a third element is accepted")
	ledger.log_slot_specific_purchase(wind, 1)
	check(not tracker.is_element_socket_allowed(Tags.Type.LIGHTNING, gate.current_state, gate.is_permanently_overclocked), "compound evolve: a fourth element is refused")
	player.capture_run_state()
	ledger.restore_state({}, [])
	player.ability_container.remove_ability_by_slot(1)
	player._restore_run_state()
	var restored := player.ability_container.get_ability_by_slot(1)
	check(is_instance_valid(restored) and restored.evolution_gate_component.current_state == T2, "compound persistence: the evolution state survives capture and restore")
	check(is_instance_valid(restored) and player.run_ledger_component.get_impact_bursts(1, restored.tag_component.get_permanent_tags()).has(shatter), "compound persistence: the shatter burst still resolves after the restore")

	# g. Apply Overclock + Shatter.
	var oc_player := _socket_pair(frost, earth, 3)
	var oc_ability := oc_player.ability_container.get_ability_by_slot(1)
	var oc_tags: Array[Tags.Type] = oc_ability.tag_component.get_permanent_tags()
	var oc_offer := mgr._build_offer_choices(oc_player, 1)
	oc_player.apply_contextual_upgrade(oc_offer[1])
	var oc_ledger := oc_player.run_ledger_component
	check(oc_ledger.is_overclocked(1) and oc_ability.evolution_gate_component.current_state == T1, "compound overclock: the slot is overclocked and stays in TIER_1_BASE")
	check(oc_ledger.get_impact_bursts(1, oc_tags).has(shatter) and not oc_ledger.get_impact_bursts(2, oc_tags).has(shatter), "compound overclock: the shatter burst resolves for slot 1 only")
	check(mgr._find_next_offer_slot(oc_player) == 0, "compound overclock: no further offer for the slot")

	# g2. A compound card already bought for the slot is not offered again.
	var bought := _socket_pair(frost, earth, 3)
	bought.run_ledger_component.log_slot_specific_purchase(evolve_card, 1)
	var bought_offer := mgr._build_offer_choices(bought, 1)
	check(_offer_ids(bought_offer) == ["compound_shatter_overclock"], "compound offer: an Evolve + Shatter already bought for the slot is not offered again (got %s)" % str(_offer_ids(bought_offer)))

	# h. Shatter in play with real hurtboxes.
	var stats := _make_stats({Stat.Type.AOE_RADIUS: 5.0})
	var burn := load("res://resources/status_effects/burn.tres") as StatusEffect
	var chill := load("res://resources/status_effects/chill.tres") as StatusEffect
	var both: Array[StatusEffect] = [burn, chill]
	var origin := Vector2(70000.0, 130000.0)
	var bats := await _spawn_burst_bats(origin, [Vector2(0, 0), Vector2(30, 0), Vector2(80, 0)])
	bats[0].status_effect_component.apply_effect(chill, 0.0, 3.0, 0.0)
	bats[0].hurtbox_component.take_hit(_ext_payload(stats, 10.0, shatter, both))
	await tree.process_frame
	await tree.process_frame
	check(is_equal_approx(_lost(bats[1]), 5.0) and bats[1].status_effect_component._active_effects.has("chill"), "shatter: a chilled primary shatters; the neighbor in range loses 0.5 of the hit and is chilled")
	check(not bats[1].status_effect_component._active_effects.has("burn"), "shatter: with Burn and Chill on the cast, the neighbor gets Chill and not Burn")
	check(is_equal_approx(_lost(bats[2]), 0.0) and bats[2].status_effect_component._active_effects.is_empty(), "shatter: a neighbor out of range is untouched")
	check(is_equal_approx(_lost(bats[0]), 10.0) and _recorded[0].size() == 1 and _recorded[1].size() == 1 and (_recorded[1][0] as CombatPayload).is_burst, "shatter: the primary takes only its own hit and the burst does not recurse")
	_free_bats(bats)

	# i. An un-chilled primary fires nothing; the hit's own Chill does not count on the first hit.
	bats = await _spawn_burst_bats(origin + Vector2(0, 1000.0), [Vector2(0, 0), Vector2(30, 0)])
	bats[0].hurtbox_component.take_hit(_ext_payload(stats, 10.0, shatter, both))
	await tree.process_frame
	await tree.process_frame
	check(is_equal_approx(_lost(bats[1]), 0.0) and bats[0].tag_component.has_tag(Tags.Type.CHILLED), "shatter: an un-chilled primary fires nothing (the hit's own Chill does not count on the first hit)")
	bats[0].hurtbox_component.take_hit(_ext_payload(stats, 10.0, shatter, both))
	await tree.process_frame
	await tree.process_frame
	check(is_equal_approx(_lost(bats[1]), 5.0), "shatter: the second hit, on the now chilled primary, shatters")
	_free_bats(bats)

	# j. At most 2 per cast, through the cast's shared CastBudget.
	bats = await _spawn_burst_bats(origin + Vector2(0, 2000.0), [Vector2(0, 0), Vector2(30, 0), Vector2(5000, 0), Vector2(5030, 0), Vector2(10000, 0), Vector2(10030, 0)])
	var capped := _ext_payload(stats, 10.0, shatter, both)
	capped.cast_budget = CastBudget.new()
	capped.cast_id = 424242
	for primary in [0, 2, 4]:
		bats[primary].status_effect_component.apply_effect(chill, 0.0, 3.0, 0.0)
	for primary in [0, 2, 4]:
		bats[primary].hurtbox_component.take_hit(capped)
	await tree.process_frame
	await tree.process_frame
	var shattered := 0
	for neighbor in [1, 3, 5]:
		if is_equal_approx(_lost(bats[neighbor]), 5.0):
			shattered += 1
	check(shattered == 2 and is_equal_approx(_lost(bats[5]), 0.0), "shatter: at most 2 shatters per cast (the third chilled primary's neighbor is untouched)")
	_free_bats(bats)


const MAGMA_EVOLVE_CARD := "res://resources/compounds/magma_evolution_upgrade_def.tres"
const MAGMA_OVERCLOCK_CARD := "res://resources/compounds/magma_overclock_upgrade_def.tres"
const MAGMA_BURST := "res://resources/bursts/magma_lava.tres"
const LAVA_ZONE_SCENE := "res://scenes/effects/lava_zone.tscn"


func _section_magma() -> void:
	var T1 := EvolutionGateComponent.EvolutionState.TIER_1_BASE
	var T2 := EvolutionGateComponent.EvolutionState.TIER_2_EVOLVED
	var mgr := fx.get_upgrade_manager()
	var fire := load(FIRE_CARD) as UpgradeDefinition
	var frost := load(FROST_CARD) as UpgradeDefinition
	var lightning := load(LIGHTNING_CARD) as UpgradeDefinition
	var earth := load(EARTH_CARD) as UpgradeDefinition
	var evolve_card := load(MAGMA_EVOLVE_CARD) as UpgradeDefinition
	var overclock_card := load(MAGMA_OVERCLOCK_CARD) as UpgradeDefinition
	var lava := load(MAGMA_BURST) as ImpactBurstDefinition
	var lava_scene := load(LAVA_ZONE_SCENE) as PackedScene
	LingeringZone.reset_registry()

	# a. Data.
	check(evolve_card.is_compound_card() and overclock_card.is_compound_card() and evolve_card.payload_type == UpgradeDefinition.PayloadType.ABILITY_UNLOCK and overclock_card.payload_type == UpgradeDefinition.PayloadType.ABILITY_OVERCLOCK, "magma data: both Magma cards are compound cards (ABILITY_UNLOCK and ABILITY_OVERCLOCK)")
	check(evolve_card.compound_pair.has(Tags.Type.FIRE) and evolve_card.compound_pair.has(Tags.Type.EARTH) and overclock_card.compound_pair == evolve_card.compound_pair and evolve_card.impact_burst_payload == lava and overclock_card.impact_burst_payload == lava, "magma data: both cards name Fire + Earth and carry the lava burst")
	check(evolve_card.evolves_from == null and evolve_card.ability_data_payload == null and overclock_card.ability_data_payload == null, "magma data: no ability data and no evolves_from")
	check(lava.burst_id == &"magma_lava" and lava.trigger == ImpactBurstDefinition.Trigger.ON_HIT and lava.shape == null and lava.effect_scene == lava_scene and lava.carried_status_tags == [Tags.Type.BURNING] and lava.required_target_tag == Tags.Type.NONE and lava.unlock_level == 1 and lava.max_per_cast == 1, "magma data: the lava burst is effect-only, ON_HIT, carries only BURNING, level 1, cap 1")
	var zone_probe := lava_scene.instantiate() as LingeringZone
	check(zone_probe != null and zone_probe.zone_id == &"magma_lava" and is_equal_approx(zone_probe.lifetime, 4.0) and is_equal_approx(zone_probe.apply_interval, 0.5) and is_equal_approx(zone_probe.radius_multiplier, 6.0) and is_equal_approx(zone_probe.merge_distance, 40.0) and zone_probe.max_live_zones == 8, "magma data: the lava zone scene's exports (4 s, 0.5 s, radius 6, merge 40, cap 8)")
	if zone_probe != null:
		zone_probe.free()

	# b. Offers.
	var player := _socket_pair(fire, earth, 3)
	check(mgr._find_next_offer_slot(player) == 1, "magma offer: Fire 3 + Earth 3 makes slot 1 offer-eligible")
	var offer := mgr._build_offer_choices(player, 1)
	check(_offer_ids(offer) == ["compound_magma_evolve", "compound_magma_overclock"], "magma offer: exactly Evolve + Magma and Overclock + Magma (got %s)" % str(_offer_ids(offer)))
	player = _socket_pair(frost, earth, 3)
	check(_offer_ids(mgr._build_offer_choices(player, 1)) == ["compound_shatter_evolve", "compound_shatter_overclock"], "magma offer: Frost 3 + Earth 3 still offers the Shatter pair")
	player = _socket_pair(fire, lightning, 3)
	check(_offer_ids(mgr._build_offer_choices(player, 1)) == ["evolve_arc_bolt", "overclock"], "magma offer: Fire 3 + Lightning 3 still offers Arc Bolt and the generic Overclock")
	player = _socket_pair(fire, frost, 3)
	check(_offer_ids(mgr._build_offer_choices(player, 1)) == ["overclock"], "magma offer: Fire 3 + Frost 3 still offers only the generic Overclock")
	var leaked := false
	for choice in mgr.generate_selection_pool(player, 99):
		leaked = leaked or choice.definition.is_compound_card()
	for entry in DebugActions.grantable_cards(mgr):
		leaked = leaked or (entry["definition"] as UpgradeDefinition).is_compound_card()
	check(not leaked, "magma pool: no compound card appears in level-up drafts or the debug grant list")

	# c. Apply Evolve + Magma.
	player = _socket_pair(fire, earth, 3)
	var ability := player.ability_container.get_ability_by_slot(1)
	var tags: Array[Tags.Type] = ability.tag_component.get_permanent_tags()
	var ledger := player.run_ledger_component
	player.apply_contextual_upgrade(offer[0])
	check(ability.evolution_gate_component.current_state == T2 and ledger.purchase_registry.has(PurchaseKey.make("compound_magma_evolve", 1)) and not ledger.purchase_registry.has("compound_magma_evolve"), "magma evolve: TIER_2_EVOLVED, the slot-specific key exists and the plain key does not")
	check(ledger.get_impact_bursts(1, tags).has(lava) and not ledger.get_impact_bursts(2, tags).has(lava) and not ledger.is_overclocked(1), "magma evolve: the lava burst resolves for slot 1 only and the slot is not overclocked")

	# d. Apply Overclock + Magma.
	player = _socket_pair(fire, earth, 3)
	ability = player.ability_container.get_ability_by_slot(1)
	tags = ability.tag_component.get_permanent_tags()
	ledger = player.run_ledger_component
	player.apply_contextual_upgrade(offer[1])
	check(ledger.is_overclocked(1) and ability.evolution_gate_component.current_state == T1 and mgr._find_next_offer_slot(player) == 0, "magma overclock: overclocked, still TIER_1_BASE, no further offer")
	check(ledger.get_impact_bursts(1, tags).has(lava) and not ledger.get_impact_bursts(2, tags).has(lava), "magma overclock: the lava burst resolves for slot 1 only")

	# e. A real hit spawns one lava zone at the hit position; Burn only, no direct damage.
	var stats := _make_stats({Stat.Type.AOE_RADIUS: 5.0})
	var burn := load("res://resources/status_effects/burn.tres") as StatusEffect
	var chill := load("res://resources/status_effects/chill.tres") as StatusEffect
	var both: Array[StatusEffect] = [burn, chill]
	var origin := Vector2(72000.0, 100000.0)
	var host := _zone_host()
	var bats := await _spawn_burst_bats(origin, [Vector2(0, 0), Vector2(20, 0), Vector2(100, 0)])
	var children_before := host.get_child_count()
	bats[0].hurtbox_component.take_hit(_ext_payload(stats, 10.0, lava, both))
	await tree.process_frame
	await tree.process_frame
	var zone: LingeringZone = null
	if host.get_child_count() > children_before:
		zone = host.get_child(host.get_child_count() - 1) as LingeringZone
	check(zone != null and host.get_child_count() == children_before + 1 and zone.global_position.is_equal_approx(origin) and LingeringZone.get_live_count(&"magma_lava") == 1, "magma zone: a hit spawns one lava zone at the hit position")
	check(zone != null and is_equal_approx(zone._radius, 30.0), "magma zone: the radius is AOE_RADIUS 5 * 6 = 30")
	await tree.create_timer(0.2).timeout
	var inside: StatusEffectInstance = bats[1].status_effect_component._active_effects.get("burn")
	check(inside != null and is_equal_approx(inside.dot_damage, 5.0) and is_equal_approx(inside.duration_bonus, 3.0) and is_equal_approx(inside.ramp_cap_bonus, 0.1), "magma zone: an enemy inside gets Burn with the exact cast snapshots")
	check(not bats[1].status_effect_component._active_effects.has("chill"), "magma zone: with Burn and Chill on the cast, the zone applies no Chill")
	check(bats[2].status_effect_component._active_effects.is_empty() and is_equal_approx(_lost(bats[2]), 0.0), "magma zone: an enemy outside is untouched")
	var zone_hits_clean: bool = _recorded[1].size() >= 1
	for seen in _recorded[1]:
		zone_hits_clean = zone_hits_clean and seen.is_burst and is_equal_approx(seen.final_damage, 0.0) and seen.status_effects_to_apply.size() == 1 and seen.status_effects_to_apply[0] == burn
	check(zone_hits_clean and is_equal_approx(_lost(bats[1]), 0.0), "magma zone: every zone hit is is_burst, deals 0 direct damage and carries only Burn")
	_free_bats(bats)
	if is_instance_valid(zone):
		zone.queue_free()
	await tree.process_frame
	LingeringZone.reset_registry()

	# f. One zone per cast (max_per_cast 1), through the cast's shared CastBudget.
	bats = await _spawn_burst_bats(origin + Vector2(0, 1000.0), [Vector2(0, 0), Vector2(5000, 0)])
	var capped := _ext_payload(stats, 10.0, lava, both)
	capped.cast_budget = CastBudget.new()
	capped.cast_id = 515151
	bats[0].hurtbox_component.take_hit(capped)
	bats[1].hurtbox_component.take_hit(capped)
	await tree.process_frame
	await tree.process_frame
	check(LingeringZone.get_live_count(&"magma_lava") == 1, "magma zone: a cast with two hits leaves one lava zone (max_per_cast 1)")
	_free_bats(bats)
	_free_live_zones(&"magma_lava")
	await tree.process_frame
	LingeringZone.reset_registry()

	# g. Merge and the live-zone cap for the new zone_id.
	var spawned: Array[LingeringZone] = []
	var first := await _spawn_zone(lava, _ext_payload(stats, 10.0, lava, both), Vector2(72000.0, 110000.0))
	var second := await _spawn_zone(lava, _ext_payload(stats, 10.0, lava, both), Vector2(72020.0, 110000.0))
	check(LingeringZone.get_live_count(&"magma_lava") == 1 and is_instance_valid(first) and not is_instance_valid(second), "magma merge: two lava zones 20 apart leave one")
	spawned.append(first)
	var far := await _spawn_zone(lava, _ext_payload(stats, 10.0, lava, both), Vector2(72100.0, 110000.0))
	spawned.append(far)
	check(LingeringZone.get_live_count(&"magma_lava") == 2, "magma merge: a zone 100 apart makes a second zone")
	for i in range(10):
		var extra := await _spawn_zone(lava, _ext_payload(stats, 10.0, lava, both), Vector2(72000.0 + 200.0 * (i + 1), 111000.0))
		if is_instance_valid(extra):
			spawned.append(extra)
	check(LingeringZone.get_live_count(&"magma_lava") == 8, "magma cap: twelve zones leave 8 registered")
	for node in spawned:
		if is_instance_valid(node):
			node.queue_free()
	await tree.process_frame
	await tree.process_frame
	LingeringZone.reset_registry()

	# h. Earth's REACH_BONUS reaches the zone radius (reported, nothing changed).
	var reach_stats := _make_stats({Stat.Type.AOE_RADIUS: 5.0, Stat.Type.REACH_BONUS: 1.0})
	var reach_zone := await _spawn_zone(lava, _ext_payload(reach_stats, 10.0, lava, both), Vector2(72000.0, 120000.0))
	check(reach_zone != null and is_equal_approx(reach_zone._radius, 60.0), "magma reach: REACH_BONUS 1.0 doubles the zone radius ((5 * 2) * 6 = 60)")
	if is_instance_valid(reach_zone):
		reach_zone.queue_free()
	await tree.process_frame
	LingeringZone.reset_registry()


func _free_live_zones(zone_id: StringName) -> void:
	for entry in LingeringZone._registry.get(zone_id, []).duplicate():
		if is_instance_valid(entry):
			(entry as Node).queue_free()


func _clear_test_effects() -> void:
	for node in TestBurstEffect.instances:
		if is_instance_valid(node):
			node.queue_free()
	TestBurstEffect.instances.clear()
	TestBurstEffect.received.clear()


func _list_tres(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	for entry in dir.get_directories():
		found.append_array(_list_tres(dir_path.path_join(entry)))
	for file in dir.get_files():
		if file.ends_with(".tres"):
			found.append(dir_path.path_join(file))
	return found


const TEST_LINGERING_ZONE := "res://tools/headless/test_lingering_zone.tscn"


func _zone_host() -> Node:
	return tree.current_scene if is_instance_valid(tree.current_scene) else tree.root


## An effect-only burst that spawns `scene` (a lingering zone) and nothing else.
func _zone_burst(id: StringName, scene: PackedScene) -> ImpactBurstDefinition:
	var definition := _ext_burst(id, 0.0, [Tags.Type.BURNING, Tags.Type.CHILLED], Tags.Type.NONE, false)
	definition.effect_scene = scene
	return definition


## A cast payload for a zone: the given statuses, Burn dot snapshot `dot`.
func _zone_payload(stats: StatsContainer, definition: ImpactBurstDefinition, statuses: Array[StatusEffect], dot: float = 5.0) -> CombatPayload:
	var payload := _ext_payload(stats, 10.0, definition, statuses)
	payload.dot_damage_snapshot = dot
	return payload


## Spawns the burst's zone at `origin` through the real burst path and returns it (null if none was added).
func _spawn_zone(definition: ImpactBurstDefinition, payload: CombatPayload, origin: Vector2) -> LingeringZone:
	var host := _zone_host()
	var before := host.get_child_count()
	ImpactBurst.run(definition, payload, origin, 0, tree.root.get_world_2d())
	var zone: LingeringZone = null
	if host.get_child_count() > before:
		zone = host.get_child(host.get_child_count() - 1) as LingeringZone
	await tree.process_frame
	await tree.process_frame
	return zone


const STORM_EVOLVE_CARD := "res://resources/compounds/storm_evolution_upgrade_def.tres"
const STORM_OVERCLOCK_CARD := "res://resources/compounds/storm_overclock_upgrade_def.tres"
const STORM_BURST := "res://resources/bursts/storm_strike.tres"


## A payload whose every hit crits (chance 1.0, multiplier 2.0), carrying `definitions`.
func _storm_crit_payload(stats: StatsContainer, damage: float, definitions: Array[ImpactBurstDefinition], effects: Array[StatusEffect] = []) -> CombatPayload:
	var payload := _burst_payload(stats, damage, definitions)
	payload.crit_chance_snapshot = 1.0
	payload.crit_multiplier_snapshot = 2.0
	payload.status_effects_to_apply = effects
	payload.dot_damage_snapshot = 5.0
	payload.status_duration_snapshot = 3.0
	payload.status_ramp_cap_snapshot = 0.1
	return payload


func _section_storm_strike() -> void:
	var mgr := fx.get_upgrade_manager()
	var fire := load(FIRE_CARD) as UpgradeDefinition
	var lightning := load(LIGHTNING_CARD) as UpgradeDefinition
	var wind := load(WIND_CARD) as UpgradeDefinition
	var evolve_card := load(STORM_EVOLVE_CARD) as UpgradeDefinition
	var overclock_card := load(STORM_OVERCLOCK_CARD) as UpgradeDefinition
	var strike := load(STORM_BURST) as ImpactBurstDefinition
	var stats := _make_stats({Stat.Type.AOE_RADIUS: 40.0})
	var burn := load("res://resources/status_effects/burn.tres") as StatusEffect
	var chill := load("res://resources/status_effects/chill.tres") as StatusEffect
	var statuses: Array[StatusEffect] = [burn, chill]
	var strike_only: Array[ImpactBurstDefinition] = [strike]
	var origin := Vector2(90000.0, 90000.0)

	# Data.
	check(strike.burst_id == &"storm_strike" and strike.trigger == ImpactBurstDefinition.Trigger.ON_CRIT and strike.hits_primary and strike.shape == null and is_equal_approx(strike.damage_fraction, 0.5) and strike.unlock_level == 1 and strike.max_per_cast == 4 and strike.carried_status_tags.is_empty(), "storm data: the strike is ON_CRIT, hits_primary, no shape, 0.5, level 1, cap 4, carries no status")
	check(evolve_card.is_compound_card() and overclock_card.is_compound_card() and evolve_card.payload_type == UpgradeDefinition.PayloadType.ABILITY_UNLOCK and overclock_card.payload_type == UpgradeDefinition.PayloadType.ABILITY_OVERCLOCK, "storm data: both Storm cards are compound cards (ABILITY_UNLOCK and ABILITY_OVERCLOCK)")
	check(evolve_card.compound_pair.has(Tags.Type.LIGHTNING) and evolve_card.compound_pair.has(Tags.Type.WIND) and evolve_card.compound_pair.size() == 2 and overclock_card.compound_pair == evolve_card.compound_pair and evolve_card.impact_burst_payload == strike and overclock_card.impact_burst_payload == strike, "storm data: both cards name Lightning + Wind and carry the strike")
	check(evolve_card.evolves_from == null and evolve_card.ability_data_payload == null, "storm data: no evolves_from, no ability data")
	check(ImpactBurstDefinition.new().hits_primary == false, "storm data: hits_primary defaults to false")

	# a. A crit queues exactly one extra hit on the primary and none on a neighbor in range.
	var bats := await _spawn_burst_bats(origin, [Vector2(0, 0), Vector2(30, 0)])
	bats[0].hurtbox_component.take_hit(_storm_crit_payload(stats, 10.0, strike_only))
	await tree.process_frame
	await tree.process_frame
	check(_recorded[0].size() == 2 and _recorded[1].size() == 0, "storm strike: a crit gives the primary exactly one extra hit and the neighbor none (got %d, %d)" % [_recorded[0].size(), _recorded[1].size()])
	# c. Strike damage = the crit hit's final damage * damage_fraction.
	check(is_equal_approx(_lost(bats[0]), 30.0) and is_equal_approx((_recorded[0][1] as CombatPayload).final_damage, 10.0) and is_equal_approx((_recorded[0][0] as CombatPayload).final_damage, 20.0), "storm strike: the crit deals 20 and the strike 10 (crit multiplier included in the fraction)")
	var strike_payload := _recorded[0][1] as CombatPayload
	check(strike_payload.is_burst and not strike_payload.is_critical_hit and strike_payload.impact_bursts.is_empty(), "storm strike: the strike payload is a burst, not a crit, with no bursts")
	_free_bats(bats)

	# b. A non-crit hit queues none.
	bats = await _spawn_burst_bats(origin + Vector2(0, 1000.0), [Vector2(0, 0)])
	var plain := _storm_crit_payload(stats, 10.0, strike_only)
	plain.crit_chance_snapshot = 0.0
	bats[0].hurtbox_component.take_hit(plain)
	await tree.process_frame
	await tree.process_frame
	check(_recorded[0].size() == 1 and is_equal_approx(_lost(bats[0]), 10.0), "storm strike: a non-crit hit queues no strike")
	_free_bats(bats)

	# d. The strike never crits and never starts another burst: an ON_HIT area burst on the same payload fires once.
	var area := _make_burst(&"test_storm_area", ImpactBurstDefinition.Trigger.ON_HIT, 0.5)
	var both_bursts: Array[ImpactBurstDefinition] = [strike, area]
	bats = await _spawn_burst_bats(origin + Vector2(0, 2000.0), [Vector2(0, 0), Vector2(30, 0)])
	bats[0].hurtbox_component.take_hit(_storm_crit_payload(stats, 10.0, both_bursts))
	await tree.process_frame
	await tree.process_frame
	check(_recorded[1].size() == 1 and is_equal_approx(_lost(bats[1]), 10.0), "storm strike: the area burst fires once, from the crit hit only (the strike hit starts no burst)")
	check(_recorded[0].size() == 2 and not (_recorded[0][1] as CombatPayload).is_critical_hit, "storm strike: the strike hit is not a crit even with chance 1.0")
	_free_bats(bats)

	# e. max_per_cast 4 caps a fan of crits on one cast, per cast.
	var offsets: Array[Vector2] = []
	for i in range(6):
		offsets.append(Vector2(float(i) * 5000.0, 0))
	bats = await _spawn_burst_bats(origin + Vector2(0, 3000.0), offsets)
	var fan := _storm_crit_payload(stats, 10.0, strike_only)
	fan.cast_budget = CastBudget.new()
	fan.cast_id = 515151
	for bat in bats:
		bat.hurtbox_component.take_hit(fan)
	await tree.process_frame
	await tree.process_frame
	var struck := 0
	for i in range(6):
		if _recorded[i].size() == 2:
			struck += 1
	check(struck == 4, "storm strike: six crits on one cast give four strikes (got %d)" % struck)
	var second_cast := _storm_crit_payload(stats, 10.0, strike_only)
	second_cast.cast_budget = CastBudget.new()
	second_cast.cast_id = 515152
	_recorded[5].clear()
	bats[5].hurtbox_component.take_hit(second_cast)
	await tree.process_frame
	await tree.process_frame
	check(_recorded[5].size() == 2, "storm strike: the cap is per cast (a new cast strikes again)")
	_free_bats(bats)

	# f. The strike applies no status; the crit hit's own statuses still apply.
	bats = await _spawn_burst_bats(origin + Vector2(0, 4000.0), [Vector2(0, 0)])
	bats[0].hurtbox_component.take_hit(_storm_crit_payload(stats, 10.0, strike_only, statuses))
	await tree.process_frame
	await tree.process_frame
	check((_recorded[0][1] as CombatPayload).status_effects_to_apply.is_empty(), "storm strike: the strike payload carries no status")
	check((_recorded[0][0] as CombatPayload).status_effects_to_apply.size() == 2, "storm strike: the crit hit itself still carries the cast statuses")
	_free_bats(bats)

	# g. A primary freed or dying before the deferred run: nothing happens, no engine error.
	bats = await _spawn_burst_bats(origin + Vector2(0, 5000.0), [Vector2(0, 0), Vector2(5000, 0)])
	bats[0].hurtbox_component.take_hit(_storm_crit_payload(stats, 10.0, strike_only))
	bats[0].free()
	bats[1].hurtbox_component.take_hit(_storm_crit_payload(stats, 10.0, strike_only))
	bats[1].queue_free()
	await tree.process_frame
	await tree.process_frame
	check(_recorded[0].size() == 1 and _recorded[1].size() == 1, "storm strike: a freed or queued-for-deletion primary receives no strike")

	# h. hits_primary false still excludes the primary.
	var area_crit := _make_burst(&"test_storm_area_crit", ImpactBurstDefinition.Trigger.ON_CRIT, 0.5)
	var area_list: Array[ImpactBurstDefinition] = [area_crit]
	bats = await _spawn_burst_bats(origin + Vector2(0, 6000.0), [Vector2(0, 0), Vector2(30, 0)])
	bats[0].hurtbox_component.take_hit(_storm_crit_payload(stats, 10.0, area_list))
	await tree.process_frame
	await tree.process_frame
	check(_recorded[0].size() == 1 and _recorded[1].size() == 1, "storm strike: an area burst without hits_primary still skips the primary")
	_free_bats(bats)

	# i. Offers and purchases.
	var player := _socket_pair(lightning, wind, 3)
	check(mgr._find_next_offer_slot(player) == 1, "storm offer: Lightning 3 + Wind 3 makes slot 1 offer-eligible")
	var offer := mgr._build_offer_choices(player, 1)
	check(_offer_ids(offer) == ["compound_storm_evolve", "compound_storm_overclock"], "storm offer: exactly Evolve + Storm and Overclock + Storm, no generic Overclock (got %s)" % str(_offer_ids(offer)))
	var ability := player.ability_container.get_ability_by_slot(1)
	var tags: Array[Tags.Type] = ability.tag_component.get_permanent_tags()
	var ledger := player.run_ledger_component
	player.apply_contextual_upgrade(offer[0])
	check(ledger.purchase_registry.has(PurchaseKey.make("compound_storm_evolve", 1)) and not ledger.purchase_registry.has("compound_storm_evolve"), "storm evolve: logged as a slot-specific purchase")
	check(ledger.get_impact_bursts(1, tags).has(strike) and not ledger.get_impact_bursts(2, tags).has(strike) and not ledger.is_overclocked(1), "storm evolve: the strike resolves for slot 1 only")
	player = _socket_pair(lightning, wind, 3)
	ability = player.ability_container.get_ability_by_slot(1)
	tags = ability.tag_component.get_permanent_tags()
	ledger = player.run_ledger_component
	player.apply_contextual_upgrade(offer[1])
	check(ledger.purchase_registry.has(PurchaseKey.make("compound_storm_overclock", 1)) and ledger.is_overclocked(1) and ledger.get_impact_bursts(1, tags).has(strike) and not ledger.get_impact_bursts(2, tags).has(strike), "storm overclock: slot-specific, overclocked, strike resolves for slot 1 only")
	player = _socket_pair(fire, lightning, 3)
	check(_offer_ids(mgr._build_offer_choices(player, 1)) == ["evolve_arc_bolt", "overclock"], "storm offer: Fire 3 + Lightning 3 is unaffected")
	var leaked := false
	for choice in mgr.generate_selection_pool(player, 99):
		leaked = leaked or choice.definition.is_compound_card()
	for entry in DebugActions.grantable_cards(mgr):
		leaked = leaked or (entry["definition"] as UpgradeDefinition).is_compound_card()
	check(not leaked, "storm pool: no compound card appears in level-up drafts or the debug grant list")


const SHOCK_EFFECT := "res://resources/status_effects/shock.tres"


## How many of `trials` hits with crit chance `chance` crit against `bat`, rolled through the real resolve_hit_crit.
func _crit_count(bat: Enemy, chance: float, trials: int = 200) -> int:
	var payload := _storm_crit_payload(_make_stats({}), 10.0, [])
	payload.crit_chance_snapshot = chance
	var crits := 0
	for i in range(trials):
		if CombatCalculations.resolve_hit_crit(payload, bat.stats_container).is_critical_hit:
			crits += 1
	return crits


## The cast statuses of a payload, as effect ids.
func _status_ids(payload: CombatPayload) -> Array[String]:
	var ids: Array[String] = []
	for status in payload.status_effects_to_apply:
		ids.append(status.effect_id)
	return ids


func _section_shock() -> void:
	var shock := load(SHOCK_EFFECT) as StatusEffect
	var storm_evolve := load(STORM_EVOLVE_CARD) as UpgradeDefinition
	var storm_overclock := load(STORM_OVERCLOCK_CARD) as UpgradeDefinition
	var stats := _make_stats({Stat.Type.AOE_RADIUS: 40.0})
	var burn := load("res://resources/status_effects/burn.tres") as StatusEffect
	var origin := Vector2(100000.0, 100000.0)
	seed(12345)

	# Data and enum values.
	check(int(Stat.Type.INCOMING_CRIT_BONUS) == 25 and int(Tags.Type.SHOCKED) == 21, "shock data: INCOMING_CRIT_BONUS is 25 and SHOCKED is 21 (appended)")
	var modifier := shock.stat_modifiers[0]
	check(shock.effect_id == "shock" and is_equal_approx(shock.base_duration, 3.0) and is_equal_approx(shock.tick_interval, 0.0) and shock.magnitude_scales and is_equal_approx(shock.max_magnitude_bonus, 0.5) and shock.granted_tags == [Tags.Type.SHOCKED], "shock data: non-ticking, 3 s, scales with magnitude, grants SHOCKED")
	check(shock.stat_modifiers.size() == 1 and modifier.type == StatModifier.Type.FLAT and is_equal_approx(modifier.value, 0.15) and modifier.target_stat_type == Stat.Type.INCOMING_CRIT_BONUS, "shock data: one FLAT 0.15 modifier on INCOMING_CRIT_BONUS")
	check(storm_evolve.status_effect_payload == shock and storm_overclock.status_effect_payload == shock, "shock data: both Storm cards carry Shock")
	check((load(STORM_BURST) as ImpactBurstDefinition).carried_status_tags.is_empty(), "shock data: the strike still carries no status tag")

	# Every shipped enemy profile carries the stat, or Shock would do nothing.
	var enemy_count := 0
	var missing: Array[String] = []
	for path in _list_tres("res://resources"):
		var resource := load(path)
		if resource is EnemyData:
			enemy_count += 1
			var profile := (resource as EnemyData).stats_profile
			if profile == null or not profile.base_stats.has(Stat.Type.INCOMING_CRIT_BONUS):
				missing.append(path)
	check(enemy_count >= 1 and missing.is_empty(), "shock profiles: every shipped enemy profile carries INCOMING_CRIT_BONUS (%d enemies, missing %s)" % [enemy_count, str(missing)])

	var bats := await _spawn_burst_bats(origin, [Vector2(0, 0)])
	var bat := bats[0]
	var comp := bat.status_effect_component
	check(is_equal_approx(bat.stats_container.get_final_stat_value(Stat.Type.INCOMING_CRIT_BONUS), 0.0) and not bat.tag_component.has_tag(Tags.Type.SHOCKED), "shock: a fresh enemy has no bonus and no SHOCKED tag")

	# The enemy's own stats container receives the status modifiers and the tag (Entity does this for every entity).
	var plain_crits := _crit_count(bat, 0.85)
	comp.apply_effect(shock)
	check(is_equal_approx(bat.stats_container.get_final_stat_value(Stat.Type.INCOMING_CRIT_BONUS), 0.15) and bat.tag_component.has_tag(Tags.Type.SHOCKED), "shock: applying Shock gives the enemy INCOMING_CRIT_BONUS 0.15 and the SHOCKED tag")
	var shocked_crits := _crit_count(bat, 0.85)
	check(plain_crits < 200 and plain_crits > 0 and shocked_crits == 200, "shock: chance 0.85 plus 0.15 always crits; without Shock it does not (%d, %d of 200)" % [plain_crits, shocked_crits])

	# The bonus belongs to the target: a payload from another slot also benefits, and the sum clamps to 1.
	var other := _storm_crit_payload(_make_stats({}, 2), 10.0, [])
	other.crit_chance_snapshot = 0.85
	check(CombatCalculations.resolve_hit_crit(other, bat.stats_container).is_critical_hit, "shock: a payload from another slot's ability also benefits")
	check(_crit_count(bat, 0.99) == 200 and _crit_count(bat, 5.0) == 200, "shock: a chance above the cap clamps and still crits")
	other.crit_chance_snapshot = 0.0
	check(not CombatCalculations.resolve_hit_crit(other, null).is_critical_hit, "shock: a null target stats container adds nothing")

	# Re-applying refreshes the timer, the latest magnitude wins.
	comp._process(2.0)
	var instance: StatusEffectInstance = comp._active_effects.get("shock")
	check(instance != null and is_equal_approx(instance.time_remaining, 1.0), "shock: 2 s in, 1 s remains")
	comp.apply_effect(shock, 0.0, 0.0, 0.0, 0.2)
	check(is_equal_approx(instance.time_remaining, 3.0) and is_equal_approx(bat.stats_container.get_final_stat_value(Stat.Type.INCOMING_CRIT_BONUS), 0.18), "shock: re-applying refreshes the timer, and a magnitude bonus of 0.2 gives 0.18")
	comp.apply_effect(shock, 0.0, 0.0, 0.0, 0.9)
	check(is_equal_approx(bat.stats_container.get_final_stat_value(Stat.Type.INCOMING_CRIT_BONUS), 0.225), "shock: a magnitude bonus above the template cap 0.5 clamps (0.15 * 1.5)")

	# Expiry removes the bonus and the tag.
	comp._process(3.1)
	check(not comp._active_effects.has("shock") and is_equal_approx(bat.stats_container.get_final_stat_value(Stat.Type.INCOMING_CRIT_BONUS), 0.0) and not bat.tag_component.has_tag(Tags.Type.SHOCKED), "shock: on expiry the bonus and SHOCKED are gone")
	_free_bats(bats)

	# A hit does not benefit from the Shock it applies, and a burst payload never crits on a Shocked enemy.
	var shock_list: Array[StatusEffect] = [shock]
	bats = await _spawn_burst_bats(origin + Vector2(0, 1000.0), [Vector2(0, 0)])
	var first := _storm_crit_payload(stats, 10.0, [], shock_list)
	first.crit_chance_snapshot = 0.0
	bats[0].hurtbox_component.take_hit(first)
	check(not (_recorded[0][0] as CombatPayload).is_critical_hit and bats[0].tag_component.has_tag(Tags.Type.SHOCKED), "shock: the hit that applies Shock does not benefit from it (the crit rolls before statuses apply)")
	var burst_payload := _storm_crit_payload(stats, 10.0, [])
	burst_payload.is_burst = true
	bats[0].hurtbox_component.take_hit(burst_payload)
	check(not (_recorded[0][1] as CombatPayload).is_critical_hit and is_equal_approx(_lost(bats[0]), 20.0), "shock: a burst payload never crits, even on a Shocked enemy")
	_free_bats(bats)

	# A Storm slot's regular hits carry Shock (no Fire needed); the strike carries nothing.
	var lightning := load(LIGHTNING_CARD) as UpgradeDefinition
	var wind := load(WIND_CARD) as UpgradeDefinition
	var player := _socket_pair(lightning, wind, 3)
	var ability := player.ability_container.get_ability_by_slot(1)
	player.apply_contextual_upgrade(fx.get_upgrade_manager()._build_offer_choices(player, 1)[0])
	var cast := CombatCalculations.generate_hit_payload(null, ability.stats_container, null)
	check(_status_ids(cast) == ["shock"], "shock: a Lightning + Wind slot with a Storm card casts exactly [shock], no Fire needed (got %s)" % str(_status_ids(cast)))
	check(cast.impact_bursts.size() == 1 and ImpactBurst.carried_statuses(cast.impact_bursts[0], cast.status_effects_to_apply).is_empty(), "shock: the strike carries none of the cast statuses")
	var other_slot := CombatCalculations.generate_hit_payload(null, _make_stats({Stat.Type.BASE_DAMAGE: 1.0, Stat.Type.DOT_DAMAGE: 1.0}, 2, player.run_ledger_component), null)
	check(other_slot.status_effects_to_apply.is_empty(), "shock: another slot of the same player casts no Shock")

	# Magma is unchanged: a Fire + Earth slot with the Magma card still casts exactly Burn.
	var fire := load(FIRE_CARD) as UpgradeDefinition
	var earth := load(EARTH_CARD) as UpgradeDefinition
	var magma_player := _socket_pair(fire, earth, 3)
	magma_player.run_ledger_component.log_slot_specific_purchase(load(MAGMA_EVOLVE_CARD) as UpgradeDefinition, 1)
	var magma_cast := CombatCalculations.generate_hit_payload(null, magma_player.ability_container.get_ability_by_slot(1).stats_container, null)
	check(_status_ids(magma_cast) == ["burn"], "shock: a Magma slot still casts exactly [burn] (got %s)" % str(_status_ids(magma_cast)))
	check(burn.tick_interval > 0.0 and burn.stat_modifiers.is_empty() and not burn.magnitude_scales, "shock: Burn's template is untouched")


func _section_lingering_zone() -> void:
	LingeringZone.reset_registry()
	var zone_scene := load(TEST_LINGERING_ZONE) as PackedScene
	var stats := _make_stats({Stat.Type.AOE_RADIUS: 10.0})
	var burn := load("res://resources/status_effects/burn.tres") as StatusEffect
	var burn_list: Array[StatusEffect] = [burn]
	var no_statuses: Array[StatusEffect] = []
	var zone_def := _zone_burst(&"test_zone_burst", zone_scene)

	# a. Safety fix: an effect gets a copy that is already a burst payload, with no bursts and no crit.
	var effect_def := _ext_burst(&"test_zone_effect", 0.5, [Tags.Type.BURNING], Tags.Type.NONE, false)
	effect_def.effect_scene = load(TEST_BURST_EFFECT) as PackedScene
	_clear_test_effects()
	var crit_source := _ext_payload(stats, 10.0, effect_def, burn_list)
	crit_source.is_critical_hit = true
	ImpactBurst.run(effect_def, crit_source, Vector2(70000.0, 90000.0), 0, tree.root.get_world_2d())
	var received: CombatPayload = TestBurstEffect.received[0] if TestBurstEffect.received.size() == 1 else null
	check(received != null and received.is_burst and received.impact_bursts.is_empty() and not received.is_critical_hit, "zone: the payload an effect receives is is_burst, has no bursts and no crit")
	check(received != null and received.status_effects_to_apply.size() == 1 and is_equal_approx(received.dot_damage_snapshot, 5.0) and is_equal_approx(received.status_duration_snapshot, 3.0) and is_equal_approx(received.status_ramp_cap_snapshot, 0.1), "zone: the effect payload keeps the cast statuses and snapshots")
	check(crit_source.impact_bursts.size() == 1 and not crit_source.is_burst and crit_source.is_critical_hit and is_equal_approx(crit_source.final_damage, 10.0), "zone: the source payload is unchanged by the safety fix")
	_clear_test_effects()

	# b. End to end: a hit on bat A fires an effect-only burst that spawns one zone.
	var origin := Vector2(70000.0, 91000.0)
	var bats := await _spawn_burst_bats(origin, [Vector2(0, 0), Vector2(30, 0), Vector2(70, 0)])
	var refreshed_count := [0]
	bats[1].status_effect_component.refreshed.connect(func(_instance: StatusEffectInstance) -> void: refreshed_count[0] += 1)
	var host := _zone_host()
	var children_before := host.get_child_count()
	bats[0].hurtbox_component.take_hit(_zone_payload(stats, zone_def, burn_list))
	await tree.process_frame
	await tree.process_frame
	var zone: LingeringZone = null
	if host.get_child_count() > children_before:
		zone = host.get_child(host.get_child_count() - 1) as LingeringZone
	check(zone != null and host.get_child_count() == children_before + 1 and zone.global_position.is_equal_approx(origin), "zone: a hit on bat A spawns one zone at A's position")
	check(LingeringZone.get_live_count(&"test_zone") == 1, "zone: the zone registered itself under its zone_id")
	await tree.create_timer(0.15).timeout
	var inside_burn: StatusEffectInstance = bats[1].status_effect_component._active_effects.get("burn")
	check(inside_burn != null and is_equal_approx(inside_burn.dot_damage, 5.0) and is_equal_approx(inside_burn.duration_bonus, 3.0) and is_equal_approx(inside_burn.ramp_cap_bonus, 0.1), "zone: the bat inside gets the cast Burn with the exact snapshots")
	check(not bats[2].status_effect_component._active_effects.has("burn"), "zone: the bat outside gets no Burn")
	await tree.create_timer(1.0).timeout
	check(refreshed_count[0] >= 2, "zone: the zone applies again on later intervals (refreshed fired %d times)" % refreshed_count[0])
	check(inside_burn != null and bats[1].status_effect_component.get_active_instances().size() == 1, "zone: repeated zone applications keep one Burn instance")
	check(not is_instance_valid(zone), "zone: the zone frees itself after its lifetime")
	var zone_hits_clean: bool = _recorded[1].size() >= 2
	for seen in _recorded[1]:
		zone_hits_clean = zone_hits_clean and seen.is_burst and is_equal_approx(seen.final_damage, 0.0)
	check(zone_hits_clean, "zone: every hit the zone delivered is is_burst with final_damage 0 (the Burn it applies still ticks on its own)")
	_free_bats(bats)

	# c. The player's hurtbox inside the radius gets no status.
	var player := fx.get_player()
	var saved_position := player.global_position
	var saved_layer := player.hurtbox_component.collision_layer
	var player_origin := Vector2(70000.0, 92000.0)
	player.global_position = player_origin
	player.hurtbox_component.collision_layer = saved_layer | 4
	await tree.physics_frame
	await tree.physics_frame
	var player_zone := await _spawn_zone(zone_def, _zone_payload(stats, zone_def, burn_list), player_origin)
	await tree.create_timer(0.3).timeout
	check(player_zone != null and player.status_effect_component._active_effects.is_empty(), "zone: the player's hurtbox inside the radius gets no status")
	player.hurtbox_component.collision_layer = saved_layer
	player.global_position = saved_position
	if is_instance_valid(player_zone):
		player_zone.queue_free()
	await tree.process_frame
	LingeringZone.reset_registry()

	# d. A payload with no statuses: the zone does nothing and raises no error.
	bats = await _spawn_burst_bats(Vector2(70000.0, 93000.0), [Vector2(0, 0), Vector2(30, 0)])
	var quiet_zone := await _spawn_zone(zone_def, _zone_payload(stats, zone_def, no_statuses), Vector2(70000.0, 93000.0))
	await tree.create_timer(0.3).timeout
	check(quiet_zone != null and is_instance_valid(quiet_zone) and bats[0].status_effect_component._active_effects.is_empty() and bats[1].status_effect_component._active_effects.is_empty() and _recorded[0].is_empty() and _recorded[1].is_empty(), "zone: a payload with no statuses hits nobody")
	_free_bats(bats)
	await tree.create_timer(0.5).timeout
	LingeringZone.reset_registry()

	# e. Radius: 35 from the centre is inside (circle 40 + hurtbox 10), 65 is outside.
	var radius_origin := Vector2(70000.0, 94000.0)
	bats = await _spawn_burst_bats(radius_origin, [Vector2(35, 0), Vector2(65, 0)])
	var radius_zone := await _spawn_zone(zone_def, _zone_payload(stats, zone_def, burn_list), radius_origin)
	await tree.create_timer(0.15).timeout
	check(radius_zone != null and bats[0].status_effect_component._active_effects.has("burn"), "zone radius: a bat at radius - 5 is affected")
	check(not bats[1].status_effect_component._active_effects.has("burn"), "zone radius: a bat at radius + 25 is not affected")
	_free_bats(bats)
	await tree.create_timer(0.6).timeout
	LingeringZone.reset_registry()

	# f. Merge: the same id 20 apart refreshes the live zone and adopts the newer payload.
	var merge_origin := Vector2(70000.0, 95000.0)
	bats = await _spawn_burst_bats(merge_origin, [Vector2(10, 0)])
	var first := await _spawn_zone(zone_def, _zone_payload(stats, zone_def, burn_list, 5.0), merge_origin)
	await tree.create_timer(0.3).timeout
	var older_remaining := first._remaining if is_instance_valid(first) else 0.0
	var second := await _spawn_zone(zone_def, _zone_payload(stats, zone_def, burn_list, 7.0), merge_origin + Vector2(20, 0))
	check(LingeringZone.get_live_count(&"test_zone") == 1 and is_instance_valid(first) and not is_instance_valid(second), "zone merge: two zones 20 apart with the same id leave one live zone")
	check(is_instance_valid(first) and older_remaining < 0.4 and first._remaining > 0.55, "zone merge: the surviving zone's lifetime was reset")
	check(is_instance_valid(first) and is_equal_approx(first._payload.dot_damage_snapshot, 7.0), "zone merge: the surviving zone holds the newer payload")
	await tree.create_timer(0.3).timeout
	var merged_burn: StatusEffectInstance = bats[0].status_effect_component._active_effects.get("burn")
	check(merged_burn != null and is_equal_approx(merged_burn.dot_damage, 7.0), "zone merge: the zone applies the newer payload's Burn (dot 7.0)")
	var far := await _spawn_zone(zone_def, _zone_payload(stats, zone_def, burn_list), merge_origin + Vector2(100, 0))
	check(LingeringZone.get_live_count(&"test_zone") == 2 and is_instance_valid(far), "zone merge: a zone 100 apart makes a second zone")
	var other_inst := zone_scene.instantiate() as LingeringZone
	other_inst.zone_id = &"test_zone_other"
	var other_scene := PackedScene.new()
	other_scene.pack(other_inst)
	other_inst.free()
	var other_def := _zone_burst(&"test_zone_other_burst", other_scene)
	var other := await _spawn_zone(other_def, _zone_payload(stats, other_def, burn_list), merge_origin + Vector2(10, 0))
	check(is_instance_valid(other) and LingeringZone.get_live_count(&"test_zone_other") == 1 and LingeringZone.get_live_count(&"test_zone") == 2, "zone merge: a different zone_id 20 apart never merges")
	_free_bats(bats)
	await tree.create_timer(0.8).timeout
	LingeringZone.reset_registry()

	# g. Cap: five far-apart zones with max_live_zones 3 leave the three newest.
	var made: Array[LingeringZone] = []
	for i in range(5):
		made.append(await _spawn_zone(zone_def, _zone_payload(stats, zone_def, burn_list), Vector2(70000.0 + 1000.0 * i, 96000.0)))
	check(LingeringZone.get_live_count(&"test_zone") == 3, "zone cap: five zones leave 3 registered")
	check(not is_instance_valid(made[0]) and not is_instance_valid(made[1]) and is_instance_valid(made[2]) and is_instance_valid(made[3]) and is_instance_valid(made[4]), "zone cap: the two oldest zones are gone, the three newest remain")

	# h. Registry: once every zone has expired nothing is left, a discarded merge instance included.
	await tree.create_timer(1.0).timeout
	check(LingeringZone.get_live_count(&"test_zone") == 0 and LingeringZone.get_live_count(&"test_zone_other") == 0 and LingeringZone._registry.is_empty(), "zone registry: empty after every zone has been freed")

	# i. Guards: this task ships no scene or resource that uses the zone.
	var referencing := 0
	for dir_path in ["res://scenes", "res://resources", "res://components", "res://ui"]:
		for path in _list_scene_files(dir_path):
			if FileAccess.get_file_as_string(path).contains("lingering_zone.gd"):
				referencing += 1
	check(referencing == 2 and FileAccess.get_file_as_string("res://scenes/effects/lava_zone.tscn").contains("lingering_zone.gd") and FileAccess.get_file_as_string("res://scenes/effects/blizzard_vortex.tscn").contains("lingering_zone.gd"), "zone guards: the only shipped scenes or resources that reference lingering_zone.gd are scenes/effects/lava_zone.tscn and blizzard_vortex.tscn (found %d)" % referencing)
	LingeringZone.reset_registry()


func _list_scene_files(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	for entry in dir.get_directories():
		found.append_array(_list_scene_files(dir_path.path_join(entry)))
	for file in dir.get_files():
		if file.ends_with(".tscn") or file.ends_with(".tres"):
			found.append(dir_path.path_join(file))
	return found


const GEOMETRY_DRIVER_DIR := "res://components/ability/drivers/geometry"


func _list_tscn_files(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	for path in _list_scene_files(dir_path):
		if path.ends_with(".tscn"):
			found.append(path)
	return found


func _stat_ids(stats: Array[Stat.Type]) -> Array[int]:
	var ids: Array[int] = []
	for stat in stats:
		ids.append(int(stat))
	ids.sort()
	return ids


func _section_geometry_contract() -> void:
	# Task W: every geometry scene declares family, reach stats and speed stats.
	# Expected table, mirrored in the GDD section 1: scene name -> [family, reach stats, speed stats].
	var expected: Dictionary = {
		"targeted_projectile_geometry": [&"moving_hitbox", [Stat.Type.AOE_RADIUS], [Stat.Type.PROJECTILE_MOVEMENT_SPEED]],
		"straight_projectile_geometry": [&"moving_hitbox", [Stat.Type.AOE_RADIUS], [Stat.Type.PROJECTILE_MOVEMENT_SPEED]],
		"mouse_aim_projectile_geometry": [&"moving_hitbox", [Stat.Type.AOE_RADIUS], [Stat.Type.PROJECTILE_MOVEMENT_SPEED]],
		"radial_pulse_geometry": [&"area_instant", [Stat.Type.AOE_RADIUS], []],
		"converging_vortex_geometry": [&"area_instant", [Stat.Type.AOE_RADIUS], []],
		"linear_sweep_geometry": [&"area_instant", [Stat.Type.AOE_RADIUS], []],
		"fissure_geometry": [&"area_stepped", [Stat.Type.AOE_RADIUS], []],
		"chain_link_geometry": [&"chain", [Stat.Type.CHAIN_RADIUS], []],
		"orbiting_ring_geometry": [&"timed", [Stat.Type.ORBIT_RADIUS, Stat.Type.AOE_RADIUS], [Stat.Type.ORBIT_ROTATION_SPEED]],
	}
	var found_names: Array[String] = []
	var drivers: Dictionary = {}
	for path in _list_tscn_files(GEOMETRY_DRIVER_DIR):
		var scene_name := path.get_file().get_basename()
		found_names.append(scene_name)
		var driver := (load(path) as PackedScene).instantiate() as GeometryDriver
		if driver == null:
			check(false, "geometry contract: %s has a GeometryDriver root" % scene_name)
			continue
		fx.track(driver)
		drivers[scene_name] = driver
		var family := driver.get_family()
		check(family != &"" and GeometryDriver.FAMILIES.has(family), "geometry contract: %s declares a family in FAMILIES (got '%s')" % [scene_name, family])
		check(driver.get_reach_stats() is Array[Stat.Type] and driver.get_speed_stats() is Array[Stat.Type], "geometry contract: %s returns typed stat arrays" % scene_name)

	# b. The table, compared exactly.
	for scene_name in expected:
		if not drivers.has(scene_name):
			continue
		var driver: GeometryDriver = drivers[scene_name]
		var row: Array = expected[scene_name]
		check(driver.get_family() == row[0], "geometry contract: %s family is %s" % [scene_name, row[0]])
		var want_reach: Array[Stat.Type] = []
		want_reach.assign(row[1])
		var want_speed: Array[Stat.Type] = []
		want_speed.assign(row[2])
		check(_stat_ids(driver.get_reach_stats()) == _stat_ids(want_reach), "geometry contract: %s reach stats match the table" % scene_name)
		check(_stat_ids(driver.get_speed_stats()) == _stat_ids(want_speed), "geometry contract: %s speed stats match the table" % scene_name)

	# c. Every call returns a new array.
	var fresh_ok := true
	for scene_name in drivers:
		var driver: GeometryDriver = drivers[scene_name]
		var reach_a := driver.get_reach_stats()
		reach_a.append(Stat.Type.QUERY_RADIUS)
		var speed_a := driver.get_speed_stats()
		speed_a.append(Stat.Type.QUERY_RADIUS)
		fresh_ok = fresh_ok and not driver.get_reach_stats().has(Stat.Type.QUERY_RADIUS) and not driver.get_speed_stats().has(Stat.Type.QUERY_RADIUS)
	check(fresh_ok, "geometry contract: each call returns a new array (mutating one does not change the next)")

	# d. The table is complete in both directions.
	found_names.sort()
	var table_names: Array = expected.keys()
	table_names.sort()
	check(found_names == table_names, "geometry contract: scene names found %s equal the table %s" % [found_names, table_names])

	# e. Shipped abilities carry a profile key for every stat their geometry declares.
	for data_path in ["res://resources/abilities/arcane_bolt/arcane_bolt_data.tres", "res://resources/abilities/arc_bolt/arc_bolt_data.tres"]:
		var data := load(data_path) as AbilityData
		var geometry := data.geometry_driver_scene.instantiate() as GeometryDriver
		fx.track(geometry)
		var ability_name: String = data_path.get_file().get_basename()
		var declared: Array[Stat.Type] = []
		declared.append_array(geometry.get_reach_stats())
		declared.append_array(geometry.get_speed_stats())
		for stat in declared:
			check(data.stats_profile.base_stats.has(stat), "geometry contract: %s profile has %s" % [ability_name, Stat.Type.keys()[stat]])
		# Task AR: every ability profile carries STATUS_MAGNITUDE_BONUS at 0.0, or magnitude-scaling statuses ignore the ability.
		check(data.stats_profile.base_stats.has(Stat.Type.STATUS_MAGNITUDE_BONUS) and is_zero_approx(data.stats_profile.base_stats[Stat.Type.STATUS_MAGNITUDE_BONUS]), "geometry contract: %s profile has STATUS_MAGNITUDE_BONUS at 0.0" % ability_name)
		# Task AZ: every ability profile carries CRIT_COOLDOWN_REFUND and CRIT_REFUND_CAP at 0.0, or Superconduct does nothing for the ability.
		for refund_stat in [Stat.Type.CRIT_COOLDOWN_REFUND, Stat.Type.CRIT_REFUND_CAP]:
			check(data.stats_profile.base_stats.has(refund_stat) and is_zero_approx(data.stats_profile.base_stats[refund_stat]), "geometry contract: %s profile has %s at 0.0" % [ability_name, Stat.Type.keys()[refund_stat]])
		# Task X: a declared reach or speed stat needs its bonus key, or Earth and Wind do nothing for the ability.
		if not geometry.get_reach_stats().is_empty():
			check(data.stats_profile.base_stats.has(Stat.Type.REACH_BONUS), "geometry contract: %s profile has REACH_BONUS" % ability_name)
		if not geometry.get_speed_stats().is_empty():
			check(data.stats_profile.base_stats.has(Stat.Type.SPEED_BONUS), "geometry contract: %s profile has SPEED_BONUS" % ability_name)

	# f. Behavior guard: query shapes for a fixed stats dictionary are unchanged.
	var area_stats := _make_stats({Stat.Type.AOE_RADIUS: 200.0, Stat.Type.QUERY_RADIUS: 150.0})
	for scene_name in ["targeted_projectile_geometry", "straight_projectile_geometry", "mouse_aim_projectile_geometry", "chain_link_geometry"]:
		var circle := (drivers[scene_name] as GeometryDriver).get_query_shape(area_stats) as CircleShape2D
		check(circle != null and is_equal_approx(circle.radius, 150.0), "geometry contract: %s query circle still QUERY_RADIUS (150)" % scene_name)
	for scene_name in ["radial_pulse_geometry", "converging_vortex_geometry"]:
		var circle := (drivers[scene_name] as GeometryDriver).get_query_shape(area_stats) as CircleShape2D
		check(circle != null and is_equal_approx(circle.radius, 200.0), "geometry contract: %s query circle still AOE_RADIUS (200)" % scene_name)
	var wedge := (drivers["linear_sweep_geometry"] as GeometryDriver).get_query_shape(area_stats) as ConvexPolygonShape2D
	check(wedge != null and is_equal_approx(wedge.points[1].length(), 200.0) and is_equal_approx(wedge.points[2].length(), 200.0), "geometry contract: linear_sweep_geometry far vertices still AOE_RADIUS (200)")
	check((drivers["fissure_geometry"] as GeometryDriver).get_query_shape(area_stats) == null, "geometry contract: fissure_geometry query shape still null")
	check((drivers["orbiting_ring_geometry"] as GeometryDriver).get_query_shape(area_stats) == null, "geometry contract: orbiting_ring_geometry query shape still null")


# ---------------------------------------------------------------------------------------------
# Task X: SPEED_BONUS and REACH_BONUS, applied through StatBonus
# ---------------------------------------------------------------------------------------------

## Spawns a projectile with `stats` and returns the speed it applies.
func _spawn_projectile_speed(container: Node, stats: StatsContainer) -> float:
	var payload := CombatPayload.new()
	payload.stats_container_id = stats.get_instance_id()
	var projectile := (load("res://components/ability/projectile.tscn") as PackedScene).instantiate() as Projectile
	projectile.initialize_volume(Vector2(100000.0, 100000.0), Vector2.RIGHT, 0, payload)
	container.add_child(projectile)
	var speed := projectile.movement_speed
	projectile.queue_free()
	return speed


var _chain_hits: Array[int] = []


func _count_chain_hit(_payload: CombatPayload, index: int) -> void:
	_chain_hits[index] += 1


## Casts a chain from a bat to a second bat `gap` away and returns how many bats were hit.
func _cast_chain(stats: StatsContainer, gap: float) -> int:
	var chain := ChainLinkGeometry.new()
	world.add_child(chain)
	fx.track(chain)
	var origin := Vector2(84000.0, 84000.0)
	_chain_hits = [0, 0]
	var bats: Array[Enemy] = []
	for i in range(2):
		var bat := _spawn_bat()
		bat.set_physics_process(false)
		bat.global_position = origin + Vector2(gap * i, 0.0)
		bat.hurtbox_component.hit_received.connect(_count_chain_hit.bind(i))
		bats.append(bat)
	await tree.physics_frame
	await tree.physics_frame
	var payload := CombatPayload.new()
	payload.stats_container_id = stats.get_instance_id()
	var primary: Array = [bats[0].hurtbox_component]
	chain.execute_geometry({"hit_nodes": primary}, payload)
	var total := _chain_hits[0] + _chain_hits[1]
	for bat in bats:
		bat.queue_free()
	chain.queue_free()
	return total


## Starts an orbit with `stats` and returns [rotation_speed, orbit_radius, first shard hitbox radius].
func _start_orbit(stats: StatsContainer) -> Array:
	var orbit := (load("res://components/ability/drivers/geometry/persistent/orbiting_ring_geometry.tscn") as PackedScene).instantiate() as OrbitingRingGeometry
	world.add_child(orbit)
	fx.track(orbit)
	var caster := Node2D.new()
	world.add_child(caster)
	fx.track(caster)
	var payload := CombatPayload.new()
	payload.stats_container_id = stats.get_instance_id()
	payload.caster_instance_id = caster.get_instance_id()
	orbit.execute_geometry({"origin": Vector2(88000.0, 88000.0)}, payload)
	var shard_radius := 0.0
	if not orbit._active_shards.is_empty():
		shard_radius = ((orbit._active_shards[0] as OrbitingShard).collision_shape.shape as CircleShape2D).radius
	var result: Array = [orbit.rotation_speed, orbit.orbit_radius, shard_radius]
	orbit._terminate_persistent_delivery()
	orbit.queue_free()
	return result


func _list_gd_files(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	for entry in dir.get_directories():
		found.append_array(_list_gd_files(dir_path.path_join(entry)))
	for file in dir.get_files():
		if file.ends_with(".gd"):
			found.append(dir_path.path_join(file))
	return found


func _section_speed_reach_bonus() -> void:
	var proj_container := world.get_node("GameWorld/ProjectilesContainer")
	var space_state := tree.root.get_world_2d().direct_space_state

	# a. StatBonus.
	var helper_ok := true
	for bonus in [0.0, 0.1, 1.0]:
		var s := _make_stats({Stat.Type.AOE_RADIUS: 10.0, Stat.Type.PROJECTILE_MOVEMENT_SPEED: 500.0, Stat.Type.REACH_BONUS: bonus, Stat.Type.SPEED_BONUS: bonus})
		helper_ok = helper_ok and is_equal_approx(StatBonus.reach(s, Stat.Type.AOE_RADIUS), 10.0 * (1.0 + bonus)) \
				and is_equal_approx(StatBonus.speed(s, Stat.Type.PROJECTILE_MOVEMENT_SPEED), 500.0 * (1.0 + bonus))
	check(helper_ok, "bonus helper: reach and speed return base * (1 + bonus) for bonus 0, 0.1 and 1.0")
	check(is_equal_approx(StatBonus.reach(null, Stat.Type.AOE_RADIUS), 0.0) and is_equal_approx(StatBonus.speed(null, Stat.Type.PROJECTILE_MOVEMENT_SPEED), 0.0), "bonus helper: an invalid stats object returns 0.0")
	var no_key := _make_stats({Stat.Type.AOE_RADIUS: 10.0, Stat.Type.PROJECTILE_MOVEMENT_SPEED: 500.0})
	check(is_equal_approx(StatBonus.reach(no_key, Stat.Type.AOE_RADIUS), 10.0) and is_equal_approx(StatBonus.speed(no_key, Stat.Type.PROJECTILE_MOVEMENT_SPEED), 500.0), "bonus helper: a container with no bonus key behaves as bonus 0")

	# b. Reach doubles with REACH_BONUS 1.0 on every geometry.
	var reach_stats := _make_stats({
		Stat.Type.AOE_RADIUS: 10.0, Stat.Type.QUERY_RADIUS: 150.0, Stat.Type.REACH_BONUS: 1.0,
		Stat.Type.ORBIT_RADIUS: 50.0, Stat.Type.ORBIT_ROTATION_SPEED: 90.0, Stat.Type.PROJECTILE_AMOUNT: 2.0,
		Stat.Type.DURATION: 5.0, Stat.Type.PROJECTILE_MOVEMENT_SPEED: 100.0, Stat.Type.CHAIN_RADIUS: 60.0,
	})
	check(is_equal_approx(_spawn_projectile_radius(proj_container, reach_stats), 20.0), "reach bonus: projectile hitbox radius 10 -> 20")
	var pulse := RadialPulseGeometry.new()
	fx.track(pulse)
	var wide := _make_stats({Stat.Type.AOE_RADIUS: 200.0, Stat.Type.QUERY_RADIUS: 150.0, Stat.Type.REACH_BONUS: 1.0})
	check(is_equal_approx((pulse.get_query_shape(wide) as CircleShape2D).radius, 400.0), "reach bonus: radial pulse query circle 200 -> 400")
	var sweep := LinearSweepGeometry.new()
	fx.track(sweep)
	var wedge := sweep.get_query_shape(wide) as ConvexPolygonShape2D
	check(is_equal_approx(wedge.points[1].length(), 400.0) and is_equal_approx(wedge.points[2].length(), 400.0), "reach bonus: linear sweep wedge length 200 -> 400")
	var fissure_hits := await _cast_fissure(_make_stats({Stat.Type.AOE_RADIUS: 40.0, Stat.Type.REACH_BONUS: 1.0}), Vector2(80000.0, 80000.0), [Vector2(70, 85), Vector2(70, 95)])
	check(fissure_hits[0] == 1 and fissure_hits[1] == 0, "reach bonus: fissure first strike radius 40 -> 80 (hit at 85, miss at 95)")
	var vortex := ConvergingVortexGeometry.new()
	fx.track(vortex)
	check(is_equal_approx((vortex.get_query_shape(wide) as CircleShape2D).radius, 400.0), "reach bonus: converging vortex query circle 200 -> 400")
	var vortex_origin := Vector2(60000.0, 60000.0)
	var vortex_bat := _spawn_bat()
	vortex_bat.set_physics_process(false)
	vortex_bat.global_position = vortex_origin + Vector2(200.0, 0.0)
	vortex_bat.velocity = Vector2.ZERO
	var vortex_payload := CombatPayload.new()
	vortex_payload.stats_container_id = wide.get_instance_id()
	vortex._process_volume_hit(vortex_bat.hurtbox_component, vortex_origin, vortex_payload)
	check(is_equal_approx(vortex_bat.velocity.length(), vortex.horizontal_suction_force * 1.5), "reach bonus: converging vortex falloff uses the doubled reach (weight 0.5 at 200 of 400)")
	var chain_wide := await _cast_chain(_make_stats({Stat.Type.CHAIN_RADIUS: 60.0, Stat.Type.REACH_BONUS: 1.0}), 100.0)
	var chain_plain := await _cast_chain(_make_stats({Stat.Type.CHAIN_RADIUS: 60.0, Stat.Type.REACH_BONUS: 0.0}), 100.0)
	check(chain_wide == 2 and chain_plain == 1, "reach bonus: chain 60 -> 120 reaches a bat 100 away (hits %d); with bonus 0 it does not (hits %d)" % [chain_wide, chain_plain])
	var orbit_wide := _start_orbit(reach_stats)
	check(is_equal_approx(orbit_wide[1], 100.0) and is_equal_approx(orbit_wide[2], 20.0), "reach bonus: orbit radius 50 -> 100 and shard hitbox 10 -> 20")
	var burst_shape := CircleBurstShape.new()
	var burst_origin := Vector2(86000.0, 86000.0)
	var bats := await _spawn_burst_bats(burst_origin, [Vector2(45, 0)])
	var burst_stats := _make_stats({Stat.Type.AOE_RADIUS: 20.0, Stat.Type.REACH_BONUS: 1.0})
	var plain_burst_stats := _make_stats({Stat.Type.AOE_RADIUS: 20.0})
	check(burst_shape.find_targets(burst_origin, burst_stats, space_state, 0).size() == 1 and burst_shape.find_targets(burst_origin, plain_burst_stats, space_state, 0).is_empty(), "reach bonus: burst circle radius 20 -> 40 catches a bat at 45 (hurtbox radius 10); without it, no")
	_free_bats(bats)
	LingeringZone.reset_registry()
	var zone_scene := load(TEST_LINGERING_ZONE) as PackedScene
	var zone_def := _zone_burst(&"test_bonus_zone", zone_scene)
	var no_statuses: Array[StatusEffect] = []
	var zone := await _spawn_zone(zone_def, _zone_payload(_make_stats({Stat.Type.AOE_RADIUS: 10.0, Stat.Type.REACH_BONUS: 1.0}), zone_def, no_statuses), Vector2(86500.0, 86500.0))
	check(zone != null and is_equal_approx(zone._radius, 80.0), "reach bonus: lingering zone radius (10 * 2) * multiplier 4 = 80")
	if zone != null:
		zone.queue_free()
	LingeringZone.reset_registry()
	# QUERY_RADIUS targeting range is not a reach stat.
	var query_only := _make_stats({Stat.Type.QUERY_RADIUS: 150.0, Stat.Type.REACH_BONUS: 1.0})
	var query_ok := is_equal_approx((pulse.get_query_shape(query_only) as CircleShape2D).radius, 150.0)
	for scene_path in [GEOMETRY_DRIVER_DIR + "/projectile/targeted_projectile_geometry.tscn", GEOMETRY_DRIVER_DIR + "/area/chain_link_geometry.tscn"]:
		var driver := (load(scene_path) as PackedScene).instantiate() as GeometryDriver
		fx.track(driver)
		query_ok = query_ok and is_equal_approx((driver.get_query_shape(wide) as CircleShape2D).radius, 150.0)
	check(query_ok, "reach bonus: QUERY_RADIUS targeting range (150) does not change")

	# c. Speed doubles with SPEED_BONUS 1.0.
	var fast := _make_stats({Stat.Type.PROJECTILE_MOVEMENT_SPEED: 100.0, Stat.Type.ORBIT_ROTATION_SPEED: 90.0, Stat.Type.ORBIT_RADIUS: 50.0,
			Stat.Type.AOE_RADIUS: 10.0, Stat.Type.PROJECTILE_AMOUNT: 2.0, Stat.Type.DURATION: 5.0, Stat.Type.SPEED_BONUS: 1.0})
	check(is_equal_approx(_spawn_projectile_speed(proj_container, fast), 200.0), "speed bonus: projectile speed 100 -> 200")
	var fast_orbit := _start_orbit(fast)
	check(is_equal_approx(fast_orbit[0], 180.0) and is_equal_approx(fast_orbit[1], 50.0) and is_equal_approx(fast_orbit[2], 10.0), "speed bonus: orbit rotation 90 -> 180, orbit radius and shard hitbox unchanged")
	var speed_pulse := (pulse.get_query_shape(_make_stats({Stat.Type.AOE_RADIUS: 200.0, Stat.Type.SPEED_BONUS: 1.0})) as CircleShape2D).radius
	check(is_equal_approx(speed_pulse, 200.0) and is_equal_approx(_spawn_projectile_radius(proj_container, fast), 10.0), "speed bonus: instant geometries and the projectile hitbox are unaffected")

	# d. The real cards.
	var wind := load(WIND_CARD) as UpgradeDefinition
	var earth := load(EARTH_CARD) as UpgradeDefinition
	var player := fx.fresh_player()
	var ability := fx.mount_arcane_bolt(player)
	var sc := ability.stats_container
	var wind_ok := true
	var earth_ok := true
	for level in range(0, 4):
		if level > 0:
			player.run_ledger_component.log_slot_specific_purchase(wind, 1)
			player.run_ledger_component.log_slot_specific_purchase(earth, 1)
		wind_ok = wind_ok and is_equal_approx(sc.get_final_stat_value(Stat.Type.SPEED_BONUS), 0.1 * level) \
				and is_equal_approx(sc.get_final_stat_value(Stat.Type.PROJECTILE_MOVEMENT_SPEED), 500.0)
		earth_ok = earth_ok and is_equal_approx(sc.get_final_stat_value(Stat.Type.REACH_BONUS), 0.1 * level) \
				and is_equal_approx(sc.get_final_stat_value(Stat.Type.AOE_RADIUS), 10.0)
	check(wind_ok, "Wind levels 0-3: SPEED_BONUS 0, 0.1, 0.2, 0.3 and PROJECTILE_MOVEMENT_SPEED stays 500")
	check(earth_ok, "Earth levels 0-3: REACH_BONUS 0, 0.1, 0.2, 0.3 and AOE_RADIUS stays 10")
	check(is_equal_approx(StatBonus.speed(sc, Stat.Type.PROJECTILE_MOVEMENT_SPEED), 650.0), "Wind 3: effective projectile speed 650")
	var bolt_payload := CombatCalculations.generate_hit_payload(player, sc, ability.tag_component)
	check(is_equal_approx(_spawn_projectile_radius_from_payload(proj_container, bolt_payload), 13.0), "Earth 3: projectile hitbox radius 13")
	var evolved := _plasma_evolved_player()
	var arc := evolved.ability_container.get_ability_by_slot(1)
	check(is_instance_valid(arc) and is_equal_approx(StatBonus.reach(arc.stats_container, Stat.Type.CHAIN_RADIUS), 150.0), "Earth 0 on the evolved Arc Bolt: chain reach 150")
	for i in range(3):
		evolved.run_ledger_component.log_slot_specific_purchase(earth, 1)
	check(is_instance_valid(arc) and is_equal_approx(StatBonus.reach(arc.stats_container, Stat.Type.CHAIN_RADIUS), 195.0) and is_equal_approx(arc.stats_container.get_final_stat_value(Stat.Type.CHAIN_RADIUS), 150.0), "Earth 3 on the evolved Arc Bolt: chain reach 150 -> 195 (the stat itself stays 150)")

	# e. Guards.
	var wind_mods := 0
	var earth_mods := 0
	var stray := 0
	for path in _list_tres("res://resources"):
		var resource := load(path)
		var modifiers: Array[StatModifier] = []
		if resource is UpgradeDefinition:
			modifiers.append_array(resource.stat_modifiers)
			if resource.status_effect_payload != null:
				modifiers.append_array(resource.status_effect_payload.stat_modifiers)
		elif resource is StatusEffect:
			modifiers.append_array(resource.stat_modifiers)
		for modifier in modifiers:
			var is_wind: bool = path == WIND_CARD
			var is_earth: bool = path == EARTH_CARD
			if modifier.target_stat_type == Stat.Type.SPEED_BONUS:
				wind_mods += 1 if is_wind else 0
				stray += 0 if is_wind else 1
			elif modifier.target_stat_type == Stat.Type.REACH_BONUS:
				earth_mods += 1 if is_earth else 0
				stray += 0 if is_earth else 1
			elif is_wind or is_earth:
				stray += 1
	check(wind_mods == 1 and earth_mods == 1 and stray == 0, "bonus guards: only Wind modifies SPEED_BONUS, only Earth modifies REACH_BONUS, and neither modifies anything else")
	check(wind.stat_modifiers.size() == 1 and earth.stat_modifiers.size() == 1 and wind.stat_modifiers[0].type == StatModifier.Type.FLAT and earth.stat_modifiers[0].type == StatModifier.Type.FLAT, "bonus guards: the Wind and Earth cards each carry one FLAT modifier")
	# Every read of a reach or speed stat goes through StatBonus: no script reads one directly.
	var direct_reads: Array[String] = []
	for dir_path in ["res://components", "res://scenes", "res://autoloads", "res://ui", "res://debug"]:
		for path in _list_gd_files(dir_path):
			if path.ends_with("stat_bonus.gd"):
				continue
			var source := FileAccess.get_file_as_string(path)
			for stat_name in ["AOE_RADIUS", "CHAIN_RADIUS", "ORBIT_RADIUS", "PROJECTILE_MOVEMENT_SPEED", "ORBIT_ROTATION_SPEED"]:
				if source.contains("get_final_stat_value(Stat.Type.%s)" % stat_name):
					direct_reads.append("%s:%s" % [path.get_file(), stat_name])
	check(direct_reads.is_empty(), "bonus guards: no script reads a reach or speed stat directly %s" % [direct_reads])
	# Every geometry declares only stats the helper scales.
	var known: Array[int] = [Stat.Type.AOE_RADIUS, Stat.Type.CHAIN_RADIUS, Stat.Type.ORBIT_RADIUS, Stat.Type.PROJECTILE_MOVEMENT_SPEED, Stat.Type.ORBIT_ROTATION_SPEED]
	var declared_ok := true
	for path in _list_tscn_files(GEOMETRY_DRIVER_DIR):
		var geometry := (load(path) as PackedScene).instantiate() as GeometryDriver
		fx.track(geometry)
		for stat_id in _stat_ids(geometry.get_reach_stats()) + _stat_ids(geometry.get_speed_stats()):
			declared_ok = declared_ok and known.has(stat_id)
	check(declared_ok, "bonus guards: every declared reach and speed stat is one the helper scales")


var _std_hits: Dictionary = {}


func _count_std_hit(_payload: CombatPayload, key: String) -> void:
	_std_hits[key] = int(_std_hits.get(key, 0)) + 1


## Spawns a frozen bat at `pos` whose hits are counted in _std_hits under `key`.
func _spawn_counted_bat(pos: Vector2, key: String) -> Enemy:
	var bat := _spawn_bat()
	bat.set_physics_process(false)
	bat.global_position = pos
	bat.velocity = Vector2.ZERO
	_std_hits[key] = 0
	bat.hurtbox_component.hit_received.connect(_count_std_hit.bind(key))
	return bat


func _section_geometry_standardization() -> void:
	var space_state := tree.root.get_world_2d().direct_space_state

	# a. The constants.
	check(CombatPhysics.ENEMY_HURTBOX_MASK == 4 and CombatPhysics.MAX_QUERY_RESULTS == 32, "standardization: mask is 4 and the result limit is 32")

	# b. filter_enemy_hurtboxes.
	var player := fx.fresh_player()
	var enemy_a := _spawn_counted_bat(Vector2(90000, 90000), "filter_a")
	var enemy_b := _spawn_counted_bat(Vector2(90100, 90000), "filter_b")
	var excluded := _spawn_counted_bat(Vector2(90200, 90000), "filter_x")
	var plain_area := Area2D.new()
	fx.track(plain_area)
	var raw: Array[Dictionary] = [
		{"collider": enemy_a.hurtbox_component},
		{"collider": player.hurtbox_component},
		{"collider": excluded.hurtbox_component},
		{"collider": null},
		{"collider": plain_area},
		{"collider": enemy_b.hurtbox_component},
		{"collider": enemy_a.hurtbox_component},
	]
	var filtered := SpatialQuery.filter_enemy_hurtboxes(raw, excluded.hurtbox_component.get_instance_id())
	check(filtered.size() == 3 and filtered[0] == enemy_a.hurtbox_component and filtered[1] == enemy_b.hurtbox_component and filtered[2] == enemy_a.hurtbox_component,
			"standardization filter: keeps only enemy hurtboxes, in order, and keeps a repeated one twice")
	var unfiltered := SpatialQuery.filter_enemy_hurtboxes(raw)
	check(unfiltered.size() == 4 and unfiltered.has(excluded.hurtbox_component) and not unfiltered.has(player.hurtbox_component),
			"standardization filter: without an exclude id the excluded bat is kept; the player hurtbox is still dropped")

	# c. query_enemy_hurtboxes.
	var origin := Vector2(91000, 91000)
	var circle := CircleShape2D.new()
	circle.radius = 50.0
	var inside_1 := _spawn_counted_bat(origin + Vector2(10, 0), "q_in1")
	var inside_2 := _spawn_counted_bat(origin + Vector2(0, 30), "q_in2")
	var outside := _spawn_counted_bat(origin + Vector2(200, 0), "q_out")
	await tree.physics_frame
	await tree.physics_frame
	var found := SpatialQuery.query_enemy_hurtboxes(space_state, circle, origin)
	check(found.size() == 2 and found.has(inside_1.hurtbox_component) and found.has(inside_2.hurtbox_component) and not found.has(outside.hurtbox_component),
			"standardization query: returns every enemy bat inside the circle and none outside")
	var found_excluding := SpatialQuery.query_enemy_hurtboxes(space_state, circle, origin, inside_1.hurtbox_component.get_instance_id())
	check(found_excluding.size() == 1 and found_excluding[0] == inside_2.hurtbox_component, "standardization query: honors the exclude id")

	# d. The cap.
	var crowd_origin := Vector2(93000, 93000)
	for i in range(40):
		_spawn_counted_bat(crowd_origin, "crowd_%d" % i)
	await tree.physics_frame
	await tree.physics_frame
	var crowd := SpatialQuery.query_enemy_hurtboxes(space_state, circle, crowd_origin)
	check(crowd.size() == 32, "standardization cap: 40 bats in one circle return exactly 32 (the current limit, not a goal); got %d" % crowd.size())

	# e. Hierarchy.
	var pulse := RadialPulseGeometry.new()
	var sweep := LinearSweepGeometry.new()
	var fissure := FissureGeometry.new()
	var chain := ChainLinkGeometry.new()
	for driver in [pulse, sweep, fissure, chain]:
		world.add_child(driver)
		fx.track(driver)
	check(pulse is AreaGeometry and sweep is AreaGeometry, "standardization hierarchy: radial pulse and linear sweep are AreaGeometry")
	var fissure_as_driver: GeometryDriver = fissure
	var chain_as_driver: GeometryDriver = chain
	check(not (fissure_as_driver is AreaGeometry) and not (chain_as_driver is AreaGeometry), "standardization hierarchy: fissure and chain are GeometryDriver but not AreaGeometry")

	# f. Behavior per geometry.
	var area_origin := Vector2(95000, 95000)
	var player_pos := player.global_position
	player.velocity = Vector2.ZERO
	var pulse_stats := _make_stats({Stat.Type.AOE_RADIUS: 100.0, Stat.Type.QUERY_RADIUS: 150.0})
	var pulse_in := _spawn_counted_bat(area_origin + Vector2(60, 0), "pulse_in")
	var pulse_edge := _spawn_counted_bat(area_origin + Vector2(0, -105), "pulse_edge")
	var pulse_out := _spawn_counted_bat(area_origin + Vector2(130, 0), "pulse_out")
	var sweep_in := _spawn_counted_bat(area_origin + Vector2(0, 5000) + Vector2(60, 0), "sweep_in")
	var sweep_behind := _spawn_counted_bat(area_origin + Vector2(0, 5000) + Vector2(-60, 0), "sweep_behind")
	await tree.physics_frame
	await tree.physics_frame
	var query_component := SpatialQueryComponent.new()
	world.add_child(query_component)
	fx.track(query_component)
	var payload := CombatPayload.new()
	payload.stats_container_id = pulse_stats.get_instance_id()
	pulse.execute_geometry(query_component.execute_spatial_query(area_origin, pulse.get_query_shape(pulse_stats)), payload)
	check(int(_std_hits["pulse_in"]) == 1 and int(_std_hits["pulse_edge"]) == 1 and int(_std_hits["pulse_out"]) == 0,
			"standardization behavior: radial pulse hits bats inside AOE_RADIUS (hurtbox radius 10) and none outside")
	var sweep_origin := area_origin + Vector2(0, 5000)
	sweep.execute_geometry(query_component.execute_spatial_query(sweep_origin, sweep.get_query_shape(pulse_stats)), payload)
	check(int(_std_hits["sweep_in"]) == 1 and int(_std_hits["sweep_behind"]) == 0, "standardization behavior: linear sweep hits a bat in its wedge and not one behind it")

	# Player hurtbox in reach of fissure and chain is never hit.
	var shared_origin := Vector2(97000, 97000)
	_std_hits["player"] = 0
	player.hurtbox_component.hit_received.connect(_count_std_hit.bind("player"))
	player.global_position = shared_origin + Vector2(70, 0)
	var fissure_bat := _spawn_counted_bat(shared_origin + Vector2(70, 20), "fissure_bat")
	var chain_origin := shared_origin + Vector2(0, 3000)
	var chain_first := _spawn_counted_bat(chain_origin, "chain_first")
	var chain_second := _spawn_counted_bat(chain_origin + Vector2(60, 0), "chain_second")
	await tree.physics_frame
	await tree.physics_frame
	var fissure_stats := _make_stats({Stat.Type.AOE_RADIUS: 40.0})
	var fissure_payload := CombatPayload.new()
	fissure_payload.stats_container_id = fissure_stats.get_instance_id()
	fissure.execute_geometry({"origin": shared_origin}, fissure_payload)
	check(int(_std_hits["fissure_bat"]) == 1 and int(_std_hits["player"]) == 0, "standardization behavior: fissure hits the bat and never the player hurtbox in its reach")
	player.global_position = chain_origin + Vector2(30, 0)
	var chain_stats := _make_stats({Stat.Type.CHAIN_RADIUS: 100.0, Stat.Type.QUERY_RADIUS: 100.0})
	var chain_payload := CombatPayload.new()
	chain_payload.stats_container_id = chain_stats.get_instance_id()
	chain.execute_geometry({"hit_nodes": [chain_first.hurtbox_component]}, chain_payload)
	check(int(_std_hits["chain_first"]) == 1 and int(_std_hits["chain_second"]) == 1 and int(_std_hits["player"]) == 0,
			"standardization behavior: chain hits both bats and never the player hurtbox in its reach")
	player.global_position = player_pos
	player.hurtbox_component.hit_received.disconnect(_count_std_hit.bind("player"))

	# g. Duplicate-declaration guard.
	var mask_declared: Array[String] = []
	var limit_declared: Array[String] = []
	var driver_leftovers: Array[String] = []
	var query_component_names: Array[String] = []
	for dir_path in ["res://components", "res://scenes", "res://debug", "res://ui"]:
		for path in _list_gd_files(dir_path):
			var text := FileAccess.get_file_as_string(path)
			if text.contains("const ENEMY_HURTBOX_MASK"):
				mask_declared.append(path)
			if text.contains("const MAX_QUERY_RESULTS"):
				limit_declared.append(path)
			var is_driver_file := path.begins_with("res://components/ability/drivers/") or path.begins_with("res://components/ability/bursts/")
			if is_driver_file and (text.contains("max_results_buffer") or text.contains("enemy_collision_mask")):
				driver_leftovers.append(path)
			if path == "res://components/ability/spatial_query_component.gd":
				query_component_names.append("enemy_collision_mask" if text.contains("enemy_collision_mask") else "")
				query_component_names.append("max_results_buffer" if text.contains("max_results_buffer") else "")
	check(mask_declared == ["res://components/utility/combat_physics.gd"], "standardization guard: ENEMY_HURTBOX_MASK is defined only in combat_physics.gd (found %s)" % str(mask_declared))
	check(limit_declared == ["res://components/utility/combat_physics.gd"], "standardization guard: MAX_QUERY_RESULTS is defined only in combat_physics.gd (found %s)" % str(limit_declared))
	check(driver_leftovers.is_empty(), "standardization guard: no geometry driver, burst shape or burst effect declares its own mask or buffer (found %s)" % str(driver_leftovers))
	check(query_component_names == ["enemy_collision_mask", "max_results_buffer"], "standardization guard: SpatialQueryComponent keeps its two exports under the standard names")


const SequenceProbe = preload("res://tools/headless/sequence_probe.gd")


func _wait_physics_frames(count: int) -> void:
	for i in range(count):
		await tree.physics_frame


## Number of hurtbox hits recorded under the keys "<tag>_0" .. "<tag>_<count - 1>" that are above 0.
func _tagged_hit_count(tag: String, count: int) -> int:
	var total := 0
	for i in range(count):
		if int(_std_hits.get("%s_%d" % [tag, i], 0)) > 0:
			total += 1
	return total


## Spawns six frozen bats 100 apart from `origin`, casts a chain at the first one and returns {"chain", "bats", "stats"}.
## The chain's finish count is recorded in _std_hits["fin_<tag>"].
func _cast_chain_line(tag: String, origin: Vector2, delay: float, speed_bonus: float) -> Dictionary:
	var chain := ChainLinkGeometry.new()
	chain.step_delay = delay
	world.add_child(chain)
	fx.track(chain)
	_std_hits["fin_" + tag] = 0
	chain.delivery_finished.connect(func() -> void: _std_hits["fin_" + tag] = int(_std_hits["fin_" + tag]) + 1)
	var bats: Array[Enemy] = []
	for i in range(6):
		bats.append(_spawn_counted_bat(origin + Vector2(100.0 * i, 0.0), "%s_%d" % [tag, i]))
	await _wait_physics_frames(2)
	var stats := _make_stats({Stat.Type.CHAIN_RADIUS: 150.0, Stat.Type.SPEED_BONUS: speed_bonus})
	var payload := CombatPayload.new()
	payload.stats_container_id = stats.get_instance_id()
	chain.execute_geometry({"hit_nodes": [bats[0].hurtbox_component]}, payload)
	return {"chain": chain, "bats": bats, "stats": stats}


func _section_stepped_delivery() -> void:
	# a. StatBonus.interval.
	var interval_ok := true
	for pair in [[0.0, 0.2], [1.0, 0.1], [0.5, 0.2 / 1.5]]:
		var s := _make_stats({Stat.Type.SPEED_BONUS: pair[0]})
		interval_ok = interval_ok and is_equal_approx(StatBonus.interval(s, 0.2), pair[1])
	check(interval_ok, "interval helper: 0.2 s with SPEED_BONUS 0 / 1.0 / 0.5 gives 0.2 / 0.1 / 0.1333")
	check(is_equal_approx(StatBonus.interval(null, 0.2), 0.2), "interval helper: an invalid stats object returns the input")

	# b. SequencedGeometry through the test-only probe.
	var timed: SequencedGeometry = SequenceProbe.new()
	world.add_child(timed)
	fx.track(timed)
	timed.start(4, 0.1)
	check(timed.steps_run == [0] and timed.finished_count == 0, "sequence: step 0 runs at once, the rest wait")
	await _wait_physics_frames(3)
	check(timed.steps_run == [0], "sequence: no later step before the delay has passed")
	await _wait_physics_frames(6)
	check(timed.steps_run == [0, 1] and timed.finished_count == 0, "sequence: step 1 runs after about one delay")
	await _wait_physics_frames(40)
	check(timed.steps_run == [0, 1, 2, 3] and timed.finished_count == 1, "sequence: every step runs in order and delivery finishes once")
	await _wait_physics_frames(10)
	check(timed.finished_count == 1, "sequence: no second finish afterwards")

	var early: SequencedGeometry = SequenceProbe.new()
	early.stop_at = 1
	world.add_child(early)
	fx.track(early)
	early.start(4, 0.05)
	await _wait_physics_frames(40)
	check(early.steps_run == [0, 1] and early.finished_count == 1, "sequence: returning false ends it early, with one finish")

	var instant: SequencedGeometry = SequenceProbe.new()
	world.add_child(instant)
	fx.track(instant)
	instant.start(3, 0.0)
	check(instant.steps_run == [0, 1, 2] and instant.finished_count == 1, "sequence: delay 0 runs every step and finishes before the call returns")
	var instant_early: SequencedGeometry = SequenceProbe.new()
	instant_early.stop_at = 1
	world.add_child(instant_early)
	fx.track(instant_early)
	instant_early.start(5, 0.0)
	check(instant_early.steps_run == [0, 1] and instant_early.finished_count == 1, "sequence: delay 0 honors the early stop")

	var replaced: SequencedGeometry = SequenceProbe.new()
	world.add_child(replaced)
	fx.track(replaced)
	replaced.start(5, 0.1)
	await _wait_physics_frames(9)
	replaced.steps_run.clear()
	replaced.start(2, 0.1)
	await _wait_physics_frames(40)
	check(replaced.steps_run == [0, 1] and replaced.finished_count == 1, "sequence: a second sequence replaces a running one with no extra finish")

	var doomed: SequencedGeometry = SequenceProbe.new()
	world.add_child(doomed)
	doomed.start(5, 0.1)
	await _wait_physics_frames(3)
	doomed.free()
	await _wait_physics_frames(20)
	check(not is_instance_valid(doomed), "sequence: freeing the node mid-sequence ends it without an error")

	# c. Chain link with a step delay.
	var plain := await _cast_chain_line("cn_a", Vector2(100000, 100000), 0.1, 0.0)
	check(_tagged_hit_count("cn_a", 6) == 1, "stepped chain: right after the cast only the first bat is hit")
	await _wait_physics_frames(9)
	check(_tagged_hit_count("cn_a", 6) == 2 and int(_std_hits["fin_cn_a"]) == 0, "stepped chain: after about 0.15 s exactly two bats are hit")
	await _wait_physics_frames(60)
	check(_tagged_hit_count("cn_a", 6) == 5 and int(_std_hits["fin_cn_a"]) == 1 and int(_std_hits["cn_a_5"]) == 0, "stepped chain: later all five bats are hit, the sixth is not, and delivery finishes once")

	var boosted := await _cast_chain_line("cn_b", Vector2(100000, 101000), 0.1, 1.0)
	await _wait_physics_frames(9)
	check(_tagged_hit_count("cn_b", 6) >= 3 and _tagged_hit_count("cn_b", 6) > 2, "stepped chain: SPEED_BONUS 1.0 bounces twice as fast (3 or more hits at the checkpoint where the plain chain had 2)")
	await _wait_physics_frames(60)
	check(_tagged_hit_count("cn_b", 6) == 5 and int(_std_hits["fin_cn_b"]) == 1, "stepped chain: the boosted chain still ends with five hits and one finish")

	var moved := await _cast_chain_line("cn_m", Vector2(100000, 102000), 0.1, 0.0)
	var moved_bats: Array = moved["bats"]
	moved_bats[1].global_position += Vector2(0, 5000)
	moved_bats[3].global_position = Vector2(100000, 102000) + Vector2(60, 40)
	await _wait_physics_frames(80)
	check(int(_std_hits["cn_m_1"]) == 0 and int(_std_hits["cn_m_3"]) == 1, "stepped chain: a bat moved out of range is skipped and one moved into range is chosen")

	var freed := await _cast_chain_line("cn_f", Vector2(100000, 103000), 0.1, 0.0)
	var freed_bats: Array = freed["bats"]
	freed_bats[0].queue_free()
	await _wait_physics_frames(80)
	check(int(_std_hits["cn_f_1"]) == 1 and _tagged_hit_count("cn_f", 6) >= 4 and int(_std_hits["fin_cn_f"]) == 1, "stepped chain: freeing the first bat does not stop the chain, which continues from its last position")

	var sync_chain := ChainLinkGeometry.new()
	world.add_child(sync_chain)
	fx.track(sync_chain)
	check(is_equal_approx(sync_chain.step_delay, 0.0), "stepped chain: .new() defaults to delay 0")
	_std_hits["fin_sync"] = 0
	sync_chain.delivery_finished.connect(func() -> void: _std_hits["fin_sync"] = int(_std_hits["fin_sync"]) + 1)
	var sync_origin := Vector2(100000, 104000)
	var sync_bats: Array[Enemy] = []
	for i in range(6):
		sync_bats.append(_spawn_counted_bat(sync_origin + Vector2(100.0 * i, 0.0), "cn_s_%d" % i))
	await _wait_physics_frames(2)
	var sync_payload := CombatPayload.new()
	sync_payload.stats_container_id = _make_stats({Stat.Type.CHAIN_RADIUS: 150.0}).get_instance_id()
	sync_chain.execute_geometry({"hit_nodes": [sync_bats[0].hurtbox_component]}, sync_payload)
	check(_tagged_hit_count("cn_s", 6) == 5 and int(_std_hits["cn_s_5"]) == 0 and int(_std_hits["fin_sync"]) == 1, "stepped chain: delay 0 hits five bats and finishes once before the call returns")

	# d. Fissure with a step delay.
	var player := fx.fresh_player()
	player.velocity = Vector2.ZERO
	var fissure_origin := Vector2(100000, 106000)
	var fissure := FissureGeometry.new()
	fissure.step_delay = 0.1
	world.add_child(fissure)
	fx.track(fissure)
	_std_hits["fin_fissure"] = 0
	fissure.delivery_finished.connect(func() -> void: _std_hits["fin_fissure"] = int(_std_hits["fin_fissure"]) + 1)
	# Strikes sit at +70, +140, +210 on x with radii 40, 55, 70; hurtboxes add 10.
	var bat_first := _spawn_counted_bat(fissure_origin + Vector2(70, 0), "fs_first")
	var bat_walks_in := _spawn_counted_bat(fissure_origin + Vector2(140, 300), "fs_in")
	var bat_walks_out := _spawn_counted_bat(fissure_origin + Vector2(140, 0), "fs_out")
	var bat_third := _spawn_counted_bat(fissure_origin + Vector2(210, 0), "fs_third")
	await _wait_physics_frames(2)
	var fissure_payload := CombatPayload.new()
	fissure_payload.stats_container_id = _make_stats({Stat.Type.AOE_RADIUS: 40.0}).get_instance_id()
	fissure.execute_geometry({"origin": fissure_origin}, fissure_payload)
	player.velocity = Vector2(0, 100)
	check(int(_std_hits["fs_first"]) == 1 and int(_std_hits["fs_third"]) == 0 and int(_std_hits["fs_out"]) == 0, "stepped fissure: the first strike hits at once, the later ones wait")
	await _wait_physics_frames(3)
	bat_walks_in.global_position = fissure_origin + Vector2(140, 50)
	bat_walks_out.global_position = fissure_origin + Vector2(140, 300)
	await _wait_physics_frames(6)
	check(int(_std_hits["fs_third"]) == 0 and int(_std_hits["fin_fissure"]) == 0, "stepped fissure: a bat at the third strike is not hit before about 0.2 s")
	await _wait_physics_frames(40)
	check(int(_std_hits["fs_third"]) == 1 and int(_std_hits["fs_first"]) == 1, "stepped fissure: the third strike hits its bat later, along the direction fixed at cast time")
	check(int(_std_hits["fs_in"]) == 1 and int(_std_hits["fs_out"]) == 0, "stepped fissure: a bat that walks into the second circle is hit and one that leaves is not")
	check(int(_std_hits["fin_fissure"]) == 1, "stepped fissure: delivery finishes once")
	player.velocity = Vector2.ZERO
	var plain_fissure := FissureGeometry.new()
	check(is_equal_approx(plain_fissure.step_delay, 0.0) and is_equal_approx(ChainLinkGeometry.new().step_delay, 0.0), "stepped fissure: .new() defaults to delay 0 for both stepped geometries")
	plain_fissure.free()

	# e. Evolution in the middle of a chain.
	var evo_player := _plasma_evolved_player()
	var evo_ability := evo_player.ability_container.get_ability_by_slot(1)
	var old_driver := evo_ability.geometry_driver
	var evo_origin := Vector2(100000, 108000)
	var evo_bats: Array[Enemy] = []
	for i in range(6):
		evo_bats.append(_spawn_counted_bat(evo_origin + Vector2(100.0 * i, 0.0), "ev_%d" % i))
	await _wait_physics_frames(2)
	var evo_payload := CombatPayload.new()
	evo_payload.stats_container_id = evo_ability.stats_container.get_instance_id()
	var chain_driver := old_driver as ChainLinkGeometry
	check(chain_driver != null and is_equal_approx(chain_driver.step_delay, 0.08), "evolution mid-chain: the evolved ability runs the shipped chain scene with delay 0.08")
	if chain_driver != null:
		chain_driver.execute_geometry({"hit_nodes": [evo_bats[0].hurtbox_component]}, evo_payload)
	evo_player.ability_container.execute_ability_evolution(load(ARC_BOLT_DATA) as AbilityData)
	await _wait_physics_frames(30)
	check(not is_instance_valid(old_driver) and is_instance_valid(evo_ability.geometry_driver), "evolution mid-chain: the old geometry is gone and a new one is mounted")
	check(_tagged_hit_count("ev", 6) == 1, "evolution mid-chain: the old chain stopped after its first hit")
	check(not evo_ability._cooldown_timer.is_stopped(), "evolution mid-chain: the ability's cooldown is running afterwards")

	# f. Shipped scenes and the class tree.
	var chain_scene := (load(GEOMETRY_DRIVER_DIR + "/area/chain_link_geometry.tscn") as PackedScene).instantiate() as ChainLinkGeometry
	var fissure_scene := (load(GEOMETRY_DRIVER_DIR + "/area/fissure_geometry.tscn") as PackedScene).instantiate() as FissureGeometry
	fx.track(chain_scene)
	fx.track(fissure_scene)
	check(is_equal_approx(chain_scene.step_delay, 0.08) and is_equal_approx(fissure_scene.step_delay, 0.12), "stepped scenes: chain_link_geometry.tscn sets 0.08 and fissure_geometry.tscn sets 0.12")
	var sequenced_scenes: Array[String] = []
	for path in _list_tscn_files(GEOMETRY_DRIVER_DIR):
		var scene_driver := (load(path) as PackedScene).instantiate() as GeometryDriver
		fx.track(scene_driver)
		if scene_driver is SequencedGeometry:
			sequenced_scenes.append(path.get_file().get_basename())
	sequenced_scenes.sort()
	check(sequenced_scenes == ["chain_link_geometry", "fissure_geometry"], "stepped scenes: only chain link and fissure extend SequencedGeometry (found %s)" % str(sequenced_scenes))


## A slot-1 lane on the player's ledger with `values` as its profile, plus `frost` Frost and `wind` Wind levels bought for slot 1.
func _indirect_lane(player: Player, values: Dictionary, frost: int, wind: int) -> StatsContainer:
	var lane := _make_stats(values, 1, player.run_ledger_component)
	for i in range(frost):
		player.run_ledger_component.log_slot_specific_purchase(load(FROST_CARD) as UpgradeDefinition, 1)
	for i in range(wind):
		player.run_ledger_component.log_slot_specific_purchase(load(WIND_CARD) as UpgradeDefinition, 1)
	return lane


func _section_indirect_scaling() -> void:
	var player := fx.fresh_player()
	var frost := load(FROST_CARD) as UpgradeDefinition
	var wind := load(WIND_CARD) as UpgradeDefinition
	check(frost.indirect_effect != null and frost.indirect_effect.kind == IndirectEffectDefinition.Kind.COOLDOWN_DAMAGE and frost.indirect_effect.unlock_level == 2, "indirect: Frost carries a COOLDOWN_DAMAGE effect unlocking at level 2")
	check(wind.indirect_effect != null and wind.indirect_effect.kind == IndirectEffectDefinition.Kind.SPEED_DAMAGE and wind.indirect_effect.unlock_level == 2, "indirect: Wind carries a SPEED_DAMAGE effect unlocking at level 2")

	# Frost: -8% cooldown per level. Base 1.875 at level 2 gives exactly 0.3 s shaved.
	var frost1 := _indirect_lane(player, {Stat.Type.COOLDOWN: 1.875}, 1, 0)
	check(is_equal_approx(frost1.get_final_stat_value(Stat.Type.COOLDOWN), 1.725) and is_equal_approx(frost1.get_indirect_damage_scale(), 1.0), "frost L1: the cooldown is shaved but there is no indirect bonus")
	player.run_ledger_component.log_slot_specific_purchase(frost, 1)
	check(is_equal_approx(frost1.get_final_stat_value(Stat.Type.COOLDOWN), 1.575) and is_equal_approx(frost1.get_indirect_damage_scale(), 1.12), "frost L2, 0.3 s shaved: +12%")
	fx.reset_player_state()

	# Frost floor: counts as 0.25 s when the effective cooldown is lower; never negative.
	var floored := _indirect_lane(player, {Stat.Type.COOLDOWN: 0.3}, 5, 0)
	check(is_equal_approx(floored.get_final_stat_value(Stat.Type.COOLDOWN), 0.18) and is_equal_approx(floored.get_indirect_damage_scale(), 1.0 + 0.05 / 0.1 * 0.04), "frost floor: a cooldown of 0.18 counts as 0.25, so 0.05 s shaved from 0.3 gives +2%")
	fx.reset_player_state()
	var below := _indirect_lane(player, {Stat.Type.COOLDOWN: 0.2}, 3, 0)
	check(is_equal_approx(below.get_indirect_damage_scale(), 1.0), "frost floor: a base cooldown under the floor gives no bonus, never a negative one")
	fx.reset_player_state()

	# Wind: 0.5 * SPEED_BONUS, level 2 and up. Wind adds +0.1 SPEED_BONUS per level.
	var wind1 := _indirect_lane(player, {Stat.Type.SPEED_BONUS: 0.1}, 0, 1)
	check(is_equal_approx(wind1.get_final_stat_value(Stat.Type.SPEED_BONUS), 0.2) and is_equal_approx(wind1.get_indirect_damage_scale(), 1.0), "wind L1: the speed bonus applies, the indirect does not")
	player.run_ledger_component.log_slot_specific_purchase(wind, 1)
	check(is_equal_approx(wind1.get_final_stat_value(Stat.Type.SPEED_BONUS), 0.3) and is_equal_approx(wind1.get_indirect_damage_scale(), 1.15), "wind L2 with SPEED_BONUS 0.3: +15%")
	fx.reset_player_state()
	var wind_tenth := _indirect_lane(player, {Stat.Type.SPEED_BONUS: -0.1}, 0, 2)
	check(is_equal_approx(wind_tenth.get_final_stat_value(Stat.Type.SPEED_BONUS), 0.1) and is_equal_approx(wind_tenth.get_indirect_damage_scale(), 1.05), "wind L2 with SPEED_BONUS 0.1: +5%")
	fx.reset_player_state()

	# Combined: summed, then clamped at +50%.
	var both := _indirect_lane(player, {Stat.Type.COOLDOWN: 1.875, Stat.Type.SPEED_BONUS: 0.0}, 2, 2)
	check(is_equal_approx(both.get_indirect_damage_scale(), 1.0 + 0.12 + 0.1), "frost + wind: bonuses are summed (0.12 + 0.1)")
	fx.reset_player_state()
	var capped := _indirect_lane(player, {Stat.Type.COOLDOWN: 1.875, Stat.Type.SPEED_BONUS: 1.0}, 2, 2)
	check(is_equal_approx(capped.get_indirect_damage_scale(), 1.5), "frost + wind: the total clamps at +50%% (raw 0.12 + 0.6)")
	fx.reset_player_state()

	# generate_hit_payload: hit scaled before the crit roll, DoT scaled before the crit share, nothing else scaled.
	var values: Dictionary = {
		Stat.Type.BASE_DAMAGE: 10.0, Stat.Type.CRIT_CHANCE: 0.0, Stat.Type.CRIT_MULTIPLIER: 2.0,
		Stat.Type.DOT_DAMAGE: 4.0, Stat.Type.STATUS_DURATION: 6.0, Stat.Type.STATUS_RAMP_CAP: 0.3,
		Stat.Type.COOLDOWN: 1.875, Stat.Type.SPEED_BONUS: -0.1, Stat.Type.CRIT_DOT_SHARE: 1.0, Stat.Type.AOE_RADIUS: 40.0,
	}
	var lane := _indirect_lane(player, values, 2, 2) # scale 1 + 0.12 + 0.05
	var scale := lane.get_indirect_damage_scale()
	var plain_lane := _make_stats(values)
	check(is_equal_approx(scale, 1.17) and is_equal_approx(plain_lane.get_indirect_damage_scale(), 1.0), "payload: lane scale 1.17; a lane with no ledger 1.0")
	var plain := CombatCalculations.generate_hit_payload(null, plain_lane, null)
	var scaled := CombatCalculations.generate_hit_payload(null, lane, null)
	check(is_equal_approx(plain.damage_scale, 1.0) and is_equal_approx(plain.final_damage, 10.0) and is_equal_approx(plain.dot_damage_snapshot, 4.0), "payload: no indirect cards leave scale 1.0, damage 10 and DoT 4")
	check(is_equal_approx(scaled.damage_scale, 1.17) and is_equal_approx(scaled.final_damage, 11.7) and is_equal_approx(scaled.dot_damage_snapshot, 4.68), "payload: damage 10 * 1.17 and DoT 4 * 1.17, no crit")
	check(is_equal_approx(scaled.status_duration_snapshot, plain.status_duration_snapshot) and is_equal_approx(scaled.status_ramp_cap_snapshot, plain.status_ramp_cap_snapshot), "payload: duration and ramp cap snapshots are not scaled")
	values[Stat.Type.CRIT_CHANCE] = 1.0
	values[Stat.Type.CRIT_MULTIPLIER] = 1.5
	var crit_lane := _indirect_lane(player, values, 0, 0)
	var crit := CombatCalculations.resolve_hit_crit(CombatCalculations.generate_hit_payload(null, crit_lane, null))
	check(crit.is_critical_hit and is_equal_approx(crit.final_damage, 10.0 * 1.17 * 1.5), "payload crit: hit = base * scale * crit multiplier (17.55)")
	check(is_equal_approx(crit.dot_damage_snapshot, 4.0 * 1.17 * (1.0 + 0.5 * 1.0)), "payload crit: DoT = base * scale, then the crit share (7.02)")
	fx.reset_player_state()

	# Burst copies and zone hits carry the cast's scale and are not scaled again.
	player = fx.fresh_player()
	var fire := load(FIRE_CARD) as UpgradeDefinition
	values[Stat.Type.CRIT_CHANCE] = 0.0
	var cast_lane := _indirect_lane(player, values, 2, 2)
	player.run_ledger_component.log_slot_specific_purchase(fire, 1)
	player.run_ledger_component.log_slot_specific_purchase(load(SHATTER_EVOLVE_CARD) as UpgradeDefinition, 1) # Chill now comes from the Shatter card (Task AO)
	var cast := CombatCalculations.generate_hit_payload(null, cast_lane, null)
	check(cast.status_effects_to_apply.size() == 2 and is_equal_approx(cast.damage_scale, 1.17), "burst/zone setup: the cast carries Chill, Burn and scale 1.17")
	var burst_def := _make_burst(&"test_indirect_burst", ImpactBurstDefinition.Trigger.ON_HIT, 0.5)
	var origin := Vector2(87000.0, 87000.0)
	var bats := await _spawn_burst_bats(origin, [Vector2.ZERO, Vector2(20, 0)])
	var bat_id: int = bats[0].get_instance_id()
	ImpactBurst.run(burst_def, cast, origin, bat_id, tree.root.get_world_2d())
	var burst_seen: CombatPayload = _recorded[1][0] if not _recorded[1].is_empty() else null
	check(burst_seen != null and is_equal_approx(burst_seen.final_damage, cast.final_damage * 0.5) and is_equal_approx(burst_seen.damage_scale, 1.17), "burst copy: damage is the cast's scaled hit * fraction, not scaled again")
	check(burst_seen != null and is_equal_approx(cast.final_damage, 11.7) and is_equal_approx(cast.dot_damage_snapshot, 4.68), "burst copy: the cast's own payload is untouched")
	_free_bats(bats)

	LingeringZone.reset_registry()
	var zone_def := _zone_burst(&"test_indirect_zone", load(TEST_LINGERING_ZONE) as PackedScene)
	cast.impact_bursts = [zone_def]
	var zone_bats := await _spawn_burst_bats(origin + Vector2(500, 0), [Vector2.ZERO])
	var zone := await _spawn_zone(zone_def, cast, origin + Vector2(500, 0))
	# The zone re-applies every 0.5 s; wait (bounded) for its first hit instead of a fixed frame count.
	for i in range(240):
		if not _recorded[0].is_empty():
			break
		await tree.physics_frame
	var zone_hits: Array = _recorded[0]
	check(zone != null and not zone_hits.is_empty(), "zone: the zone hit the bat inside it")
	if not zone_hits.is_empty():
		var zone_hit: CombatPayload = zone_hits[0]
		check(is_equal_approx(zone_hit.final_damage, 0.0) and is_equal_approx(zone_hit.dot_damage_snapshot, 4.68) and is_equal_approx(zone_hit.damage_scale, 1.17), "zone: 0 hit damage, the cast's scaled DoT snapshot (4.68), scale unchanged")
	_free_bats(zone_bats)
	LingeringZone.reset_registry()

	# Direct effects are never gated: Chill at level 1 and Frost's cooldown cut.
	player = fx.fresh_player()
	var direct := _indirect_lane(player, {Stat.Type.COOLDOWN: 1.0, Stat.Type.BASE_DAMAGE: 10.0, Stat.Type.DOT_DAMAGE: 1.0}, 1, 0)
	var level1 := CombatCalculations.generate_hit_payload(null, direct, null)
	check(is_equal_approx(direct.get_final_stat_value(Stat.Type.COOLDOWN), 0.92) and level1.status_effects_to_apply.is_empty() and is_equal_approx(level1.final_damage, 10.0), "direct effects: Frost L1 still cuts the cooldown, with scale 1.0, and carries no status (Task AO)")
	player.run_ledger_component.log_slot_specific_purchase(load(SHATTER_EVOLVE_CARD) as UpgradeDefinition, 1)
	var level1_shatter := CombatCalculations.generate_hit_payload(null, direct, null)
	check(level1_shatter.status_effects_to_apply.size() == 1 and level1_shatter.status_effects_to_apply[0].effect_id == &"chill" and is_equal_approx(level1_shatter.damage_scale, 1.0), "direct effects: with the Shatter card, Chill applies at Frost L1, scale 1.0")
	fx.reset_player_state()


## Task AU: Lightning (CRIT_CHANCE) and Earth (REACH_BONUS) are stat-conversion indirect effects at level 3.
func _section_lightning_earth_indirect() -> void:
	var lightning := load(LIGHTNING_CARD) as UpgradeDefinition
	var earth := load(EARTH_CARD) as UpgradeDefinition
	var fire := load(FIRE_CARD) as UpgradeDefinition
	var lightning_effect := lightning.indirect_effect
	var earth_effect := earth.indirect_effect

	# a. The shipped definitions.
	check(lightning_effect != null and lightning_effect.kind == IndirectEffectDefinition.Kind.CRIT_DAMAGE and lightning_effect.unlock_level == 3 and is_equal_approx(lightning_effect.crit_ratio, 1.0), "lightning/earth indirect: Lightning carries CRIT_DAMAGE, unlock 3, crit_ratio 1.0")
	check(earth_effect != null and earth_effect.kind == IndirectEffectDefinition.Kind.REACH_DAMAGE and earth_effect.unlock_level == 3 and is_equal_approx(earth_effect.reach_ratio, 0.5), "lightning/earth indirect: Earth carries REACH_DAMAGE, unlock 3, reach_ratio 0.5")
	check(int(IndirectEffectDefinition.Kind.CRIT_DAMAGE) == 3 and int(IndirectEffectDefinition.Kind.REACH_DAMAGE) == 4 and int(IndirectEffectDefinition.Kind.SPEED_DAMAGE) == 2, "lightning/earth indirect: Kind is append-only (SPEED_DAMAGE 2, CRIT_DAMAGE 3, REACH_DAMAGE 4)")

	# b. Lightning: nothing at level 2, crit_ratio * CRIT_CHANCE at level 3 (CRIT_CHANCE 0.2 + 0.03 per level).
	var player := fx.fresh_player()
	var values := {Stat.Type.BASE_DAMAGE: 10.0, Stat.Type.DOT_DAMAGE: 4.0, Stat.Type.CRIT_CHANCE: 0.2, Stat.Type.CRIT_MULTIPLIER: 2.0, Stat.Type.REACH_BONUS: 0.0}
	var lane := _make_stats(values, 1, player.run_ledger_component)
	_grant(player, LIGHTNING_CARD, 1, 2)
	check(is_equal_approx(lane.get_final_stat_value(Stat.Type.CRIT_CHANCE), 0.26) and is_equal_approx(lane.get_indirect_damage_scale(), 1.0), "lightning/earth indirect: Lightning 2 raises CRIT_CHANCE but adds no scale")
	_grant(player, LIGHTNING_CARD, 1, 1)
	check(is_equal_approx(lane.get_indirect_damage_scale(), 1.0 + 0.29), "lightning/earth indirect: Lightning 3 adds crit_ratio * CRIT_CHANCE (0.29)")
	fx.reset_player_state()

	# c. Earth: nothing at level 2, reach_ratio * REACH_BONUS at level 3 (REACH_BONUS 0.1 per level).
	player = fx.fresh_player()
	lane = _make_stats(values, 1, player.run_ledger_component)
	_grant(player, EARTH_CARD, 1, 2)
	check(is_equal_approx(lane.get_final_stat_value(Stat.Type.REACH_BONUS), 0.2) and is_equal_approx(lane.get_indirect_damage_scale(), 1.0), "lightning/earth indirect: Earth 2 raises REACH_BONUS but adds no scale")
	_grant(player, EARTH_CARD, 1, 1)
	check(is_equal_approx(lane.get_indirect_damage_scale(), 1.0 + 0.5 * 0.3), "lightning/earth indirect: Earth 3 adds reach_ratio * REACH_BONUS (0.15)")
	fx.reset_player_state()

	# d. Both on one slot sum: CRIT_CHANCE 0.05 + 0.09 = 0.14, REACH_BONUS 0.3 * 0.5 = 0.15.
	player = fx.fresh_player()
	values[Stat.Type.CRIT_CHANCE] = 0.05
	lane = _make_stats(values, 1, player.run_ledger_component)
	_grant(player, LIGHTNING_CARD, 1, 3)
	_grant(player, EARTH_CARD, 1, 3)
	check(is_equal_approx(lane.get_indirect_damage_scale(), 1.0 + 0.14 + 0.15), "lightning/earth indirect: Lightning 3 + Earth 3 on one slot sum (0.14 + 0.15)")

	# e. The scale multiplies the pre-crit hit and the DoT snapshot, and nothing else.
	var cast := CombatCalculations.generate_hit_payload(null, lane, null)
	check(is_equal_approx(cast.damage_scale, 1.29) and is_equal_approx(cast.final_damage, 12.9) and is_equal_approx(cast.dot_damage_snapshot, 4.0 * 1.29), "lightning/earth indirect: the cast scales BOTH final_damage (pre-crit, 12.9) and dot_damage_snapshot (5.16)")
	fx.reset_player_state()

	# f. The sum clamps at +50%: a synthetic effect with a huge ratio proves it.
	player = fx.fresh_player()
	var huge := IndirectEffectDefinition.new()
	huge.kind = IndirectEffectDefinition.Kind.CRIT_DAMAGE
	huge.unlock_level = 1
	huge.crit_ratio = 100.0
	var huge_card := UpgradeDefinition.new()
	huge_card.upgrade_id = "test_huge_crit_ratio"
	huge_card.indirect_effect = huge
	lane = _make_stats(values, 1, player.run_ledger_component)
	_grant_card(player, huge_card, 1, 1)
	check(IndirectScaling.bonus_of(huge, lane) > IndirectScaling.TOTAL_BONUS_CAP and is_equal_approx(lane.get_indirect_damage_scale(), 1.5), "lightning/earth indirect: a raw bonus of 5.0 clamps to scale 1.5")
	fx.reset_player_state()

	# g. A Lightning-only slot gets no status (so no DoT); the DoT snapshot is inert until a ticking status is carried.
	player = fx.fresh_player()
	lane = _make_stats(values, 1, player.run_ledger_component)
	_grant(player, LIGHTNING_CARD, 1, 3)
	var lightning_cast := CombatCalculations.generate_hit_payload(null, lane, null)
	check(lightning_cast.status_effects_to_apply.is_empty() and lightning_cast.dot_damage_snapshot > 0.0, "lightning/earth indirect: a Lightning-only slot carries no status, its scaled DoT snapshot is inert")
	_grant(player, FIRE_CARD, 1, 1)
	var fire_cast := CombatCalculations.generate_hit_payload(null, lane, null)
	check(fire_cast.status_effects_to_apply.size() == 1 and fire_cast.status_effects_to_apply[0].effect_id == &"burn" and is_equal_approx(fire_cast.dot_damage_snapshot, 4.0 * fire_cast.damage_scale), "lightning/earth indirect: with Fire the scaled DoT snapshot feeds Burn")
	fx.reset_player_state()

	# h. A crit multiplies after the scale, per hit: CRIT_CHANCE 1.0, Earth 3 (scale 1.15), multiplier 2.
	player = fx.fresh_player()
	values[Stat.Type.CRIT_CHANCE] = 1.0
	lane = _make_stats(values, 1, player.run_ledger_component)
	_grant(player, EARTH_CARD, 1, 3)
	var crit_cast := CombatCalculations.generate_hit_payload(null, lane, null)
	var crit_hit := CombatCalculations.resolve_hit_crit(crit_cast)
	check(not crit_cast.is_critical_hit and is_equal_approx(crit_cast.final_damage, 11.5) and crit_hit.is_critical_hit and is_equal_approx(crit_hit.final_damage, 11.5 * 2.0), "lightning/earth indirect: the crit multiplies the scaled hit (10 * 1.15 * 2 = 23), the shared cast payload stays pre-crit")
	fx.reset_player_state()

	# i. Higher levels and Overclock keep the effect.
	player = fx.fresh_player()
	values[Stat.Type.CRIT_CHANCE] = 0.05
	lane = _make_stats(values, 1, player.run_ledger_component)
	_grant(player, LIGHTNING_CARD, 1, 4)
	_grant(player, EARTH_CARD, 1, 4)
	player.run_ledger_component.log_slot_specific_purchase(load(DBG_OVERCLOCK_CARD) as UpgradeDefinition, 1)
	check(player.run_ledger_component.is_overclocked(1) and is_equal_approx(lane.get_indirect_damage_scale(), 1.0 + 0.17 + 0.5 * 0.4), "lightning/earth indirect: Overclocked at level 4 the effect stays active (0.17 + 0.20)")
	fx.reset_player_state()

	# j. Neither card produces impact bursts on any slot at any level.
	player = fx.fresh_player()
	lane = _make_stats(values, 1, player.run_ledger_component)
	var other := _make_stats(values, 2, player.run_ledger_component)
	var no_bursts := true
	for level in range(5):
		_grant(player, LIGHTNING_CARD, 1, 1)
		_grant(player, EARTH_CARD, 1, 1)
		_grant(player, LIGHTNING_CARD, 2, 1)
		no_bursts = no_bursts and lane.get_impact_bursts().is_empty() and other.get_impact_bursts().is_empty() and CombatCalculations.generate_hit_payload(null, lane, null).impact_bursts.is_empty()
	check(no_bursts and lightning.impact_burst_payload == null and earth.impact_burst_payload == null, "lightning/earth indirect: the Lightning and Earth cards produce no impact bursts at levels 1 to 5")
	fx.reset_player_state()


## Task AO: Fire is the only base infusion that applies a status; Chill comes from the two Shatter cards.
func _section_status_sources() -> void:
	var fire := load(FIRE_CARD) as UpgradeDefinition
	var frost := load(FROST_CARD) as UpgradeDefinition
	var earth := load(EARTH_CARD) as UpgradeDefinition
	var shatter_evolve := load(SHATTER_EVOLVE_CARD) as UpgradeDefinition
	var shatter_overclock := load(SHATTER_OVERCLOCK_CARD) as UpgradeDefinition
	var magma_evolve := load(MAGMA_EVOLVE_CARD) as UpgradeDefinition
	var burn := load("res://resources/status_effects/burn.tres") as StatusEffect
	var chill := load("res://resources/status_effects/chill.tres") as StatusEffect

	# a. Frost alone applies nothing.
	var player := _socket_pair(frost, frost, 3)
	var tags: Array[Tags.Type] = player.ability_container.get_ability_by_slot(1).tag_component.get_permanent_tags()
	var statuses := player.run_ledger_component.get_status_effects(1, tags)
	check(statuses.is_empty() and frost.status_effect_payload == null, "status sources: Frost level 3 alone resolves no status (no Chill)")

	# b. Fire alone is exactly Burn.
	player = _socket_pair(fire, fire, 3)
	tags = player.ability_container.get_ability_by_slot(1).tag_component.get_permanent_tags()
	statuses = player.run_ledger_component.get_status_effects(1, tags)
	check(statuses.size() == 1 and statuses[0] == burn, "status sources: Fire level 3 alone resolves exactly [Burn]")

	# c. Frost 3 + Earth 3 with each Shatter card: exactly Chill, slot 1 only.
	for card in [shatter_evolve, shatter_overclock]:
		player = _socket_pair(frost, earth, 3)
		tags = player.ability_container.get_ability_by_slot(1).tag_component.get_permanent_tags()
		check(player.run_ledger_component.get_status_effects(1, tags).is_empty(), "status sources: Frost 3 + Earth 3 before the card resolves no status (%s)" % card.upgrade_id)
		player.run_ledger_component.log_slot_specific_purchase(card, 1)
		statuses = player.run_ledger_component.get_status_effects(1, tags)
		check(statuses.size() == 1 and statuses[0] == chill, "status sources: Frost 3 + Earth 3 with %s resolves exactly [Chill]" % card.upgrade_id)
		check(player.run_ledger_component.get_status_effects(2, tags).is_empty(), "status sources: the %s purchase on slot 1 puts no Chill on slot 2" % card.upgrade_id)

	# d. Fire 3 + Earth 3 with Magma: Burn only; Magma carries no status.
	player = _socket_pair(fire, earth, 3)
	tags = player.ability_container.get_ability_by_slot(1).tag_component.get_permanent_tags()
	player.run_ledger_component.log_slot_specific_purchase(magma_evolve, 1)
	statuses = player.run_ledger_component.get_status_effects(1, tags)
	check(statuses.size() == 1 and statuses[0] == burn and magma_evolve.status_effect_payload == null, "status sources: Fire 3 + Earth 3 with Magma resolves exactly [Burn]")

	# e. Fire 3 + Frost 3 with no compound card: Burn only.
	player = _socket_pair(fire, frost, 3)
	tags = player.ability_container.get_ability_by_slot(1).tag_component.get_permanent_tags()
	statuses = player.run_ledger_component.get_status_effects(1, tags)
	check(statuses.size() == 1 and statuses[0] == burn, "status sources: Fire 3 + Frost 3 with no compound card resolves exactly [Burn]")

	# f. The shatter burst still carries Chill.
	var shatter := load(SHATTER_BURST) as ImpactBurstDefinition
	var both: Array[StatusEffect] = [burn, chill]
	var carried := ImpactBurst.carried_statuses(shatter, both)
	check(carried.size() == 1 and carried[0] == chill, "status sources: the shatter burst carries Chill (and not Burn) from a cast status list")
	fx.reset_player_state()


# Task AE: burst level gating helpers.
func _burst_lane(player: Player, slot: int, extra: Dictionary = {}) -> StatsContainer:
	var values := {Stat.Type.AOE_RADIUS: 10.0, Stat.Type.BASE_DAMAGE: 10.0, Stat.Type.CRIT_CHANCE: 0.0, Stat.Type.CRIT_MULTIPLIER: 2.0, Stat.Type.REACH_BONUS: 0.0, Stat.Type.DOT_DAMAGE: 1.0}
	values.merge(extra, true)
	return _make_stats(values, slot, player.run_ledger_component)


func _grant(player: Player, card_path: String, slot: int, levels: int) -> void:
	for i in range(levels):
		player.run_ledger_component.log_slot_specific_purchase(load(card_path) as UpgradeDefinition, slot)


func _burst_ids_of(payload: CombatPayload) -> Array[String]:
	var ids: Array[String] = []
	for burst in payload.impact_bursts:
		ids.append(String(burst.burst_id))
	return ids


## Task AU: the shipped Earth explosion and Lightning overload were removed, so the burst mechanism is exercised with
## bursts built in code (same numbers as the old ones) and granted through test cards. The real Earth and Lightning
## cards are checked to keep their direct stats and to carry no burst.
func _burst_test_card(id: String, burst: ImpactBurstDefinition) -> UpgradeDefinition:
	var card := UpgradeDefinition.new()
	card.upgrade_id = id
	card.scope = UpgradeDefinition.ScopeType.LOCAL_SLOT
	card.impact_burst_payload = burst
	return card


func _grant_card(player: Player, card: UpgradeDefinition, slot: int, levels: int) -> void:
	for i in range(levels):
		player.run_ledger_component.log_slot_specific_purchase(card, slot)


func _section_burst_gating_synthetic() -> void:
	var player := fx.fresh_player()
	var explosion := _make_burst(&"test_explosion", ImpactBurstDefinition.Trigger.ON_HIT, 0.4, 0.0, 0.0, 6.0)
	explosion.max_per_cast = 3
	explosion.unlock_level = 3
	var overload := _make_burst(&"test_overload", ImpactBurstDefinition.Trigger.ON_CRIT, 0.6, 0.0, 0.0, 8.0)
	overload.max_per_cast = 1
	overload.unlock_level = 3
	var explosion_card := _burst_test_card("test_explosion_card", explosion)
	var overload_card := _burst_test_card("test_overload_card", overload)
	check(ImpactBurstDefinition.new().unlock_level == 1 and IndirectScaling.is_unlocked(3, 3) and not IndirectScaling.is_unlocked(2, 3), "bursts AE: unlock_level defaults to 1; the shared gate is level >= unlock")

	# Real cards: direct stats stay, no burst on any level.
	var real_earth := load(EARTH_CARD) as UpgradeDefinition
	var real_lightning := load(LIGHTNING_CARD) as UpgradeDefinition
	check(real_earth.impact_burst_payload == null and real_lightning.impact_burst_payload == null, "bursts AE: the real Earth and Lightning cards carry no burst (Task AU)")
	var real_lane := _burst_lane(player, 4, {Stat.Type.CRIT_CHANCE: 1.0})
	_grant(player, EARTH_CARD, 4, 2)
	check(is_equal_approx(real_lane.get_final_stat_value(Stat.Type.REACH_BONUS), 0.2), "bursts AE: Earth 2 still gives its direct REACH_BONUS 0.2")
	_grant(player, LIGHTNING_CARD, 4, 3)
	check(is_equal_approx(real_lane.get_final_stat_value(Stat.Type.CRIT_CHANCE), 1.09) and CombatCalculations.generate_hit_payload(world as Node2D, real_lane, null).impact_bursts.is_empty(), "bursts AE: Lightning 3 gives its direct crit chance and no overload")

	# Gating by level, per slot. REACH_BONUS 0.3 stands in for Earth 3's direct bonus.
	var earth_lane := _burst_lane(player, 1, {Stat.Type.REACH_BONUS: 0.3})
	var other_lane := _burst_lane(player, 2, {Stat.Type.REACH_BONUS: 0.3})
	_grant_card(player, explosion_card, 1, 2)
	check(_burst_ids_of(CombatCalculations.generate_hit_payload(world as Node2D, earth_lane, null)).is_empty(), "bursts AE: an unlock_level 3 ON_HIT burst card at level 2 gives no explosion")
	_grant_card(player, explosion_card, 1, 1)
	check(_burst_ids_of(CombatCalculations.generate_hit_payload(world as Node2D, earth_lane, null)) == ["test_explosion"], "bursts AE: at level 3 the burst card gives the explosion")
	check(_burst_ids_of(CombatCalculations.generate_hit_payload(world as Node2D, other_lane, null)).is_empty(), "bursts AE: level 3 in slot 1 gives slot 2 no burst")
	var light_lane := _burst_lane(player, 3, {Stat.Type.CRIT_CHANCE: 1.0})
	_grant_card(player, overload_card, 3, 1)
	check(CombatCalculations.generate_hit_payload(world as Node2D, light_lane, null).impact_bursts.is_empty(), "bursts AE: an unlock_level 3 ON_CRIT burst card at level 1 gives no overload")
	_grant_card(player, overload_card, 3, 1)
	check(_burst_ids_of(CombatCalculations.generate_hit_payload(world as Node2D, light_lane, null)).is_empty(), "bursts AE: at level 2 it gives no overload")
	_grant_card(player, overload_card, 3, 1)
	var crit_cast := CombatCalculations.generate_hit_payload(world as Node2D, light_lane, null)
	check(_burst_ids_of(crit_cast) == ["test_overload"], "bursts AE: at level 3 it gives the overload")

	# Explosion: fires on a hit, scaled radius 10 * 1.3 * 6 = 78 (reach 88 with the hurtbox), damage 0.4 of the hit, cap 3 per cast.
	var origin := Vector2(130000.0, 130000.0)
	var cast := CombatCalculations.generate_hit_payload(world as Node2D, earth_lane, null)
	var bats := await _spawn_burst_bats(origin, [Vector2(0, 0), Vector2(60, 0), Vector2(85, 0), Vector2(100, 0)])
	bats[0].hurtbox_component.take_hit(cast)
	await tree.process_frame
	await tree.process_frame
	check(is_equal_approx(_lost(bats[1]), 4.0), "bursts AE: the explosion deals 0.4 of the 10 damage hit (4.0)")
	check(is_equal_approx(_lost(bats[2]), 4.0) and is_equal_approx(_lost(bats[3]), 0.0), "bursts AE: radius 10 * (1 + 0.3) * 6: a bat at 85 is caught (without reach it would not be), one at 100 is not")
	check(is_equal_approx(_lost(bats[0]), 10.0), "bursts AE: the primary target takes only the hit")
	check(_recorded[1].size() == 1 and _recorded[1][0].is_burst and _recorded[1][0].impact_bursts.is_empty() and not _recorded[1][0].is_critical_hit, "bursts AE: the burst copy is marked is_burst, holds no bursts and never crits (no recursion)")
	_free_bats(bats)
	var five := CombatCalculations.generate_hit_payload(world as Node2D, earth_lane, null)
	check(await _burst_hits_on_neighbor(five, 131000.0, 5) == 3, "bursts AE: five hits from one cast spawn 3 explosions")

	# Overload: crit only, once per cast, 0.6 of the crit's final damage (the multiplier is included).
	var expected := 10.0 * light_lane.get_final_stat_value(Stat.Type.CRIT_MULTIPLIER)
	var crit_resolved := CombatCalculations.resolve_hit_crit(crit_cast)
	check(crit_resolved.is_critical_hit and is_equal_approx(crit_resolved.final_damage, expected) and expected > 10.0 and not crit_cast.is_critical_hit, "bursts AE: the crit hit's final damage includes the multiplier")
	check(await _burst_hits_on_neighbor(crit_cast, 132000.0, 4) == 1, "bursts AE: four crit hits from one cast spawn one overload")
	bats = await _spawn_burst_bats(Vector2(130000.0, 133000.0), [Vector2(0, 0), Vector2(30, 0)])
	var crit_fresh := CombatCalculations.generate_hit_payload(world as Node2D, light_lane, null)
	bats[0].hurtbox_component.take_hit(crit_fresh)
	await tree.process_frame
	await tree.process_frame
	check(is_equal_approx(_lost(bats[1]), 0.6 * expected), "bursts AE: the overload deals 0.6 of the crit's final damage")
	_free_bats(bats)
	var plain_cast := CombatCalculations.generate_hit_payload(world as Node2D, light_lane, null)
	plain_cast.crit_chance_snapshot = 0.0
	check(await _burst_hits_on_neighbor(plain_cast, 134000.0, 3) == 0, "bursts AE: a non-crit hit never fires the overload")
	fx.reset_player_state()

	# Overload radius at reach 0: 10 * 8 = 80 (reach 90): a bat at 85 is caught, one at 100 is not.
	var wide_player := fx.fresh_player()
	var wide_lane := _burst_lane(wide_player, 1, {Stat.Type.CRIT_CHANCE: 1.0})
	_grant_card(wide_player, overload_card, 1, 3)
	var wide_cast := CombatCalculations.generate_hit_payload(world as Node2D, wide_lane, null)
	bats = await _spawn_burst_bats(Vector2(130000.0, 135000.0), [Vector2(0, 0), Vector2(85, 0), Vector2(100, 0)])
	bats[0].hurtbox_component.take_hit(wide_cast)
	await tree.process_frame
	await tree.process_frame
	check(_lost(bats[1]) > 0.0 and is_equal_approx(_lost(bats[2]), 0.0), "bursts AE: overload radius 10 * 8 = 80 catches a bat at 85, not one at 100")
	_free_bats(bats)
	fx.reset_player_state()

	# Guard: every ability profile, and every evolved profile, keeps AOE_RADIUS (key 9) above 0 so a burst has reach.
	var profiles := 0
	var bad: Array[String] = []
	for path in _list_tres("res://resources/abilities"):
		var resource := load(path)
		var data := resource as AbilityData
		if resource is UpgradeDefinition:
			data = (resource as UpgradeDefinition).ability_data_payload
		if data == null or data.stats_profile == null:
			continue
		profiles += 1
		if float(data.stats_profile.base_stats.get(Stat.Type.AOE_RADIUS, 0.0)) <= 0.0:
			bad.append(path)
	check(profiles >= 2 and bad.is_empty(), "profile guard: every ability and evolved profile has AOE_RADIUS > 0 (%d profiles, missing: %s)" % [profiles, str(bad)])


# Task AD: a burst's size comes from the caster's AOE_RADIUS and REACH_BONUS. This section pins current behavior.
func _section_burst_stat_inheritance() -> void:
	# Hurtbox circles have radius 10, so a circle of radius R catches a bat whose centre is within R + 10.
	var space_state := (world as Node2D).get_world_2d().direct_space_state
	var origin := Vector2(120000.0, 120000.0)
	var shape := CircleBurstShape.new()
	var bats := await _spawn_burst_bats(origin, [Vector2(33, 0), Vector2(15, 0)])

	# a. reach 0: radius = AOE_RADIUS * radius_multiplier. AOE 20 reaches 30: the bat at 15 is caught, the one at 33 is not.
	var plain := _make_stats({Stat.Type.AOE_RADIUS: 20.0, Stat.Type.REACH_BONUS: 0.0})
	var plain_hits := shape.find_targets(origin, plain, space_state, 0)
	check(plain_hits.size() == 1 and plain_hits[0] == bats[1].hurtbox_component, "burst stats: reach 0 gives radius 20 (catches the bat at 15, not the one at 33)")
	var doubled := CircleBurstShape.new()
	doubled.radius_multiplier = 2.0
	check(doubled.find_targets(origin, plain, space_state, 0).size() == 2, "burst stats: radius_multiplier 2 gives radius 40 (catches both)")

	# b. REACH_BONUS 0.3: radius 26, reaches 36. The bat at 33 is between the old edge (30) and the new one (36).
	var reach := _make_stats({Stat.Type.AOE_RADIUS: 20.0, Stat.Type.REACH_BONUS: 0.3})
	check(shape.find_targets(origin, reach, space_state, 0).size() == 2, "burst stats: REACH_BONUS 0.3 (radius x1.3) catches the bat at 33")
	check(shape.find_targets(origin, plain, space_state, 0).size() == 1, "burst stats: the same bat is missed with REACH_BONUS 0.0")

	# c. A changed AOE_RADIUS scales the burst.
	var wide := _make_stats({Stat.Type.AOE_RADIUS: 40.0})
	check(shape.find_targets(origin, wide, space_state, 0).size() == 2, "burst stats: AOE_RADIUS 20 -> 40 catches the bat at 33")

	# d. The shared shape resource is not mutated by scaling.
	check(is_equal_approx(shape.radius_multiplier, 1.0) and is_equal_approx(doubled.radius_multiplier, 2.0), "burst stats: scaling never changes the shape's radius_multiplier")

	# e. Characterization (current behavior, not a requirement): the stats are read when the burst fires, not at cast time.
	var definition := _make_burst(&"test_ad_live", ImpactBurstDefinition.Trigger.ON_HIT)
	var live := _make_stats({Stat.Type.AOE_RADIUS: 20.0, Stat.Type.REACH_BONUS: 0.0})
	var cast := _burst_payload(live, 10.0, [definition])
	var bigger := StatsProfile.new()
	var bigger_stats: Dictionary[Stat.Type, float] = {Stat.Type.AOE_RADIUS: 20.0, Stat.Type.REACH_BONUS: 0.3}
	bigger.base_stats = bigger_stats
	live.mutate_base_profile(bigger)
	ImpactBurst.run(definition, cast, origin + Vector2(0, -500), 0, tree.root.get_world_2d())
	var fired := _lost(bats[0])
	# The burst above was centered away from the bats; fire one at the bats' origin instead.
	ImpactBurst.run(definition, cast, origin, 0, tree.root.get_world_2d())
	check(is_equal_approx(fired, 0.0) and is_equal_approx(_lost(bats[0]), 5.0), "burst stats (current behavior): a REACH_BONUS change between cast and fire changes the radius (bat at 33 is hit, 0.5 of 10 = 5)")

	# f. Caster freed or invalid when the burst fires: no reach, no error (instance_from_id gives null).
	var doomed := _make_stats({Stat.Type.AOE_RADIUS: 20.0})
	var orphan := _burst_payload(doomed, 10.0, [definition])
	doomed.free()
	var before := _lost(bats[1])
	ImpactBurst.run(definition, orphan, origin, 0, tree.root.get_world_2d())
	check(is_equal_approx(_lost(bats[1]), before), "burst stats (current behavior): a freed caster StatsContainer gives the burst no reach and no error")
	_free_bats(bats)

	# g. The 32-result cap still holds with a scaled burst: 40 bats inside it, at most 32 targets.
	var crowd_offsets: Array[Vector2] = []
	for i in range(40):
		crowd_offsets.append(Vector2(float(i % 8) * 3.0, float(i / 8) * 3.0))
	var crowd_origin := Vector2(120000.0, 121000.0)
	var crowd := await _spawn_burst_bats(crowd_origin, crowd_offsets)
	var crowd_hits := shape.find_targets(crowd_origin, reach, space_state, 0)
	check(crowd_hits.size() == CombatPhysics.MAX_QUERY_RESULTS, "burst stats: a scaled burst over 40 enemies returns exactly %d targets" % CombatPhysics.MAX_QUERY_RESULTS)
	_free_bats(crowd)

	# h. Lingering zone: radius = AOE_RADIUS * (1 + REACH_BONUS) * its multiplier (test zone multiplier 4).
	LingeringZone.reset_registry()
	var zone_def := _zone_burst(&"test_ad_zone", load(TEST_LINGERING_ZONE) as PackedScene)
	var no_statuses: Array[StatusEffect] = []
	var zone_plain := await _spawn_zone(zone_def, _zone_payload(_make_stats({Stat.Type.AOE_RADIUS: 10.0}), zone_def, no_statuses), Vector2(120000.0, 122000.0))
	check(zone_plain != null and is_equal_approx(zone_plain._radius, 40.0), "burst stats: lingering zone at reach 0 has radius 10 * 4 = 40")
	if zone_plain != null:
		zone_plain.queue_free()
	LingeringZone.reset_registry()
	var zone_reach := await _spawn_zone(zone_def, _zone_payload(_make_stats({Stat.Type.AOE_RADIUS: 10.0, Stat.Type.REACH_BONUS: 0.3}), zone_def, no_statuses), Vector2(120000.0, 123000.0))
	check(zone_reach != null and is_equal_approx(zone_reach._radius, 52.0), "burst stats: lingering zone at REACH_BONUS 0.3 has radius 10 * 1.3 * 4 = 52")
	if zone_reach != null:
		zone_reach.queue_free()
	LingeringZone.reset_registry()


func _section_health_bar() -> void:
	# a. Ratio math, visibility and colour on a bare bar.
	var bar := HealthBarComponent.new()
	fx.track(bar)
	bar.set_health(5.0, 10.0)
	check(is_equal_approx(bar.get_ratio(), 0.5), "health bar: 5/10 gives ratio 0.5")
	bar.set_health(5.0, 0.0)
	check(bar.get_ratio() == 0.0, "health bar: max 0 gives ratio 0")
	bar.set_health(5.0, -3.0)
	check(bar.get_ratio() == 0.0, "health bar: negative max gives ratio 0")
	bar.set_health(15.0, 10.0)
	check(bar.get_ratio() == 1.0, "health bar: over max clamps to 1")
	bar.set_health(10.0, 10.0)
	check(not bar.visible, "health bar: hidden at full health")
	bar.set_health(5.0, 10.0)
	check(bar.visible, "health bar: visible at 0.5")
	bar.set_health(0.0, 10.0)
	check(not bar.visible, "health bar: hidden at 0")
	bar.show_when_full = true
	bar.set_health(10.0, 10.0)
	check(bar.visible, "health bar: show_when_full shows the bar at full health")
	bar.set_health(0.0, 10.0)
	check(not bar.visible, "health bar: show_when_full still hides the bar at 0")
	bar.show_when_full = false
	bar.set_health(3.0, 10.0)
	check(bar.is_low() and bar.get_fill_color() == bar.low_health_color, "health bar: ratio at the threshold (0.3) uses the low colour")
	bar.set_health(4.0, 10.0)
	check(not bar.is_low() and bar.get_fill_color() == bar.fill_color, "health bar: ratio above the threshold uses the normal colour")

	# b. An instanced enemy, wired by the entity.
	var bat := fx.spawn_bat()
	await _wait_physics_frames(2)
	var health_bar := bat.health_bar_component
	check(health_bar != null and not health_bar.visible, "health bar: a fresh enemy has a bar and it is hidden")
	bat.health_component.take_damage(bat.health_component.max_health * 0.5)
	check(health_bar.visible and is_equal_approx(health_bar.get_ratio(), 0.5), "health bar: damaging the enemy shows the bar at the right ratio")
	bat.health_component.heal(bat.health_component.max_health)
	check(not health_bar.visible, "health bar: healing back to full hides the bar")
	bat.health_component.update_max_health(bat.health_component.max_health * 2.0)
	check(health_bar.visible and is_equal_approx(health_bar.get_ratio(), 0.5), "health bar: a max health change reaches the bar")
	bat.health_component.take_damage(bat.health_component.max_health * 0.5)
	var dying_bar := health_bar
	bat.health_component.take_damage(bat.health_component.max_health)
	check(not dying_bar.visible, "health bar: lethal damage hides the bar")

	# c. Structure: a child of the enemy root, not of the sprite, and not a child of anything that flips.
	var bat2 := fx.spawn_bat()
	await _wait_physics_frames(1)
	check(bat2.health_bar_component.get_parent() == bat2 and bat2.health_bar_component.get_parent() != bat2.sprite_node, "health bar: the bar is a child of the enemy root, not of the sprite")
	check(bat2.health_bar_component.top_level, "health bar: the bar is top level, so root rotation or flip never turns it")
	bat2.rotation = 1.0
	bat2.health_component.take_damage(1.0)
	await _wait_physics_frames(1)
	check(is_zero_approx(bat2.health_bar_component.global_rotation) and bat2.health_bar_component.global_position.is_equal_approx(bat2.global_position + bat2.health_bar_component.offset), "health bar: a rotated enemy leaves the bar upright and above it")
	var player_has_bar := false
	var player := fx.get_player()
	if is_instance_valid(player):
		for child in player.get_children():
			if child is HealthBarComponent:
				player_has_bar = true
	check(not player_has_bar, "health bar: the player has no bar")


func _section_error_guard() -> void:
	# a. The capture records a warning and an error, and drain() empties it. These two lines show in the console on purpose.
	var capture := fx.capture
	capture.drain()
	push_warning("error_guard_probe_warning")
	push_error("error_guard_probe_error")
	var entries := capture.drain()
	var warning_entry: Dictionary = {}
	var error_entry: Dictionary = {}
	for entry in entries:
		if str(entry["message"]).contains("error_guard_probe_warning"):
			warning_entry = entry
		elif str(entry["message"]).contains("error_guard_probe_error"):
			error_entry = entry
	check(entries.size() == 2 and warning_entry.get("kind", "") == "warning", "error guard: a push_warning is recorded as a warning")
	check(error_entry.get("kind", "") == "error" and not str(error_entry.get("file", "")).is_empty() and int(error_entry.get("line", 0)) > 0, "error guard: a push_error is recorded as an error with a file and a line")
	check(capture.errors_only(entries).size() == 1 and capture.drain().is_empty(), "error guard: errors_only drops the warning and a second drain is empty")

	# b. ExpectedErrors.filter with a fake list.
	var fake: Array[Dictionary] = [
		{"section": "_section_fake", "fragment": "known engine noise", "max_count": 2, "reason": "test entry"},
		{"section": "_section_fake", "fragment": "never printed at all", "max_count": 1, "reason": "test entry"},
	]
	var noise: Dictionary = {"message": "ERROR: known engine noise here", "file": "x.gd", "line": 1}
	var other: Dictionary = {"message": "something else broke", "file": "y.gd", "line": 2}
	var errors: Array[Dictionary] = [noise, noise, noise, other]
	var verdict := ExpectedErrors.filter("_section_fake", errors, fake)
	check((verdict["allowed"] as Array).size() == 2, "expected errors: a matching error is allowed up to max_count")
	check((verdict["unexpected"] as Array).size() == 2, "expected errors: one more than max_count, and an unmatched error, are unexpected")
	check((verdict["unused_entries"] as Array).size() == 1 and (verdict["unused_entries"][0] as Dictionary)["fragment"] == "never printed at all", "expected errors: an entry that matched nothing is reported as unused")
	var elsewhere := ExpectedErrors.filter("_section_other", errors, fake)
	check((elsewhere["allowed"] as Array).is_empty() and (elsewhere["unexpected"] as Array).size() == 4 and (elsewhere["unused_entries"] as Array).is_empty(), "expected errors: a different section name never matches")

	# c. The real allow-list is honest.
	var list_ok := true
	for entry in ExpectedErrors.EXPECTED:
		list_ok = list_ok and not str(entry.get("reason", "")).is_empty() and str(entry.get("fragment", "")).length() >= 12
	check(list_ok, "expected errors: every real entry has a reason and a fragment of at least 12 characters")

	# d. uninstall() removes the logger. The shared capture also sees these probes, so it is drained afterwards.
	var temporary := ErrorCapture.new()
	temporary.install()
	temporary.begin()
	push_error("error_guard_while_installed")
	var while_installed := temporary.drain()
	temporary.uninstall()
	push_error("error_guard_after_uninstall")
	var after_uninstall := temporary.drain()
	capture.drain()
	check(while_installed.size() == 1 and after_uninstall.is_empty(), "error guard: uninstall() stops the logger from recording")


# ---------------------------------------------------------------------------------------------
# Task AR: STATUS_MAGNITUDE_BONUS scales magnitude-scaling (non-ticking) statuses
# ---------------------------------------------------------------------------------------------

func _chill_speed_ratio(bat: Enemy, base_speed: float) -> float:
	return bat.stats_container.get_final_stat_value(Stat.Type.MOVEMENT_SPEED) / base_speed


func _section_status_magnitude() -> void:
	var chill := load("res://resources/status_effects/chill.tres") as StatusEffect
	var burn := load("res://resources/status_effects/burn.tres") as StatusEffect

	check(chill.magnitude_scales and is_equal_approx(chill.max_magnitude_bonus, 0.5) and not burn.magnitude_scales, "magnitude: Chill scales its magnitude (cap 0.5), Burn does not")

	# a. Bonus values on a fresh bat: 0 -> -0.3, 0.2 -> -0.36, above the cap -> cap (-0.45), negative -> 0 (-0.3).
	var expectations := [[0.0, 0.7], [0.2, 0.64], [5.0, 0.55], [-1.0, 0.7]]
	for pair in expectations:
		var bat := _spawn_bat()
		var base_speed := bat.stats_container.get_final_stat_value(Stat.Type.MOVEMENT_SPEED)
		bat.status_effect_component.apply_effect(chill, 0.0, 0.0, 0.0, pair[0])
		check(is_equal_approx(_chill_speed_ratio(bat, base_speed), pair[1]), "magnitude: Chill with bonus %s slows to %s of speed" % [pair[0], pair[1]])

	# b. The template is never mutated.
	check(is_equal_approx(chill.stat_modifiers[0].value, -0.3), "magnitude: the Chill template modifier is still -0.3 after scaled applications")

	# c. Re-apply: a higher bonus raises the live slow on the entity's stat, a lower one replaces it (latest wins).
	var bat_r := _spawn_bat()
	var speed_r := bat_r.stats_container.get_final_stat_value(Stat.Type.MOVEMENT_SPEED)
	bat_r.status_effect_component.apply_effect(chill, 0.0, 0.0, 0.0, 0.1)
	check(is_equal_approx(_chill_speed_ratio(bat_r, speed_r), 0.67), "magnitude re-apply: first application at 0.1 gives x0.67")
	bat_r.status_effect_component.apply_effect(chill, 0.0, 0.0, 0.0, 0.4)
	check(is_equal_approx(_chill_speed_ratio(bat_r, speed_r), 0.58), "magnitude re-apply: a higher bonus 0.4 raises the live slow to x0.58")
	bat_r.status_effect_component.apply_effect(chill, 0.0, 0.0, 0.0, 0.0)
	check(is_equal_approx(_chill_speed_ratio(bat_r, speed_r), 0.7), "magnitude re-apply: a lower bonus later replaces it (latest wins, x0.7)")
	check(bat_r.status_effect_component.get_active_instances().size() == 1, "magnitude re-apply: still one instance")

	# d. Burn ignores the bonus: damage, ramp and cap are unchanged.
	var comp_plain := _bare_status_component()
	var comp_bonus := _bare_status_component()
	comp_plain.apply_effect(burn, 10.0, 5.0, 0.2, 0.0)
	comp_bonus.apply_effect(burn, 10.0, 5.0, 0.2, 0.4)
	var plain: StatusEffectInstance = comp_plain._active_effects["burn"]
	var boosted: StatusEffectInstance = comp_bonus._active_effects["burn"]
	comp_plain._process(1.0)
	comp_bonus._process(1.0)
	check(is_zero_approx(boosted.magnitude_bonus) and boosted.runtime_modifiers.size() == plain.runtime_modifiers.size(), "magnitude: Burn keeps magnitude_bonus 0 and its modifiers")
	check(is_equal_approx(boosted.get_tick_damage(), plain.get_tick_damage()) and is_equal_approx(boosted.get_ramp_multiplier(), plain.get_ramp_multiplier()), "magnitude: Burn tick damage and ramp are unchanged by the bonus")
	comp_bonus.apply_effect(burn, 20.0, 5.0, 0.2, 0.4)
	check(is_zero_approx(boosted.magnitude_bonus) and is_equal_approx(boosted.dot_damage, 20.0), "magnitude: a ticking re-apply (strongest wins) ignores magnitude")

	# e. The payload snapshot comes from the stat; a profile without the key reads 0.0 and does nothing.
	var with_key := _make_stats({Stat.Type.BASE_DAMAGE: 10.0, Stat.Type.STATUS_MAGNITUDE_BONUS: 0.25, Stat.Type.CRIT_CHANCE: 1.0, Stat.Type.CRIT_MULTIPLIER: 2.0})
	var payload_a := CombatCalculations.generate_hit_payload(world as Node2D, with_key, null)
	check(is_equal_approx(payload_a.status_magnitude_snapshot, 0.25), "magnitude: the payload snapshot is the STATUS_MAGNITUDE_BONUS stat (not crit or damage scaled)")
	var without_key := _make_stats({Stat.Type.BASE_DAMAGE: 10.0})
	var payload_b := CombatCalculations.generate_hit_payload(world as Node2D, without_key, null)
	check(is_zero_approx(payload_b.status_magnitude_snapshot), "magnitude: a profile missing the key reads 0.0")
	var bat_p := _tough_bat()
	var speed_p := bat_p.stats_container.get_final_stat_value(Stat.Type.MOVEMENT_SPEED)
	payload_b.status_effects_to_apply.append(chill)
	bat_p.hurtbox_component.take_hit(payload_b)
	check(is_instance_valid(bat_p) and is_equal_approx(_chill_speed_ratio(bat_p, speed_p), 0.7), "magnitude: a hit from a profile without the key leaves Chill at x0.7")
	var bat_q := _tough_bat()
	var speed_q := bat_q.stats_container.get_final_stat_value(Stat.Type.MOVEMENT_SPEED)
	payload_a.status_effects_to_apply.append(chill)
	payload_a.crit_chance_snapshot = 0.0
	bat_q.hurtbox_component.take_hit(payload_a)
	check(is_instance_valid(bat_q) and is_equal_approx(_chill_speed_ratio(bat_q, speed_q), 0.625), "magnitude: a hit carrying snapshot 0.25 applies Chill at x0.625 through the entity")


# ---------------------------------------------------------------------------------------------
# Task AR: a GLOBAL_TAG_MATCH card needs ALL its target tags on an ability's permanent tags
# ---------------------------------------------------------------------------------------------

func _ar_card(id: String, tags: Array[Tags.Type]) -> UpgradeDefinition:
	var card := _l3_card(id)
	card.scope = UpgradeDefinition.ScopeType.GLOBAL_TAG_MATCH
	card.target_tags = tags
	card.stat_modifiers = [_l3_modifier(StatModifier.Type.PERCENT, 0.5, Stat.Type.BASE_DAMAGE)]
	return card


func _ar_pool_has(manager: UpgradeManager, player: Player, id: String) -> bool:
	for choice in manager.generate_selection_pool(player, 99):
		if choice.source_tracker.definition.upgrade_id == id:
			return true
	return false


func _section_all_match_tags() -> void:
	var manager := fx.get_upgrade_manager()
	var saved_pool := manager.master_upgrade_pool.duplicate()
	var two_tags: Array[Tags.Type] = [Tags.Type.PROJECTILE, Tags.Type.FIRE]
	var no_tags: Array[Tags.Type] = []
	var two_card := _ar_card("test_ar_two_tags", two_tags)
	var empty_card := _ar_card("test_ar_empty", no_tags)
	var definitions: Array[UpgradeDefinition] = [two_card, empty_card]
	var profile := UpgradeBlueprintProfile.new()
	profile.definition_bundle = definitions
	manager.master_upgrade_pool.append(profile)

	var both: Array[Tags.Type] = [Tags.Type.PROJECTILE, Tags.Type.FIRE]
	var one: Array[Tags.Type] = [Tags.Type.METAMAGIC, Tags.Type.FIRE]

	check(two_card.matches_permanent_tags(both) and not two_card.matches_permanent_tags(one), "all-match: the helper needs every target tag")
	check(not empty_card.matches_permanent_tags(both) and not empty_card.matches_permanent_tags(no_tags), "all-match: a card with no target tags matches nothing, not even an empty tag list")

	# a. An ability with both tags: the ledger and the pool both reach it.
	var player := fx.fresh_player()
	var ability_both := _l6_mount(player, 1, both)
	var ledger := player.run_ledger_component
	ledger.log_purchase(two_card)
	ledger.log_purchase(empty_card)
	var perm_both := ability_both.tag_component.get_permanent_tags()
	check(ledger.get_card_tier(two_card, 1, perm_both) == 1, "all-match: the two-tag card reaches an ability with both tags (ledger)")
	check(_ar_pool_has(manager, player, "test_ar_two_tags"), "all-match: the two-tag card is drafted for an ability with both tags (pool)")
	check(ledger.get_card_tier(empty_card, 1, perm_both) == 0 and not _ar_pool_has(manager, player, "test_ar_empty"), "all-match: the empty-tag card reaches nothing (ledger and pool agree)")

	# b. An ability with only one of the tags: neither the ledger nor the pool reaches it.
	player = fx.fresh_player()
	var ability_one := _l6_mount(player, 1, one)
	ledger = player.run_ledger_component
	ledger.log_purchase(two_card)
	var perm_one := ability_one.tag_component.get_permanent_tags()
	check(ledger.get_card_tier(two_card, 1, perm_one) == 0, "all-match: the two-tag card does not reach an ability with only one tag (ledger)")
	check(not _ar_pool_has(manager, player, "test_ar_two_tags"), "all-match: the two-tag card is not drafted for an ability with only one tag (pool)")

	# c. A temporary tag never completes the pair.
	player = fx.fresh_player()
	var ability_temp := _l6_mount(player, 1, one)
	ability_temp.tag_component.add_temporary_tag(Tags.Type.PROJECTILE)
	check(not _ar_pool_has(manager, player, "test_ar_two_tags"), "all-match: a temporary tag does not complete the pair (pool)")
	ability_temp.tag_component.remove_temporary_tag(Tags.Type.PROJECTILE)

	# d. Tags spread over different abilities do not combine.
	player = fx.fresh_player()
	_l6_mount(player, 1, one)
	_l6_mount(player, 2, one)
	var only_projectile: Array[Tags.Type] = [Tags.Type.PROJECTILE]
	_l6_mount(player, 3, only_projectile)
	check(not _ar_pool_has(manager, player, "test_ar_two_tags"), "all-match: tags spread over different abilities do not combine (pool)")
	_l6_mount(player, 4, both)
	check(_ar_pool_has(manager, player, "test_ar_two_tags"), "all-match: slot 4 with both tags makes the card eligible (pool)")

	manager.master_upgrade_pool = saved_pool


const SUPERCONDUCT_EVOLVE_CARD := "res://resources/compounds/superconduct_evolution_upgrade_def.tres"
const SUPERCONDUCT_OVERCLOCK_CARD := "res://resources/compounds/superconduct_overclock_upgrade_def.tres"
const COMPOUND_BLUEPRINT := "res://resources/compounds/compound_blueprint.tres"


## A geometry that only keeps the payload it was handed, to read what Ability._trigger_ability_delivery wired.
class _CaptureGeometry extends GeometryDriver:
	var captured: CombatPayload = null

	func execute_geometry(_query_results: Dictionary, final_payload: CombatPayload) -> void:
		captured = final_payload

	func get_family() -> StringName:
		return &"timed"


## A payload whose hits crit with `crit_chance`, refunding `refund` seconds per crit up to `cap` per cast, with its own CastEvents.
func _refund_payload(stats: StatsContainer, refund: float, cap: float, crit_chance: float = 1.0) -> CombatPayload:
	var payload := _storm_crit_payload(stats, 10.0, [])
	payload.crit_chance_snapshot = crit_chance
	payload.crit_refund_snapshot = refund
	payload.crit_refund_cap_snapshot = cap
	payload.cast_events = CastEvents.new()
	return payload


## Wires a payload's refunds to `ability` the way Ability._trigger_ability_delivery does.
func _wire_refund(payload: CombatPayload, ability: Ability) -> CombatPayload:
	payload.cast_events.cooldown_refunded.connect(ability._on_cooldown_refunded)
	return payload


func _section_superconduct() -> void:
	var frost := load(FROST_CARD) as UpgradeDefinition
	var lightning := load(LIGHTNING_CARD) as UpgradeDefinition
	var fire := load(FIRE_CARD) as UpgradeDefinition
	var evolve_card := load(SUPERCONDUCT_EVOLVE_CARD) as UpgradeDefinition
	var overclock_card := load(SUPERCONDUCT_OVERCLOCK_CARD) as UpgradeDefinition
	var blueprint := load(COMPOUND_BLUEPRINT) as UpgradeBlueprintProfile
	var mgr := fx.get_upgrade_manager()
	var stats := _make_stats({Stat.Type.AOE_RADIUS: 40.0})
	var floor_time: float = Ability.MIN_REMAINING
	seed(12345)

	# a. Data, enum values, registration.
	check(int(Stat.Type.CRIT_COOLDOWN_REFUND) == 26 and int(Stat.Type.CRIT_REFUND_CAP) == 27 and int(Tags.Type.FROST) == 10 and int(Tags.Type.LIGHTNING) == 11, "superconduct data: CRIT_COOLDOWN_REFUND is 26, CRIT_REFUND_CAP is 27 (appended), Frost 10, Lightning 11")
	check(evolve_card.upgrade_id == "compound_superconduct_evolve" and overclock_card.upgrade_id == "compound_superconduct_overclock" and evolve_card.display_name == "Evolve + Superconduct" and overclock_card.display_name == "Overclock + Superconduct", "superconduct data: ids and names")
	check(evolve_card.is_compound_card() and overclock_card.is_compound_card() and evolve_card.payload_type == UpgradeDefinition.PayloadType.ABILITY_UNLOCK and overclock_card.payload_type == UpgradeDefinition.PayloadType.ABILITY_OVERCLOCK, "superconduct data: both are compound cards (ABILITY_UNLOCK and ABILITY_OVERCLOCK)")
	check(evolve_card.compound_pair == [Tags.Type.FROST, Tags.Type.LIGHTNING] and overclock_card.compound_pair == evolve_card.compound_pair, "superconduct data: both cards name Frost + Lightning")
	check(evolve_card.evolves_from == null and evolve_card.ability_data_payload == null and evolve_card.impact_burst_payload == null and overclock_card.impact_burst_payload == null and evolve_card.status_effect_payload == null and overclock_card.status_effect_payload == null, "superconduct data: no evolves_from, no ability data, no burst, no status")
	var modifiers_ok := true
	for card in [evolve_card, overclock_card]:
		var mods := (card as UpgradeDefinition).stat_modifiers
		modifiers_ok = modifiers_ok and mods.size() == 2 \
				and mods[0].type == StatModifier.Type.FLAT and mods[0].target_stat_type == Stat.Type.CRIT_COOLDOWN_REFUND and is_equal_approx(mods[0].value, 0.25) \
				and mods[1].type == StatModifier.Type.FLAT and mods[1].target_stat_type == Stat.Type.CRIT_REFUND_CAP and is_equal_approx(mods[1].value, 0.5)
	check(modifiers_ok, "superconduct data: both cards carry FLAT +0.25 CRIT_COOLDOWN_REFUND and FLAT +0.5 CRIT_REFUND_CAP")
	var shipped_compounds: Array[String] = []
	for definition in blueprint.definition_bundle:
		if definition.is_compound_card():
			shipped_compounds.append(definition.upgrade_id)
	shipped_compounds.sort()
	check(blueprint.definition_bundle.has(evolve_card) and blueprint.definition_bundle.has(overclock_card), "superconduct data: both cards are registered in compound_blueprint.tres")
	check(shipped_compounds == ["compound_blizzard_evolve", "compound_blizzard_overclock", "compound_magma_evolve", "compound_magma_overclock", "compound_shatter_evolve", "compound_shatter_overclock", "compound_storm_evolve", "compound_storm_overclock", "compound_superconduct_evolve", "compound_superconduct_overclock"], "superconduct guard: the blueprint holds exactly the ten shipped compound cards (found %s)" % str(shipped_compounds))
	for data_path in ["res://resources/abilities/arcane_bolt/arcane_bolt_data.tres", "res://resources/abilities/arc_bolt/arc_bolt_data.tres"]:
		var base_stats := (load(data_path) as AbilityData).stats_profile.base_stats
		check(base_stats.get(Stat.Type.CRIT_COOLDOWN_REFUND, -1.0) == 0.0 and base_stats.get(Stat.Type.CRIT_REFUND_CAP, -1.0) == 0.0, "superconduct profiles: %s carries both refund stats at 0.0" % data_path.get_file().get_basename())

	# b. claim_crit_refund on its own.
	var claim := _refund_payload(stats, 0.25, 0.5)
	check(is_zero_approx(CombatCalculations.claim_crit_refund(claim)), "superconduct claim: the shared (unresolved) cast payload never refunds")
	var claim_crit := CombatCalculations.resolve_hit_crit(claim)
	check(claim_crit.is_critical_hit and claim_crit.cast_events == claim.cast_events, "superconduct claim: a critting copy shares the cast's CastEvents")
	var grants: Array[float] = []
	for i in range(3):
		grants.append(CombatCalculations.claim_crit_refund(claim_crit))
	check(is_equal_approx(grants[0], 0.25) and is_equal_approx(grants[1], 0.25) and is_zero_approx(grants[2]) and is_equal_approx(claim.cast_events.refunded, 0.5), "superconduct claim: 0.25 per crit up to the 0.5 cap, then 0 (got %s, total %s)" % [str(grants), claim.cast_events.refunded])
	var partial := CombatCalculations.resolve_hit_crit(_refund_payload(stats, 0.4, 0.5))
	var partial_grants: Array[float] = [CombatCalculations.claim_crit_refund(partial), CombatCalculations.claim_crit_refund(partial), CombatCalculations.claim_crit_refund(partial)]
	check(is_equal_approx(partial_grants[0], 0.4) and is_equal_approx(partial_grants[1], 0.1) and is_zero_approx(partial_grants[2]), "superconduct claim: the last grant is cut to the cap room left (got %s)" % str(partial_grants))
	var burst_like := _refund_payload(stats, 0.25, 0.5)
	burst_like.is_critical_hit = true
	burst_like.is_burst = true
	check(is_zero_approx(CombatCalculations.claim_crit_refund(burst_like)), "superconduct claim: a burst payload never refunds")
	var no_events := _refund_payload(stats, 0.25, 0.5)
	no_events.is_critical_hit = true
	no_events.cast_events = null
	check(is_zero_approx(CombatCalculations.claim_crit_refund(no_events)), "superconduct claim: a payload without CastEvents refunds nothing")
	var no_snapshot := _refund_payload(stats, 0.0, 0.5)
	no_snapshot.is_critical_hit = true
	check(is_zero_approx(CombatCalculations.claim_crit_refund(no_snapshot)), "superconduct claim: a 0 snapshot refunds nothing")
	var no_cap := _refund_payload(stats, 0.25, 0.0)
	no_cap.is_critical_hit = true
	check(is_zero_approx(CombatCalculations.claim_crit_refund(no_cap)), "superconduct claim: a 0 cap refunds nothing")

	# c. Timer behavior through take_hit. Bats first (they await); the timer checks below run with no awaits.
	var bats := await _spawn_burst_bats(Vector2(110000.0, 110000.0), [Vector2(0, 0)])
	var player := fx.fresh_player()
	var ability := fx.mount_arcane_bolt(player)
	var timer := ability._cooldown_timer
	var hurtbox := bats[0].hurtbox_component
	timer.start(10.0)
	hurtbox.take_hit(_wire_refund(_refund_payload(stats, 0.25, 0.5), ability))
	check(absf(timer.time_left - 9.75) < 0.01, "superconduct timer: a crit shortens the running cooldown by the refund (left %s)" % timer.time_left)
	hurtbox.take_hit(_wire_refund(_refund_payload(stats, 0.25, 0.5, 0.0), ability))
	check(absf(timer.time_left - 9.75) < 0.01, "superconduct timer: a non-crit does not")
	var burst_hit := _wire_refund(_refund_payload(stats, 0.25, 0.5), ability)
	burst_hit.is_burst = true
	hurtbox.take_hit(burst_hit)
	check(absf(timer.time_left - 9.75) < 0.01 and is_zero_approx(burst_hit.cast_events.refunded), "superconduct timer: a burst payload does not")
	var fan := _wire_refund(_refund_payload(stats, 0.25, 0.5), ability)
	timer.start(10.0)
	for i in range(6):
		hurtbox.take_hit(fan)
	check(absf(timer.time_left - 9.5) < 0.01 and is_equal_approx(fan.cast_events.refunded, 0.5), "superconduct timer: six crits of one cast refund 0.5 in total, the cap (left %s)" % timer.time_left)
	var second_cast := _wire_refund(_refund_payload(stats, 0.25, 0.5), ability)
	for i in range(6):
		hurtbox.take_hit(second_cast)
	check(absf(timer.time_left - 9.0) < 0.01 and is_equal_approx(second_cast.cast_events.refunded, 0.5), "superconduct timer: a second cast has a fresh cap (left %s)" % timer.time_left)

	# d. The floor, and what Timer.start(0) does.
	timer.start(1.0)
	hurtbox.take_hit(_wire_refund(_refund_payload(stats, 5.0, 10.0), ability))
	check(absf(timer.time_left - floor_time) < 0.01 and absf(timer.wait_time - floor_time) < 0.001 and not timer.is_stopped(), "superconduct floor: a refund bigger than the time left leaves MIN_REMAINING (left %s, wait_time %s)" % [timer.time_left, timer.wait_time])
	hurtbox.take_hit(_wire_refund(_refund_payload(stats, 5.0, 10.0), ability))
	check(absf(timer.time_left - floor_time) < 0.01 and absf(timer.wait_time - floor_time) < 0.001, "superconduct floor: a refund with only MIN_REMAINING left changes nothing (never lengthens)")
	var probe := Timer.new()
	world.add_child(probe)
	fx.track(probe)
	probe.start(2.0)
	probe.start(0.0)
	check(is_equal_approx(probe.wait_time, 2.0) and is_equal_approx(probe.time_left, 2.0), "engine: Timer.start(0.0) keeps the previous wait_time (the reason the refund never passes 0)")
	probe.start(0.7)
	check(is_equal_approx(probe.wait_time, 0.7), "engine: Timer.start(t > 0) also sets wait_time to t")

	# e. A stopped timer holds the refund; the next cooldown takes it off; the cycle after is the full stat value.
	var full: float = ability.stats_container.get_final_stat_value(Stat.Type.COOLDOWN)
	timer.stop()
	hurtbox.take_hit(_wire_refund(_refund_payload(stats, 0.25, 0.5), ability))
	check(timer.is_stopped() and is_equal_approx(ability._pending_refund, 0.25), "superconduct pending: a crit while the timer is stopped is held, the timer stays stopped")
	ability._start_cooldown_phase()
	check(absf(timer.time_left - (full - 0.25)) < 0.01 and is_zero_approx(ability._pending_refund), "superconduct pending: the next cooldown is the stat value minus the held refund and the hold is cleared (left %s, full %s)" % [timer.time_left, full])
	ability._start_cooldown_phase()
	check(absf(timer.time_left - full) < 0.01 and is_equal_approx(timer.wait_time, full), "superconduct pending: the cooldown after that is the full stat value")
	timer.stop()
	hurtbox.take_hit(_wire_refund(_refund_payload(stats, 50.0, 100.0), ability))
	ability._start_cooldown_phase()
	check(absf(timer.time_left - floor_time) < 0.01, "superconduct pending: a held refund bigger than the cooldown leaves MIN_REMAINING")
	timer.start(10.0)
	hurtbox.take_hit(_wire_refund(_refund_payload(stats, 0.25, 0.5), ability))
	check(absf(timer.wait_time - 9.75) < 0.01, "superconduct restore: after a refund the timer's wait_time is the shortened value")
	ability._on_stat_updated(Stat.Type.COOLDOWN, full)
	check(is_equal_approx(timer.wait_time, full) and absf(timer.time_left - 9.75) < 0.01, "superconduct restore: a COOLDOWN stat update sets wait_time and leaves the time left alone")
	ability._start_cooldown_phase()
	check(absf(timer.time_left - full) < 0.01 and is_equal_approx(timer.wait_time, full), "superconduct restore: the next normal cooldown after a refunded cycle is the full stat value")

	# f. A slot without the stats refunds nothing (missing stats read 0.0).
	var plain := CombatCalculations.generate_hit_payload(player, ability.stats_container, ability.tag_component)
	check(is_zero_approx(plain.crit_refund_snapshot) and is_zero_approx(plain.crit_refund_cap_snapshot) and plain.cast_events != null and is_zero_approx(plain.cast_events.refunded), "superconduct missing: a slot without the cards snapshots 0 / 0 and a fresh CastEvents")
	var bare := CombatCalculations.generate_hit_payload(player, _make_stats({}), null)
	check(is_zero_approx(bare.crit_refund_snapshot) and is_zero_approx(bare.crit_refund_cap_snapshot), "superconduct missing: a profile without the keys reads 0.0")
	_wire_refund(bare, ability)
	bare.crit_chance_snapshot = 1.0
	bare.crit_multiplier_snapshot = 2.0
	timer.start(10.0)
	hurtbox.take_hit(bare)
	check(absf(timer.time_left - 10.0) < 0.01 and is_zero_approx(bare.cast_events.refunded), "superconduct missing: a critting hit from such a cast leaves the timer alone")
	var again := CombatCalculations.generate_hit_payload(player, ability.stats_container, ability.tag_component)
	check(plain.cast_events != again.cast_events, "superconduct cast: every cast gets its own CastEvents")
	timer.stop()
	_free_bats(bats)

	# g. A strike (burst) never refunds, while its triggering crit does exactly once.
	var strike := load(STORM_BURST) as ImpactBurstDefinition
	var strike_list: Array[ImpactBurstDefinition] = [strike]
	var strike_bats := await _spawn_burst_bats(Vector2(112000.0, 112000.0), [Vector2(0, 0)])
	var strike_payload := _storm_crit_payload(stats, 10.0, strike_list)
	strike_payload.crit_refund_snapshot = 0.25
	strike_payload.crit_refund_cap_snapshot = 5.0
	strike_payload.cast_events = CastEvents.new()
	strike_bats[0].hurtbox_component.take_hit(strike_payload)
	await tree.process_frame
	await tree.process_frame
	check(_recorded[0].size() == 2 and is_equal_approx(strike_payload.cast_events.refunded, 0.25), "superconduct strike: the crit refunds once, the strike hit it triggers refunds nothing (hits %d, refunded %s)" % [_recorded[0].size(), strike_payload.cast_events.refunded])
	_free_bats(strike_bats)

	# h. Real cast: Frost 3 + Lightning 3 offers the two cards, the purchase is slot-specific, the cast wires the refund.
	var frost_player := _socket_pair(frost, lightning, 3)
	check(mgr._find_next_offer_slot(frost_player) == 1, "superconduct offer: Frost 3 + Lightning 3 makes slot 1 offer-eligible")
	var offer := mgr._build_offer_choices(frost_player, 1)
	check(_offer_ids(offer) == ["compound_superconduct_evolve", "compound_superconduct_overclock"], "superconduct offer: exactly Evolve + Superconduct and Overclock + Superconduct, no generic Overclock (got %s)" % str(_offer_ids(offer)))
	var frost_ability := frost_player.ability_container.get_ability_by_slot(1)
	var tags: Array[Tags.Type] = frost_ability.tag_component.get_permanent_tags()
	var ledger := frost_player.run_ledger_component
	var scale_before := frost_ability.stats_container.get_indirect_damage_scale()
	var cooldown_before := frost_ability.stats_container.get_final_stat_value(Stat.Type.COOLDOWN)
	var payload_before := CombatCalculations.generate_hit_payload(frost_player, frost_ability.stats_container, frost_ability.tag_component)
	check(is_zero_approx(payload_before.crit_refund_snapshot) and scale_before > 1.0, "superconduct frost: before the card there is no refund and Frost's indirect scale is above 1 (%s)" % scale_before)
	frost_player.apply_contextual_upgrade(offer[0])
	check(ledger.purchase_registry.has(PurchaseKey.make("compound_superconduct_evolve", 1)) and not ledger.purchase_registry.has("compound_superconduct_evolve"), "superconduct evolve: logged as a slot-specific purchase")
	check(is_equal_approx(ledger.get_modifier_totals(1, tags, Stat.Type.CRIT_COOLDOWN_REFUND).x, 0.25) and is_equal_approx(ledger.get_modifier_totals(1, tags, Stat.Type.CRIT_REFUND_CAP).x, 0.5), "superconduct evolve: slot 1 gets +0.25 and +0.5 flat")
	for other_slot in [0, 2, 3, 4]:
		check(is_zero_approx(ledger.get_modifier_totals(other_slot, tags, Stat.Type.CRIT_COOLDOWN_REFUND).x) and is_zero_approx(ledger.get_modifier_totals(other_slot, tags, Stat.Type.CRIT_REFUND_CAP).x), "superconduct evolve: slot %d gets nothing" % other_slot)
	var other_stats := _make_stats({Stat.Type.CRIT_COOLDOWN_REFUND: 0.0, Stat.Type.CRIT_REFUND_CAP: 0.0}, 2, ledger)
	check(is_zero_approx(other_stats.get_final_stat_value(Stat.Type.CRIT_COOLDOWN_REFUND)) and is_zero_approx(other_stats.get_final_stat_value(Stat.Type.CRIT_REFUND_CAP)), "superconduct evolve: a slot-2 stats container with the keys still reads 0 / 0")
	var payload_after := CombatCalculations.generate_hit_payload(frost_player, frost_ability.stats_container, frost_ability.tag_component)
	check(is_equal_approx(payload_after.crit_refund_snapshot, 0.25) and is_equal_approx(payload_after.crit_refund_cap_snapshot, 0.5), "superconduct cast: the payload snapshots 0.25 / 0.5, not scaled by Frost's damage_scale (%s)" % payload_after.damage_scale)
	check(is_equal_approx(payload_after.damage_scale, payload_before.damage_scale) and is_equal_approx(payload_after.final_damage, payload_before.final_damage) and is_equal_approx(payload_after.dot_damage_snapshot, payload_before.dot_damage_snapshot) and is_equal_approx(frost_ability.stats_container.get_indirect_damage_scale(), scale_before) and is_equal_approx(frost_ability.stats_container.get_final_stat_value(Stat.Type.COOLDOWN), cooldown_before), "superconduct frost: damage_scale, hit and DoT snapshots, Frost's indirect scale and COOLDOWN are unchanged by the card")
	var frost_bats := await _spawn_burst_bats(Vector2(114000.0, 114000.0), [Vector2(0, 0)])
	var capture := _CaptureGeometry.new()
	frost_ability.add_child(capture)
	frost_ability.geometry_driver = capture
	var frost_timer := frost_ability._cooldown_timer
	frost_timer.stop()
	frost_ability._pending_refund = 0.0
	frost_ability._trigger_ability_delivery()
	check(capture.captured != null and capture.captured.cast_events.cooldown_refunded.is_connected(frost_ability._on_cooldown_refunded), "superconduct cast: _trigger_ability_delivery connects the payload's refund signal to the Ability")
	capture.captured.crit_chance_snapshot = 1.0
	frost_bats[0].hurtbox_component.take_hit(capture.captured)
	check(frost_timer.is_stopped() and is_equal_approx(frost_ability._pending_refund, 0.25), "superconduct cast: a crit during delivery (timer stopped) is held as a pending refund")
	capture.delivery_finished.connect(frost_ability._on_delivery_finished)
	capture.delivery_finished.emit()
	var frost_full: float = frost_ability.stats_container.get_final_stat_value(Stat.Type.COOLDOWN)
	check(absf(frost_timer.time_left - maxf(frost_full - 0.25, floor_time)) < 0.01, "superconduct cast: delivery_finished starts the cooldown shortened by the held refund (left %s, full %s)" % [frost_timer.time_left, frost_full])
	frost_timer.stop()
	_free_bats(frost_bats)

	# i. Overclock + Superconduct: same effect, slot-specific, overclocked.
	var oc_player := _socket_pair(frost, lightning, 3)
	var oc_ability := oc_player.ability_container.get_ability_by_slot(1)
	var oc_tags: Array[Tags.Type] = oc_ability.tag_component.get_permanent_tags()
	oc_player.apply_contextual_upgrade(offer[1])
	var oc_ledger := oc_player.run_ledger_component
	check(oc_ledger.purchase_registry.has(PurchaseKey.make("compound_superconduct_overclock", 1)) and oc_ledger.is_overclocked(1) and is_equal_approx(oc_ledger.get_modifier_totals(1, oc_tags, Stat.Type.CRIT_COOLDOWN_REFUND).x, 0.25) and is_zero_approx(oc_ledger.get_modifier_totals(2, oc_tags, Stat.Type.CRIT_COOLDOWN_REFUND).x), "superconduct overclock: slot-specific, overclocked, the refund reaches slot 1 only")

	# j. Other pairs are unaffected; no leak into drafts or the debug list.
	var fire_player := _socket_pair(fire, lightning, 3)
	check(_offer_ids(mgr._build_offer_choices(fire_player, 1)) == ["evolve_arc_bolt", "overclock"], "superconduct offer: Fire 3 + Lightning 3 is unaffected")
	var leaked := false
	for choice in mgr.generate_selection_pool(frost_player, 99):
		leaked = leaked or choice.definition.is_compound_card()
	for entry in DebugActions.grantable_cards(mgr):
		leaked = leaked or (entry["definition"] as UpgradeDefinition).is_compound_card()
	check(not leaked, "superconduct pool: no compound card appears in level-up drafts or the debug grant list")

	# k. A freed Ability leaves no connection behind and the emit is harmless.
	var dangling := _refund_payload(stats, 0.25, 0.5)
	var doomed_player := fx.fresh_player()
	var doomed := fx.mount_arcane_bolt(doomed_player)
	doomed._cooldown_timer.stop()
	dangling.cast_events.cooldown_refunded.connect(doomed._on_cooldown_refunded)
	check(dangling.cast_events.cooldown_refunded.get_connections().size() == 1, "superconduct dangling: one connection while the Ability lives")
	doomed.free()
	check(dangling.cast_events.cooldown_refunded.get_connections().is_empty(), "superconduct dangling: freeing the Ability removes the connection")
	dangling.cast_events.cooldown_refunded.emit(0.25)
	check(true, "superconduct dangling: emitting after the Ability is gone raises no error (the error guard watches this section)")


const BLIZZARD_EVOLVE_CARD := "res://resources/compounds/blizzard_evolution_upgrade_def.tres"
const BLIZZARD_OVERCLOCK_CARD := "res://resources/compounds/blizzard_overclock_upgrade_def.tres"
const BLIZZARD_BURST := "res://resources/bursts/blizzard_vortex.tres"
const BLIZZARD_VORTEX_SCENE := "res://scenes/effects/blizzard_vortex.tscn"
const CHILL_EFFECT := "res://resources/status_effects/chill.tres"


## A cast payload for the vortex: Chill, hit damage `damage`, a Chill duration of `chill_seconds`, no crit.
func _vortex_payload(stats: StatsContainer, damage: float, chill_seconds: float = 3.0) -> CombatPayload:
	var definition := load(BLIZZARD_BURST) as ImpactBurstDefinition
	var chill_list: Array[StatusEffect] = [load(CHILL_EFFECT) as StatusEffect]
	var payload := _ext_payload(stats, damage, definition, chill_list)
	payload.status_duration_snapshot = chill_seconds
	payload.cast_budget = CastBudget.new()
	return payload


func _free_zone(zone) -> void:
	if is_instance_valid(zone):
		zone.queue_free()


func _section_blizzard() -> void:
	LingeringZone.reset_registry()
	var vortex := load(BLIZZARD_BURST) as ImpactBurstDefinition
	var vortex_scene := load(BLIZZARD_VORTEX_SCENE) as PackedScene
	var chill := load(CHILL_EFFECT) as StatusEffect
	var evolve_card := load(BLIZZARD_EVOLVE_CARD) as UpgradeDefinition
	var overclock_card := load(BLIZZARD_OVERCLOCK_CARD) as UpgradeDefinition
	var blueprint := load(COMPOUND_BLUEPRINT) as UpgradeBlueprintProfile
	var mgr := fx.get_upgrade_manager()
	var stats := _make_stats({Stat.Type.AOE_RADIUS: 5.0})
	var host := _zone_host()
	seed(12345)

	# a. Data.
	check(vortex.burst_id == &"blizzard_vortex" and vortex.trigger == ImpactBurstDefinition.Trigger.ON_HIT and vortex.shape == null and vortex.effect_scene == vortex_scene and vortex.carried_status_tags == [Tags.Type.CHILLED] and vortex.unlock_level == 1 and vortex.max_per_cast == 1 and not vortex.hits_primary, "blizzard data: the vortex burst is effect-only, ON_HIT, carries only CHILLED, level 1, cap 1")
	var probe := vortex_scene.instantiate() as LingeringZone
	check(probe != null and probe.zone_id == &"blizzard_vortex" and is_equal_approx(probe.lifetime, 3.0) and is_equal_approx(probe.apply_interval, 0.2) and probe.scale_interval_with_speed and is_equal_approx(probe.damage_fraction, 0.1) and is_equal_approx(probe.radius_multiplier, 5.0) and is_equal_approx(probe.merge_distance, 40.0) and probe.max_live_zones == 6, "blizzard data: the vortex scene's exports (3 s, 0.2 s scaled by speed, 0.1 damage, radius 5, merge 40, cap 6)")
	if probe != null:
		probe.free()
	check(evolve_card.is_compound_card() and overclock_card.is_compound_card() and evolve_card.payload_type == UpgradeDefinition.PayloadType.ABILITY_UNLOCK and overclock_card.payload_type == UpgradeDefinition.PayloadType.ABILITY_OVERCLOCK and evolve_card.compound_pair == [Tags.Type.FROST, Tags.Type.WIND] and overclock_card.compound_pair == evolve_card.compound_pair, "blizzard data: both cards are compound cards naming Frost + Wind")
	check(evolve_card.impact_burst_payload == vortex and overclock_card.impact_burst_payload == vortex and evolve_card.status_effect_payload == chill and overclock_card.status_effect_payload == chill and evolve_card.evolves_from == null and evolve_card.ability_data_payload == null and evolve_card.stat_modifiers.is_empty() and overclock_card.stat_modifiers.is_empty(), "blizzard data: both cards carry the vortex and Chill, no ability data, no stat modifiers")
	check(blueprint.definition_bundle.has(evolve_card) and blueprint.definition_bundle.has(overclock_card), "blizzard data: both cards are registered in compound_blueprint.tres")
	var chill_before := [chill.effect_id, chill.base_duration, chill.tick_interval, chill.magnitude_scales, chill.max_magnitude_bonus, chill.granted_tags.duplicate(), chill.stat_modifiers.size(), chill.stat_modifiers[0].value, chill.stat_modifiers[0].type, chill.stat_modifiers[0].target_stat_type]

	# b. Pulses damage and Chill everything inside, nothing outside; pulses never crit or start a burst.
	var origin := Vector2(116000.0, 116000.0)
	var bats := await _spawn_burst_bats(origin, [Vector2(0, 0), Vector2(20, 0), Vector2(100, 0)])
	var chill_refreshes := [0]
	bats[1].status_effect_component.refreshed.connect(func(_instance: StatusEffectInstance) -> void: chill_refreshes[0] += 1)
	var payload := _vortex_payload(stats, 10.0, -2.7) # Chill base 3.0 s - 2.7 = 0.3 s
	payload.crit_chance_snapshot = 1.0
	payload.crit_multiplier_snapshot = 2.0
	var zone := await _spawn_zone(vortex, payload, origin)
	check(zone != null and is_equal_approx(zone._interval, 0.2) and LingeringZone.get_live_count(&"blizzard_vortex") == 1, "blizzard pulse: a vortex spawned, registered, pulsing every 0.2 s with SPEED_BONUS 0")
	await tree.create_timer(0.7).timeout
	var inside_hits: Array = _recorded[1]
	var pulses_ok: bool = inside_hits.size() >= 2
	for seen in inside_hits:
		pulses_ok = pulses_ok and seen.is_burst and not seen.is_critical_hit and seen.impact_bursts.is_empty() and is_equal_approx(seen.final_damage, 1.0) and seen.status_effects_to_apply.size() == 1
	check(pulses_ok, "blizzard pulse: every pulse hit is_burst, not a crit even with crit chance 1.0, has no bursts, carries Chill and deals 10 * 0.1 = 1 (%d pulses)" % inside_hits.size())
	check(is_equal_approx(_lost(bats[1]), float(inside_hits.size())) and is_equal_approx(_lost(bats[0]), float(_recorded[0].size())) and _recorded[0].size() == inside_hits.size(), "blizzard pulse: every enemy inside loses 1 per pulse")
	check(_recorded[2].is_empty() and is_zero_approx(_lost(bats[2])), "blizzard pulse: an enemy outside the radius takes nothing")
	check(bats[1].status_effect_component._active_effects.has("chill") and bats[1].status_effect_component.get_active_instances().size() == 1 and chill_refreshes[0] >= 2, "blizzard chill: Chill is applied on the first pulse and refreshed by later ones, one instance (refreshed %d times)" % chill_refreshes[0])
	check(not bats[2].status_effect_component._active_effects.has("chill"), "blizzard chill: an enemy outside is not Chilled")

	# c. Chill expires after the enemy leaves; the latest payload wins on refresh.
	bats[1].global_position = origin + Vector2(300, 0)
	await tree.physics_frame
	await tree.physics_frame
	var count_left: int = _recorded[1].size()
	await tree.create_timer(0.6).timeout
	check(_recorded[1].size() == count_left and not bats[1].status_effect_component._active_effects.has("chill"), "blizzard chill: after the enemy leaves, pulses stop hitting it and the 0.3 s Chill expires")
	var stronger := _vortex_payload(stats, 40.0, 0.3)
	var stronger_burst := stronger.duplicate() as CombatPayload
	stronger_burst.is_burst = true
	var no_bursts: Array[ImpactBurstDefinition] = []
	stronger_burst.impact_bursts = no_bursts
	var before_refresh: int = _recorded[0].size()
	zone.refresh(stronger_burst)
	await tree.create_timer(0.3).timeout
	var latest: CombatPayload = _recorded[0][_recorded[0].size() - 1]
	check(_recorded[0].size() > before_refresh and is_equal_approx(latest.final_damage, 4.0), "blizzard refresh: the latest payload wins, pulses now deal 40 * 0.1 = 4")
	check([chill.effect_id, chill.base_duration, chill.tick_interval, chill.magnitude_scales, chill.max_magnitude_bonus, chill.granted_tags, chill.stat_modifiers.size(), chill.stat_modifiers[0].value, chill.stat_modifiers[0].type, chill.stat_modifiers[0].target_stat_type] == chill_before and is_equal_approx(chill.stat_modifiers[0].value, -0.3) and chill.granted_tags == [Tags.Type.CHILLED], "blizzard chill: the Chill template is unchanged by the pulses")

	# d. Lifetime, merge refresh.
	await tree.create_timer(0.5).timeout
	var near := await _spawn_zone(vortex, _vortex_payload(stats, 10.0), origin + Vector2(10, 0))
	await tree.process_frame
	check(LingeringZone.get_live_count(&"blizzard_vortex") == 1 and is_instance_valid(zone) and not is_instance_valid(near), "blizzard merge: a new hit within merge_distance refreshes the live vortex instead of adding one")
	await tree.create_timer(2.4).timeout
	check(is_instance_valid(zone), "blizzard merge: the refresh reset the lifetime (the vortex outlives its original 3 s)")
	await tree.create_timer(1.0).timeout
	check(not is_instance_valid(zone) and LingeringZone.get_live_count(&"blizzard_vortex") == 0, "blizzard lifetime: the vortex frees itself 3 s after its last refresh and unregisters")
	_free_bats(bats)

	# e. Interval: 0.2 / (1 + SPEED_BONUS), never below 0.05; pulse rate follows.
	var intervals: Array[float] = []
	for bonus in [0.0, 1.0, 3.0, 9.0]:
		var speed_stats := _make_stats({Stat.Type.AOE_RADIUS: 5.0, Stat.Type.SPEED_BONUS: bonus})
		var speed_zone := vortex_scene.instantiate() as LingeringZone
		speed_zone.configure(_vortex_payload(speed_stats, 10.0))
		intervals.append(speed_zone._interval)
		speed_zone.free()
	check(is_equal_approx(intervals[0], 0.2) and is_equal_approx(intervals[1], 0.1) and is_equal_approx(intervals[2], 0.05) and is_equal_approx(intervals[3], 0.05), "blizzard speed: interval 0.2 / (1 + SPEED_BONUS), floor 0.05 (got %s)" % str(intervals))
	var rate_origin := Vector2(118000.0, 118000.0)
	var rate_counts: Array[int] = []
	for bonus in [0.0, 1.0]:
		var rate_bats := await _spawn_burst_bats(rate_origin, [Vector2(0, 0)])
		var rate_stats := _make_stats({Stat.Type.AOE_RADIUS: 5.0, Stat.Type.SPEED_BONUS: bonus})
		var rate_zone := await _spawn_zone(vortex, _vortex_payload(rate_stats, 10.0), rate_origin)
		await tree.create_timer(0.6).timeout
		rate_counts.append(_recorded[0].size())
		_free_zone(rate_zone)
		_free_bats(rate_bats)
		await tree.process_frame
	check(rate_counts[0] >= 2 and rate_counts[1] > rate_counts[0], "blizzard speed: SPEED_BONUS 1.0 pulses more often than 0 in the same time (%s)" % str(rate_counts))

	# f. A real hit queues one vortex at the impact point; max_per_cast holds over a fan; a crit makes stronger pulses.
	var hit_origin := Vector2(120000.0, 120000.0)
	var hit_bats := await _spawn_burst_bats(hit_origin, [Vector2(0, 0), Vector2(20, 0)])
	var children_before := host.get_child_count()
	var fan := _vortex_payload(stats, 10.0)
	fan.crit_chance_snapshot = 1.0
	fan.crit_multiplier_snapshot = 2.0
	for i in range(4):
		hit_bats[0].hurtbox_component.take_hit(fan)
	await tree.process_frame
	await tree.process_frame
	var spawned: LingeringZone = null
	if host.get_child_count() > children_before:
		spawned = host.get_child(host.get_child_count() - 1) as LingeringZone
	check(spawned != null and host.get_child_count() == children_before + 1 and spawned.global_position.is_equal_approx(hit_origin) and LingeringZone.get_live_count(&"blizzard_vortex") == 1, "blizzard hit: four crits of one cast queue exactly one vortex, at the impact point (max_per_cast 1)")
	await tree.create_timer(0.5).timeout
	var neighbor_hits: Array = _recorded[1]
	var crit_pulse := false
	for seen in neighbor_hits:
		crit_pulse = crit_pulse or is_equal_approx(seen.final_damage, 2.0)
	check(crit_pulse and neighbor_hits.size() >= 2, "blizzard crit: pulses made from a crit hit deal 20 * 0.1 = 2 (the resolved damage)")
	_free_zone(spawned)
	_free_bats(hit_bats)

	# g. An enemy freed or killed mid-zone causes no error.
	var kill_origin := Vector2(122000.0, 122000.0)
	var kill_bats := await _spawn_burst_bats(kill_origin, [Vector2(0, 0), Vector2(10, 0), Vector2(-10, 0)])
	var kill_zone := await _spawn_zone(vortex, _vortex_payload(stats, 10.0), kill_origin)
	await tree.create_timer(0.3).timeout
	kill_bats[1].free()
	var lethal := _vortex_payload(stats, 5000.0)
	var no_vortex: Array[ImpactBurstDefinition] = []
	lethal.impact_bursts = no_vortex # a lethal hit that starts no vortex (a refresh would adopt its damage)
	kill_bats[2].hurtbox_component.take_hit(lethal)
	await tree.create_timer(0.6).timeout
	check(is_instance_valid(kill_zone) and is_instance_valid(kill_bats[0]), "blizzard death: the vortex keeps pulsing after an enemy inside is freed and another is killed (the error guard watches this section)")
	_free_zone(kill_zone)
	var kill_rest: Array[Enemy] = [kill_bats[0]]
	_free_bats(kill_rest)

	# h. The live cap (6) removes the oldest.
	LingeringZone.reset_registry()
	var cap_zones: Array[LingeringZone] = []
	for i in range(8):
		cap_zones.append(await _spawn_zone(vortex, _vortex_payload(stats, 10.0), Vector2(124000.0 + 200.0 * i, 124000.0)))
	await tree.process_frame
	var survivors := 0
	for cap_zone in cap_zones:
		if is_instance_valid(cap_zone) and not cap_zone.is_queued_for_deletion():
			survivors += 1
	check(LingeringZone.get_live_count(&"blizzard_vortex") == 6 and survivors == 6 and not is_instance_valid(cap_zones[0]) and not is_instance_valid(cap_zones[1]) and is_instance_valid(cap_zones[7]), "blizzard cap: eight vortices leave six, the two oldest removed (live %d)" % LingeringZone.get_live_count(&"blizzard_vortex"))
	for cap_zone in cap_zones:
		_free_zone(cap_zone)
	await tree.process_frame

	# i. Magma's zone is unchanged: statuses only, its own interval, speed ignored.
	var lava_zone := (load(LAVA_ZONE_SCENE) as PackedScene).instantiate() as LingeringZone
	var fast_stats := _make_stats({Stat.Type.AOE_RADIUS: 5.0, Stat.Type.SPEED_BONUS: 3.0})
	lava_zone.configure(_vortex_payload(fast_stats, 10.0))
	check(is_zero_approx(lava_zone.damage_fraction) and not lava_zone.scale_interval_with_speed and is_equal_approx(lava_zone._interval, 0.5), "blizzard magma: the lava zone keeps damage_fraction 0, no speed scaling and its 0.5 s interval even with SPEED_BONUS 3")
	lava_zone.free()

	# j. Offers and purchases.
	var frost := load(FROST_CARD) as UpgradeDefinition
	var wind := load(WIND_CARD) as UpgradeDefinition
	var earth := load(EARTH_CARD) as UpgradeDefinition
	var lightning := load(LIGHTNING_CARD) as UpgradeDefinition
	var player := _socket_pair(frost, wind, 3)
	check(mgr._find_next_offer_slot(player) == 1, "blizzard offer: Frost 3 + Wind 3 makes slot 1 offer-eligible")
	var offer := mgr._build_offer_choices(player, 1)
	check(_offer_ids(offer) == ["compound_blizzard_evolve", "compound_blizzard_overclock"], "blizzard offer: exactly Evolve + Blizzard and Overclock + Blizzard, no generic Overclock (got %s)" % str(_offer_ids(offer)))
	var ability := player.ability_container.get_ability_by_slot(1)
	var tags: Array[Tags.Type] = ability.tag_component.get_permanent_tags()
	var ledger := player.run_ledger_component
	player.apply_contextual_upgrade(offer[0])
	check(ledger.purchase_registry.has(PurchaseKey.make("compound_blizzard_evolve", 1)) and not ledger.purchase_registry.has("compound_blizzard_evolve"), "blizzard evolve: logged as a slot-specific purchase")
	check(ledger.get_impact_bursts(1, tags).has(vortex) and not ledger.get_impact_bursts(2, tags).has(vortex) and ledger.get_status_effects(1, tags).has(chill) and not ledger.get_status_effects(2, tags).has(chill) and not ledger.is_overclocked(1), "blizzard evolve: the vortex and Chill resolve for slot 1 only")
	player = _socket_pair(frost, wind, 3)
	ability = player.ability_container.get_ability_by_slot(1)
	tags = ability.tag_component.get_permanent_tags()
	ledger = player.run_ledger_component
	player.apply_contextual_upgrade(offer[1])
	check(ledger.purchase_registry.has(PurchaseKey.make("compound_blizzard_overclock", 1)) and ledger.is_overclocked(1) and ledger.get_impact_bursts(1, tags).has(vortex) and not ledger.get_impact_bursts(2, tags).has(vortex), "blizzard overclock: slot-specific, overclocked, the vortex resolves for slot 1 only")
	check(_offer_ids(mgr._build_offer_choices(_socket_pair(frost, earth, 3), 1)) == ["compound_shatter_evolve", "compound_shatter_overclock"], "blizzard offer: Frost 3 + Earth 3 still offers the Shatter pair")
	check(_offer_ids(mgr._build_offer_choices(_socket_pair(frost, lightning, 3), 1)) == ["compound_superconduct_evolve", "compound_superconduct_overclock"], "blizzard offer: Frost 3 + Lightning 3 still offers the Superconduct pair")
	var shatter_player := _socket_pair(frost, earth, 3)
	shatter_player.apply_contextual_upgrade(mgr._build_offer_choices(shatter_player, 1)[0])
	var shatter_tags: Array[Tags.Type] = shatter_player.ability_container.get_ability_by_slot(1).tag_component.get_permanent_tags()
	check(not shatter_player.run_ledger_component.get_impact_bursts(1, shatter_tags).has(vortex), "blizzard offer: a Shatter slot gets no vortex")
	var leaked := false
	for choice in mgr.generate_selection_pool(player, 99):
		leaked = leaked or choice.definition.is_compound_card()
	for entry in DebugActions.grantable_cards(mgr):
		leaked = leaked or (entry["definition"] as UpgradeDefinition).is_compound_card()
	check(not leaked, "blizzard pool: no compound card appears in level-up drafts or the debug grant list")

	# k. Guards.
	var burst_cards: Array[String] = []
	var vortex_ids: Array[String] = []
	var compound_ids: Array[String] = []
	for path in _list_tres("res://resources"):
		var resource := load(path)
		if resource is UpgradeDefinition and (resource as UpgradeDefinition).impact_burst_payload != null and (resource as UpgradeDefinition).impact_burst_payload.burst_id == &"blizzard_vortex":
			burst_cards.append((resource as UpgradeDefinition).upgrade_id)
		if resource is ImpactBurstDefinition and (resource as ImpactBurstDefinition).effect_scene != null:
			vortex_ids.append(String((resource as ImpactBurstDefinition).burst_id))
		if resource is UpgradeDefinition and (resource as UpgradeDefinition).is_compound_card():
			compound_ids.append((resource as UpgradeDefinition).upgrade_id)
	burst_cards.sort()
	vortex_ids.sort()
	compound_ids.sort()
	check(burst_cards == ["compound_blizzard_evolve", "compound_blizzard_overclock"] and vortex_ids == ["blizzard_vortex", "magma_lava"], "blizzard guard: only the two Blizzard cards carry the vortex, and the only zone bursts are magma_lava and blizzard_vortex (found %s, %s)" % [str(burst_cards), str(vortex_ids)])
	check(compound_ids.size() == 10 and compound_ids.has("compound_blizzard_evolve") and compound_ids.has("compound_blizzard_overclock"), "blizzard guard: ten compound cards ship in total (found %s)" % str(compound_ids))
