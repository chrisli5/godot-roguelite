class_name PersistentGeometry
extends GeometryDriver

## Internal Memory Caches
var _duration_left: float = 0.0
var _active_payload: CombatPayload = null
var _cached_caster: Node2D = null
var _is_active: bool = false


func _ready() -> void:
	# Keep the physics processing thread completely asleep until the spell is explicitly cast
	set_physics_process(false)


## Rule 1: Persistent spells manage their own lifecycles, so they skip the initial circular query
func get_query_shape(_stats: StatsContainer) -> Shape2D:
	return null


## The Unified Initialization Engine (Inherited by all child classes)
func execute_geometry(query_results: Dictionary, final_payload: CombatPayload) -> void:
	_terminate_persistent_delivery()
	
	_active_payload = final_payload
	if not is_instance_valid(_active_payload):
		delivery_finished.emit()
		return

	# Extract standard caster context out of the memory stream
	_cached_caster = instance_from_id(_active_payload.caster_instance_id) as Node2D
	if not is_instance_valid(_cached_caster):
		_terminate_persistent_delivery()
		return

	# Dynamically extract duration lengths directly from current active runtime stats
	var stats = instance_from_id(_active_payload.stats_container_id)
	var has_stats := is_instance_valid(stats)
	_duration_left = stats.get_final_stat_value(Stat.Type.DURATION) if has_stats else 1.0
	
	# Extract the launch point resolved by the DeploymentAnchor
	var spawn_origin: Vector2 = query_results.get("origin", Vector2.ZERO)

	# Invoke virtual setup hook for custom child logic (e.g., spawning physical nodes)
	_on_persistent_started(spawn_origin, query_results)
	
	_is_active = true
	set_physics_process(true)


## The Continuous Processing Tick Loop
func _physics_process(delta: float) -> void:
	if not _is_active:
		return
		
	_duration_left -= delta
	
	# Safety Fail-Safe: If the timer runs out or the player dies, immediately self-destruct
	if _duration_left <= 0.0 or not is_instance_valid(_cached_caster):
		_terminate_persistent_delivery()
		return

	# Invoke virtual update hook for child classes
	_update_persistent_step(delta)


## The Unified Cleanup Engine (Ensures zero memory leaks)
func _terminate_persistent_delivery() -> void:
	set_physics_process(false)
	_is_active = false
	
	# Invoke virtual cleanup hook so children can safely queue_free their specific spawned sub-nodes
	_on_persistent_terminated()
	
	_active_payload = null
	_cached_caster = null
	delivery_finished.emit()


# =============================================================================
# VIRTUAL HOOKS (Intended to be overridden by child classes)
# =============================================================================

## Called exactly once on the frame the spell initiates. Use this to spawn child sub-nodes.
func _on_persistent_started(_spawn_origin: Vector2, _query_results: Dictionary) -> void:
	pass

## Called on every single physics tick frame while the spell is active. Use this for delta math.
func _update_persistent_step(_delta: float) -> void:
	pass

## Called exactly once when the spell expires. Use this to safely queue_free remaining objects.
func _on_persistent_terminated() -> void:
	pass
