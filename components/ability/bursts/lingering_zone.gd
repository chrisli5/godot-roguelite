class_name LingeringZone
extends BurstEffect
## A timed area spawned by an effect-only impact burst. While it lives it re-applies the cast's statuses,
## with the cast's snapshots and no direct damage, to every enemy inside it. A new zone near a live zone
## with the same zone_id refreshes that zone instead of spawning another, and each zone_id has a live cap.

## Zones with the same id share the merge rule and the live cap. Set a unique id per zone type.
@export var zone_id: StringName = &""
## Seconds the zone lives after it spawns or is refreshed.
@export var lifetime: float = 4.0
## Seconds between applications. The first application happens on the zone's first physics frame.
@export var apply_interval: float = 0.5
## Zone radius = the cast's AOE_RADIUS times this.
@export var radius_multiplier: float = 1.0
## A new zone this close to a live zone of the same zone_id refreshes it instead of spawning.
@export var merge_distance: float = 40.0
## At most this many live zones per zone_id; the oldest is removed first.
@export var max_live_zones: int = 8
@export_group("Physics Hardware Configuration")
@export_flags_2d_physics var enemy_collision_mask: int = 4
@export var max_results_buffer: int = 32
@export_group("Placeholder Visual")
@export var zone_color: Color = Color(1.0, 0.45, 0.1, 0.35)

## Live zones per zone_id, oldest first.
static var _registry: Dictionary[StringName, Array] = {}

var _payload: CombatPayload = null
var _radius: float = 0.0
var _shape: CircleShape2D = null
var _remaining: float = 0.0
var _apply_timer: float = 0.0
var _discarded: bool = false


## Empties the registry. For tests.
static func reset_registry() -> void:
	_registry.clear()


## Number of live zones registered under `id`. For tests.
static func get_live_count(id: StringName) -> int:
	var zones: Array = _registry.get(id, [])
	return zones.size()


func configure(source_payload: CombatPayload) -> void:
	_payload = source_payload
	var stats := instance_from_id(source_payload.stats_container_id) as StatsContainer
	if is_instance_valid(stats):
		_radius = StatBonus.reach(stats, Stat.Type.AOE_RADIUS) * radius_multiplier
	if _radius > 0.0:
		_shape = CircleShape2D.new()
		_shape.radius = _radius
	queue_redraw()


func _ready() -> void:
	_remaining = lifetime
	# Apply on the first physics frame, then every apply_interval.
	_apply_timer = apply_interval
	# The spawner positions the node after add_child, so merge and register one step later.
	_register_or_merge.call_deferred()


## Resets the remaining lifetime and adopts the newer payload copy (the latest applier wins, like statuses).
func refresh(new_payload: CombatPayload) -> void:
	_remaining = lifetime
	_payload = new_payload


func _exit_tree() -> void:
	_unregister()


func _physics_process(delta: float) -> void:
	if _discarded:
		return
	_remaining -= delta
	if _remaining <= 0.0:
		queue_free()
		return
	_apply_timer += delta
	if _apply_timer >= apply_interval:
		_apply_timer = fmod(_apply_timer, maxf(apply_interval, 0.001))
		_apply_statuses()


func _draw() -> void:
	if _radius > 0.0:
		draw_circle(Vector2.ZERO, _radius, zone_color)


func _register_or_merge() -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	var zones: Array = _registry.get(zone_id, [])
	var nearest: LingeringZone = null
	var nearest_distance := merge_distance
	for entry in zones:
		var other := entry as LingeringZone
		if not is_instance_valid(other) or other.is_queued_for_deletion():
			continue
		var distance := other.global_position.distance_to(global_position)
		if distance <= nearest_distance:
			nearest = other
			nearest_distance = distance
	if nearest != null:
		nearest.refresh(_payload)
		_discarded = true
		set_physics_process(false)
		hide()
		queue_free()
		return

	zones.append(self)
	_registry[zone_id] = zones
	while zones.size() > maxi(max_live_zones, 1):
		var oldest := zones.pop_front() as LingeringZone
		if is_instance_valid(oldest):
			oldest.queue_free()


func _unregister() -> void:
	var zones: Array = _registry.get(zone_id, [])
	zones.erase(self)
	if zones.is_empty():
		_registry.erase(zone_id)


func _apply_statuses() -> void:
	if _shape == null or _payload == null or _payload.status_effects_to_apply.is_empty():
		return
	var intersections := SpatialQuery.query_shape_intersections(
		get_world_2d().direct_space_state, _shape, global_position, enemy_collision_mask, max_results_buffer
	)
	var zone_hit: CombatPayload = null
	for result in intersections:
		var hurtbox := result.get("collider") as HurtboxComponent
		if hurtbox == null or hurtbox.is_player_hurtbox:
			continue
		# One shared copy for every target: statuses and snapshots kept, no damage.
		if zone_hit == null:
			zone_hit = _payload.duplicate() as CombatPayload
			zone_hit.final_damage = 0.0
		hurtbox.take_hit(zone_hit)
