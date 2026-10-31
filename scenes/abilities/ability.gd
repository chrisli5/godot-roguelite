# res://scenes/abilities/ability.gd
class_name Ability
extends Node2D

@export_group("Components")
@export var stats_container: StatsContainer
@export var infusion_tracker_component: InfusionTrackerComponent
@export var evolution_gate_component: EvolutionGateComponent
@export var tag_component: TagComponent
@export var spatial_query_component: SpatialQueryComponent

var data: AbilityData = null

# Live execution strategy handles
var deployment_anchor: DeploymentAnchor = null
var geometry_driver: GeometryDriver = null
var payload_driver: PayloadDriver = null

var character_caster: Node2D = null
var is_eligible_for_overclock: bool = false
var _cooldown_timer: Timer
## Seconds refunded while the cooldown timer was stopped (delivery in progress); taken off the next cooldown.
var _pending_refund: float = 0.0

## A refund never leaves less than this on the timer. Timer.start(0) would keep the previous wait_time instead.
const MIN_REMAINING: float = 0.05

var display_name: String:
	get:
		return data.display_name if is_instance_valid(data) else "ABILITY_DISPLAY_NAME"


func _ready() -> void:
	# Cleaned completely of legacy local ledger component checks!
	var required_ability_components: Array[String] = [
		"stats_container",
		"infusion_tracker_component",
		"evolution_gate_component",
		"tag_component",
		"spatial_query_component"
	]
	
	if not ComponentValidator.validate_components(self, required_ability_components):
		set_physics_process(false)
		return
	
	_setup_cooldown_clock()
	if is_instance_valid(stats_container):
		stats_container.stat_updated.connect(_on_stat_updated)


func initialize_caster_context(caster_node: Node2D) -> void:
	character_caster = caster_node


func _trigger_ability_delivery() -> void:
	if not is_instance_valid(geometry_driver) or not is_instance_valid(character_caster):
		_start_cooldown_phase()
		return
		
	var running_payload := CombatCalculations.generate_hit_payload(character_caster, stats_container, tag_component)
	if is_instance_valid(data) and data.texture_prefab is Texture2D:
		running_payload.base_texture = data.texture_prefab
	# The connection ends with this node: Godot disconnects a signal from a freed Callable target.
	running_payload.cast_events.cooldown_refunded.connect(_on_cooldown_refunded)

	if is_instance_valid(payload_driver):
		payload_driver.intercept_payload(running_payload)

	# 1. Resolve where this ability initiates from space coordinates
	var spawn_pos := deployment_anchor.get_anchor_position(character_caster)

	# 2. Polymorphically extract the precise shape required directly from the geometry driver
	var custom_shape := geometry_driver.get_query_shape(stats_container)

	# 3. Fire the unified query pass (SpatialQueryDriver handles ALL physics queries)
	var query_results := spatial_query_component.execute_spatial_query(spawn_pos, custom_shape)

	# 4. Hand off the pre-sorted physics dataset cleanly to the geometry layer
	geometry_driver.execute_geometry(query_results, running_payload)


func swap_runtime_strategies(new_data: AbilityData) -> void:
	if not is_instance_valid(new_data): 
		return
	data = new_data

	# AbilityData.structural_tags is the source of truth for this ability's base (identity) tags.
	if new_data.structural_tags.is_empty():
		push_warning("Ability '%s': structural_tags is empty, base tags were left unchanged." % new_data.display_name)
	elif is_instance_valid(tag_component):
		tag_component.set_base_tags(new_data.structural_tags)

	# Wiped out local ledger initialization blocks completely!
	spatial_query_component.reset_to_defaults()
	
	if new_data.custom_sort_rule_script:
		var custom_rule_instance = new_data.custom_sort_rule_script.new()
		if custom_rule_instance.has_method("get_sort_callable"):
			spatial_query_component.active_sort_rule = custom_rule_instance.get_sort_callable()

	# Free highly volatile visual/mechanical strategy nodes
	for driver in [geometry_driver, payload_driver, deployment_anchor]:
		if is_instance_valid(driver): 
			driver.queue_free()
			
	geometry_driver = null
	payload_driver = null
	deployment_anchor = null

	# Instantiate the Deployment Anchor Strategy
	if is_instance_valid(data.deployment_anchor_scene):
		var anchor_inst = data.deployment_anchor_scene.instantiate()
		if anchor_inst is DeploymentAnchor:
			add_child(anchor_inst)
			deployment_anchor = anchor_inst
			
	if not is_instance_valid(deployment_anchor):
		deployment_anchor = CasterPositionAnchor.new()
		add_child(deployment_anchor)

	# Instantiate the Geometry Driver Strategy
	if is_instance_valid(data.geometry_driver_scene):
		var geom_inst = data.geometry_driver_scene.instantiate()
		if geom_inst is GeometryDriver:
			add_child(geom_inst)
			geometry_driver = geom_inst
			geometry_driver.delivery_finished.connect(_on_delivery_finished)

	# Instantiate the Payload Driver Strategy
	if is_instance_valid(data.payload_driver_scene):
		var payload_inst = data.payload_driver_scene.instantiate()
		if payload_inst is PayloadDriver:
			add_child(payload_inst)
			payload_driver = payload_inst

	
	if data.stats_profile and is_instance_valid(stats_container):
		stats_container.mutate_base_profile(data.stats_profile)

	# Changed base tags can switch tag-scoped (GLOBAL_TAG_MATCH) upgrades on or off.
	if is_instance_valid(stats_container):
		stats_container.invalidate_all_caches()

	if data.slot_index >= AbilityContainer.MIN_SLOT:
		EventBus.ability_modification_completed.emit(data.slot_index)
			
	_start_cooldown_phase()


