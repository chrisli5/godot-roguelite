class_name LingeringZone
extends BurstEffect
## A timed area spawned by an effect-only impact burst. While it lives, each pulse re-applies the cast's statuses,
## with the cast's snapshots, to every enemy inside it, and deals damage_fraction of the cast payload's final damage
## (0 = no direct damage, as for Magma). A new zone near a live zone
## with the same zone_id refreshes that zone instead of spawning another, and each zone_id has a live cap.

## Zones with the same id share the merge rule and the live cap. Set a unique id per zone type.
@export var zone_id: StringName = &""
## Seconds the zone lives after it spawns or is refreshed.
@export var lifetime: float = 4.0
## Seconds between pulses. The first pulse happens on the zone's first physics frame.
@export var apply_interval: float = 0.5
## When true, the pulse interval is apply_interval / (1 + SPEED_BONUS) of the cast's stats (minimum MIN_INTERVAL).
@export var scale_interval_with_speed: bool = false
## Hit damage each pulse deals to every enemy inside, as a fraction of the cast payload's final damage. 0 = statuses only.
@export var damage_fraction: float = 0.0
## Zone radius = the cast's AOE_RADIUS times this.
@export var radius_multiplier: float = 1.0
## A new zone this close to a live zone of the same zone_id refreshes it instead of spawning.
@export var merge_distance: float = 40.0
## At most this many live zones per zone_id; the oldest is removed first.
@export var max_live_zones: int = 8
@export_group("Placeholder Visual")
@export var zone_color: Color = Color(1.0, 0.45, 0.1, 0.35)

## Shortest pulse interval a speed-scaled zone may have.
const MIN_INTERVAL: float = 0.05

## Live zones per zone_id, oldest first.
static var _registry: Dictionary[StringName, Array] = {}

var _payload: CombatPayload = null
var _radius: float = 0.0
var _shape: CircleShape2D = null
var _remaining: float = 0.0
var _apply_timer: float = 0.0
## Seconds between pulses; set by configure, or from apply_interval in _ready when never configured.
var _interval: float = -1.0
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
	_interval = apply_interval
	if scale_interval_with_speed:
		_interval = maxf(StatBonus.interval(stats, apply_interval), MIN_INTERVAL)
	if _radius > 0.0:
		_shape = CircleShape2D.new()
		_shape.radius = _radius
	queue_redraw()


func _ready() -> void:
	_remaining = lifetime
	# Pulse on the first physics frame, then every interval.
	if _interval < 0.0:
		_interval = apply_interval
	_apply_timer = _interval
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
	if _apply_timer >= _interval:
		_apply_timer = fmod(_apply_timer, maxf(_interval, 0.001))
		_pulse()


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


## One pulse: every enemy inside takes the cast's statuses and damage_fraction of its final damage.
func _pulse() -> void:
	if _shape == null or _payload == null:
		return
	if _payload.status_effects_to_apply.is_empty() and damage_fraction <= 0.0:
		return
	var zone_hit: CombatPayload = null
	for hurtbox in SpatialQuery.query_enemy_hurtboxes(get_world_2d().direct_space_state, _shape, global_position):
		# One shared copy for every target: statuses and snapshots kept, damage_fraction of the hit's damage (0 for none).
		if zone_hit == null:
			zone_hit = _payload.duplicate() as CombatPayload
			zone_hit.final_damage = _payload.final_damage * damage_fraction
		hurtbox.take_hit(zone_hit)
