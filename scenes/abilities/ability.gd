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
		
	# Gather our active taxonomy tags to pass down through the layered calculation layers
	var active_tags := tag_component.get_active_tags() if is_instance_valid(tag_component) else []
		
	var running_payload := CombatCalculations.generate_hit_payload(character_caster, stats_container, tag_component)
	if is_instance_valid(data) and data.texture_prefab is Texture2D:
		running_payload.base_texture = data.texture_prefab

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

	_sync_ability_tags()
	
	if data.stats_profile and is_instance_valid(stats_container):
		stats_container.mutate_base_profile(data.stats_profile)

	if is_instance_valid(evolution_gate_component) and data.is_overclock_evolution:
		evolution_gate_component.is_permanently_overclocked = true
	
	if data.slot_index:
		EventBus.ability_modification_completed.emit(data.slot_index)
			
	_start_cooldown_phase()


func apply_infusion_socket(element_tag: Tags.Type, _upgrade_id: String) -> void:
	if is_instance_valid(tag_component):
		tag_component.add_tag(element_tag)
		tag_component.add_tag(Tags.Type.INFUSION)

	if is_instance_valid(infusion_tracker_component):
		infusion_tracker_component.record_socket_transaction(element_tag)

	print("[SOCKET] %s successfully registered inside local module layers." % Tags.Type.keys()[element_tag])
	
	# Force an immediate stat calculation update pass right now since tags changed
	if is_instance_valid(stats_container) and is_instance_valid(tag_component):
		stats_container.get_final_stat_value(Stat.Type.BASE_DAMAGE, tag_component.get_active_tags())


func _sync_ability_tags() -> void:
	if not is_instance_valid(tag_component): 
		return
	var preserved_infusions: Array[Tags.Type] = []
	for tag in tag_component.get_active_tags():
		if Tags.get_index_from_element(tag) >= 0:
			preserved_infusions.append(tag)
			
	tag_component._active_tags.clear()
	for tag in preserved_infusions: 
		tag_component.add_tag(tag)
	for tag in data.structural_tags: 
		tag_component.add_tag(tag)
		
	tag_component.tags_changed.emit(tag_component._active_tags)


func _setup_cooldown_clock() -> void:
	_cooldown_timer = Timer.new()
	_cooldown_timer.one_shot = true 
	_cooldown_timer.timeout.connect(_trigger_ability_delivery)
	add_child(_cooldown_timer)
	_start_cooldown_phase()


func _start_cooldown_phase() -> void:
	var downtime: float = 4.0
	if is_instance_valid(stats_container) and is_instance_valid(tag_component):
		downtime = stats_container.get_final_stat_value(Stat.Type.COOLDOWN, tag_component.get_active_tags())
	_cooldown_timer.start(downtime)


func _on_delivery_finished() -> void:
	_start_cooldown_phase()


func _on_stat_updated(stat_type: Stat.Type, new_value: float) -> void:
	if stat_type == Stat.Type.COOLDOWN and is_instance_valid(_cooldown_timer):
		_cooldown_timer.wait_time = new_value
