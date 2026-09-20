class_name Ability
extends Node2D

@export_group("Components")
@export var stats_container: StatsContainer
@export var upgrade_ledger_component: UpgradeLedgerComponent
@export var infusion_tracker_component: InfusionTrackerComponent
@export var evolution_gate_component: EvolutionGateComponent
@export var tag_component: TagComponent

## Reference to the active child element handling shape boundaries and targeting
var geometry_driver: GeometryDriver = null:
	set(value):
		# Clean disconnect loops when hot-swapping strategy modules mid-run
		if is_instance_valid(geometry_driver) and geometry_driver.delivery_finished.is_connected(_on_delivery_finished):
			geometry_driver.delivery_finished.disconnect(_on_delivery_finished)
		geometry_driver = value
		if is_instance_valid(geometry_driver):
			geometry_driver.delivery_finished.connect(_on_delivery_finished)

var payload_driver: PayloadDriver = null
var targeting_strategy: TargetingStrategy = null

var display_name: String = ""
var is_eligible_for_overclock: bool = false
var _cooldown_timer: Timer


func _ready() -> void:
	var required_ability_components: Array[String] = [
		"stats_container",
		"upgrade_ledger_component",
		"infusion_tracker_component",
		"evolution_gate_component",
		"tag_component"
	]
	
	if not ComponentValidator.validate_components(self, required_ability_components):
		set_physics_process(false)
		return
	
	_setup_cooldown_clock()
	if is_instance_valid(stats_container):
		stats_container.stat_updated.connect(_on_stat_updated)


func compile_eligible_pool(player_character_level: int) -> void:
	if not is_instance_valid(upgrade_ledger_component):
		return
		
	var compiled_upgrades: Array[UpgradeTracker] = []
	var compiled_evolutions: Array[UpgradeTracker] = []
	
	var raw_evo_blueprints: Array[UpgradeTracker] = upgrade_ledger_component.available_evolutions
	var active_tags: Array[Tags.Type] = tag_component.get_active_tags() if is_instance_valid(tag_component) else []
	
	# Reset the state flag before evaluating the current frame pass
	is_eligible_for_overclock = false

	# --- PHASE 1: EVALUATE STRUCTURAL RECIPES THROUGH THE EVO ENGINE ---
	if is_instance_valid(evolution_gate_component) and is_instance_valid(infusion_tracker_component):
		# SYNCED PASS: Evaluates hand-crafted recipes passing the type-safe integer array directly
		compiled_evolutions = evolution_gate_component.evaluate_evolution_recipes(
			raw_evo_blueprints, 
			infusion_tracker_component.infusion_levels, 
			active_tags
		)
		
		# --- DATA-DRIVEN OVERCLOCK ELIGIBILITY STATE AUDIT ---
		# Determine if the weapon's socket arrays have collectively arrived at a soft cap ceiling
		var active_sockets: int = 0
		var capped_elements: int = 0
		var soft_cap_target = 3 if evolution_gate_component.current_state == EvolutionGateComponent.EvolutionState.TIER_1_BASE else 5
		
		for level in infusion_tracker_component.infusion_levels:
			if level > 0:
				active_sockets += 1
				if level >= soft_cap_target:
					capped_elements += 1
					
		var is_at_soft_cap = (active_sockets >= 2 and capped_elements >= 2) if evolution_gate_component.current_state == EvolutionGateComponent.EvolutionState.TIER_1_BASE else (active_sockets >= 3 and capped_elements >= 3)
		
		# Expose the boolean state flag; if true, the UpgradeManager injects the disk-based Overclock tracker
		if is_at_soft_cap and not evolution_gate_component.is_permanently_overclocked:
			is_eligible_for_overclock = true
			
			# Pull the persistent Overclock variant scene swap tracker straight from disk storage configurations
			var ovr_track = upgrade_ledger_component.overclock_tracker
			if is_instance_valid(ovr_track) and ovr_track.current_purchases < ovr_track.max_purchases:
				compiled_evolutions.append(ovr_track)
		
	# --- PHASE 2: COMPILE LINEAR WEAPON STAT MODIFIERS ---
	for tracker in upgrade_ledger_component.available_upgrades:
		var definition = tracker.definition
		if not is_instance_valid(definition) or tracker.current_purchases >= tracker.max_purchases: 
			continue
		
		# Dynamic level step gating calculation pass (Single Value Scaling integration)
		var dynamic_req_level = tracker.required_character_level + (tracker.current_purchases * 2)
		if player_character_level < dynamic_req_level: 
			continue
			
		# Synchronize card text tier number display properties smoothly (e.g., Cooldown Rate III)
		tracker.tier_index = tracker.current_purchases + 1
		compiled_upgrades.append(tracker)

	# --- PHASE 3: WRITE BACK TO THE LOCAL VIEW CACHE REGISTERS ---
	upgrade_ledger_component.clear_caches()
	upgrade_ledger_component.overwrite_cached_pools(compiled_upgrades, compiled_evolutions)


func apply_evolution_mutation(_choice: UpgradeChoice) -> void:
	if is_instance_valid(evolution_gate_component):
		evolution_gate_component.advance_evolution_state()