## Called after the ledger has recorded a socket for this slot. The ledger holds the infusion level,
## so nothing is stored here; this only refreshes the stats that depend on it.
func apply_infusion_socket(element_tag: Tags.Type, _upgrade_id: String) -> void:
	print("[SOCKET] %s successfully registered inside local module layers." % Tags.Type.keys()[element_tag])
	
	# Force an immediate stat calculation update pass right now since tags changed
	if is_instance_valid(stats_container):
		stats_container.get_final_stat_value(Stat.Type.BASE_DAMAGE)


func _setup_cooldown_clock() -> void:
	_cooldown_timer = Timer.new()
	_cooldown_timer.one_shot = true 
	_cooldown_timer.timeout.connect(_trigger_ability_delivery)
	add_child(_cooldown_timer)
	_start_cooldown_phase()


func _start_cooldown_phase() -> void:
	var downtime: float = 4.0
	if is_instance_valid(stats_container):
		downtime = StatBonus.cooldown(stats_container)
	if _pending_refund > 0.0:
		downtime = minf(downtime, maxf(downtime - _pending_refund, MIN_REMAINING))
		_pending_refund = 0.0
	_cooldown_timer.start(downtime)


## Shortens the running cooldown by `seconds` (never below MIN_REMAINING). With the timer stopped (delivery still in
## progress) the refund is held and taken off the next cooldown instead.
func _on_cooldown_refunded(seconds: float) -> void:
	if seconds <= 0.0 or not is_instance_valid(_cooldown_timer):
		return
	if _cooldown_timer.is_stopped() or _cooldown_timer.time_left <= 0.0:
		_pending_refund += seconds
		return
	# Nothing left to take off: a refund must never lengthen the cooldown.
	if _cooldown_timer.time_left <= MIN_REMAINING:
		return
	# start() also sets wait_time to this value; the next _start_cooldown_phase restores the full stat value.
	_cooldown_timer.start(maxf(_cooldown_timer.time_left - seconds, MIN_REMAINING))


func _on_delivery_finished() -> void:
	_start_cooldown_phase()


func _on_stat_updated(stat_type: Stat.Type, new_value: float) -> void:
	if (stat_type == Stat.Type.COOLDOWN or stat_type == Stat.Type.COOLDOWN_BONUS) and is_instance_valid(_cooldown_timer):
		var cooldown: float = StatBonus.cooldown(stats_container)
		if cooldown > 0.0:
			_cooldown_timer.wait_time = cooldown


## Runtime state that cannot be rebuilt from AbilityData or the run ledger.
func export_runtime_state() -> Dictionary:
	var snapshot: Dictionary = {}
	if is_instance_valid(evolution_gate_component):
		snapshot["evolution_state"] = evolution_gate_component.current_state
	return snapshot


## Call after the ability has been mounted from its saved AbilityData.
func import_runtime_state(snapshot: Dictionary) -> void:
	if is_instance_valid(evolution_gate_component) and snapshot.has("evolution_state"):
		evolution_gate_component.restore_state(snapshot["evolution_state"])
