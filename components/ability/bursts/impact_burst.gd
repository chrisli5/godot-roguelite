class_name ImpactBurst
extends RefCounted
## Runs impact bursts. Every burst rule lives here, not in the shapes: a burst never crits and never
## triggers another burst, and applies no status unless its definition sets applies_statuses.


## Runs `definition` as a one-shot burst at `origin`. Called deferred from HurtboxComponent.take_hit,
## because take_hit can run inside a physics callback where spatial queries may not be allowed.
## `exclude_instance_id` is the primary target's hurtbox, which a burst never hits.
static func run(
	definition: ImpactBurstDefinition,
	source_payload: CombatPayload,
	origin: Vector2,
	exclude_instance_id: int,
	world: World2D
) -> void:
	if definition == null or source_payload == null or world == null:
		return

	# No shape: an effect-only burst, which only spawns its effect.
	if definition.shape == null:
		_spawn_effect(definition, origin, source_payload)
		return

	# The ability's stats container is the burst's caster context (credit and AOE_RADIUS).
	var stats := instance_from_id(source_payload.stats_container_id) as StatsContainer
	var targets := definition.shape.find_targets(origin, stats, world.direct_space_state, exclude_instance_id)
	if targets.is_empty():
		return

	# Shared payloads are never mutated: duplicate, then replace (not clear) the arrays.
	var burst_payload := source_payload.duplicate() as CombatPayload
	var no_statuses: Array[StatusEffect] = []
	var no_bursts: Array[ImpactBurstDefinition] = []
	burst_payload.final_damage = source_payload.final_damage * _get_damage_multiplier(definition, targets.size())
	burst_payload.is_critical_hit = false
	if not definition.applies_statuses:
		burst_payload.status_effects_to_apply = no_statuses
	burst_payload.impact_bursts = no_bursts
	burst_payload.is_burst = true

	for hurtbox in targets:
		if is_instance_valid(hurtbox):
			hurtbox.take_hit(burst_payload)

	_spawn_effect(definition, origin, source_payload)


## damage_fraction * (1 + min(per_enemy_bonus * enemies caught, per_enemy_bonus_cap)).
static func _get_damage_multiplier(definition: ImpactBurstDefinition, targets_caught: int) -> float:
	var bonus := minf(definition.per_enemy_bonus * targets_caught, definition.per_enemy_bonus_cap)
	return definition.damage_fraction * (1.0 + bonus)


static func _spawn_effect(definition: ImpactBurstDefinition, origin: Vector2, source_payload: CombatPayload) -> void:
	if definition.effect_scene == null:
		return
	var effect := definition.effect_scene.instantiate() as Node2D
	if effect == null:
		return
	# A BurstEffect gets its own copy of the cast's payload before it enters the tree.
	if effect is BurstEffect:
		(effect as BurstEffect).configure(source_payload.duplicate() as CombatPayload)
	var tree := Engine.get_main_loop() as SceneTree
	var host: Node = tree.current_scene if is_instance_valid(tree.current_scene) else tree.root
	host.add_child(effect)
	effect.global_position = origin