func apply_infusion_socket(element_tag: Tags.Type, _upgrade_id: String) -> void:
	# 1. Update strict identity categorization rules safely via tag component
	if is_instance_valid(tag_component):
		tag_component.add_tag(element_tag)
		tag_component.add_tag(Tags.Type.INFUSION)

	# 2. Directly instruct the independent module to record progress levels string-free
	if is_instance_valid(infusion_tracker_component):
		infusion_tracker_component.record_socket_transaction(element_tag)

	print("[SOCKET] %s successfully registered inside local module layers." % Tags.Type.keys()[element_tag])

func _setup_cooldown_clock() -> void:
	_cooldown_timer = Timer.new()
	_cooldown_timer.one_shot = true # Enforce single-fire ticking
	_cooldown_timer.timeout.connect(_trigger_ability_delivery)
	add_child(_cooldown_timer)
	_start_cooldown_phase()


func _start_cooldown_phase() -> void:
	var downtime: float = 4.0
	if is_instance_valid(stats_container):
		downtime = stats_container.get_stat_value(Stat.Type.COOLDOWN, 4.0)
	_cooldown_timer.start(downtime)


## Centralized Execution Loop: Handles all Parent-Mediated parameter gathering
func _trigger_ability_delivery() -> void:
	if not is_instance_valid(geometry_driver):
		_start_cooldown_phase()
		return

	var direction := Vector2.RIGHT
	var tracked_enemy: Node2D = null
	
	if is_instance_valid(targeting_strategy):
		var target_package := targeting_strategy.get_targeting_data(global_position)
		direction = target_package.get("direction", Vector2.RIGHT)
		tracked_enemy = target_package.get("target_node", null)

	var speed := stats_container.get_stat_value(Stat.Type.SPEED, 400.0) if stats_container else 400.0
	var aoe_scale := stats_container.get_stat_value(Stat.Type.ACCELERATION, 1.0) if stats_container else 1.0
	var running_payload := CombatCalculations.generate_hit_payload(owner, stats_container, tag_component)

	# If a straight projectile driver receives this, it uses 'direction' and ignores the node.
	# If a homing projectile spawner receives this, it extracts the node to track it in real-time.
	running_payload.tracked_target_node = tracked_enemy

	if is_instance_valid(payload_driver) and payload_driver.has_method("intercept_payload"):
		payload_driver.intercept_payload(running_payload)

	geometry_driver.execute_delivery(global_position, direction, speed, aoe_scale, running_payload)


func swap_runtime_strategies(new_data: AbilityData) -> void:
	# --- 1. UNIFORM DRIVER HOT-SWAP ---
	if is_instance_valid(geometry_driver):
		geometry_driver.queue_free()
		geometry_driver = null
		
	if is_instance_valid(payload_driver):
		payload_driver.queue_free()
		payload_driver = null

	if is_instance_valid(targeting_strategy):
		targeting_strategy.queue_free()
		targeting_strategy = null

	if is_instance_valid(new_data.geometry_driver_scene):
		var geom_inst = new_data.geometry_driver_scene.instantiate()
		if geom_inst:
			add_child(geom_inst)
			geometry_driver = geom_inst

	if is_instance_valid(new_data.payload_driver_scene):
		var payload_inst = new_data.payload_driver_scene.instantiate()
		if payload_inst:
			add_child(payload_inst)
			payload_driver = payload_inst

	if is_instance_valid(new_data.targeting_strategy_scene):
		var target_inst = new_data.targeting_strategy_scene.instantiate()
		add_child(target_inst)
		targeting_strategy = target_inst

	# --- 2. UNIFORM TAXONOMY OVERWRITE ---
	if is_instance_valid(tag_component):
		var current_tags: Array[Tags.Type] = tag_component.get_active_tags()
		var preserved_infusions: Array[Tags.Type] = []
		
		for tag in current_tags:
			if Tags.get_index_from_element(tag) >= 0:
				preserved_infusions.append(tag)
				
		tag_component._active_tags.clear()
		for tag in preserved_infusions:
			tag_component.add_tag(tag)
		for tag in new_data.structural_tags:
			tag_component.add_tag(tag)
			
		tag_component.tags_changed.emit(tag_component._active_tags)

	# --- 3. UNIFORM STAT OVERWRITE / MUTATION ---
	# If the evolution asset includes an updated stats profile (common for Overclocks),
	# we pass it down to re-initialize or augment base values smoothly.
	if new_data.stats_profile and is_instance_valid(stats_container):
		stats_container.mutate_base_profile(new_data.stats_profile)

	# --- 4. UNIFORM OVERCLOCK FLAG GATING ---
	# The EvolutionGateComponent evaluates state automatically using the data flag
	if is_instance_valid(evolution_gate_component):
		if new_data.is_overclock_evolution:
			evolution_gate_component.is_permanently_overclocked = true
	_start_cooldown_phase()


func _on_delivery_finished() -> void:
	# Hand-off received! Safely return to recovery frames
	_start_cooldown_phase()


func _on_stat_updated(stat_type: Stat.Type, new_value: float) -> void:
	if stat_type == Stat.Type.COOLDOWN and is_instance_valid(_cooldown_timer):
		_cooldown_timer.wait_time = new_value
