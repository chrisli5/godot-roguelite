class_name Player
extends Entity

@export_group("Components")
@export var collector_component: CollectorComponent
@export var progression_component: ProgressionComponent
@export var run_ledger_component: RunLedgerComponent

var player_data: PlayerData:
	get:
		return entity_data as PlayerData


func _ready() -> void:
	super()
	var required_player_components: Array[String] = [
		"collector_component",
		"progression_component",
		"ability_container",
		"stats_container",
		"health_component",
		"hurtbox_component",
		"run_ledger_component",
		"status_effect_component",
		"tag_component",
		"sprite_node",
	]
	
	if not ComponentValidator.validate_components(self, required_player_components):
		set_physics_process(false)
		return
		
	# Synchronize our core stats container context as Slot 0 (Character Core)
	if is_instance_valid(stats_container):
		stats_container.configure_slot_context(0)
	
	collector_component.payload_collected.connect(_on_payload_collected)
	
	# Pre-load initial player starting blueprints directly into the central run ledger
	if is_instance_valid(player_data) and player_data.player_core_blueprints:
		for profile in player_data.player_core_blueprints:
			if is_instance_valid(profile) and profile.definition_bundle:
				for definition in profile.definition_bundle:
					# Seed baseline upgrades as Tier 0 or unlock them based on starting rules
					pass
					
	EventBus.player_spawned.emit(get_instance_id())


func _physics_process(_delta: float) -> void:
	_handle_movement_physics()


func _exit_tree() -> void:
	EventBus.player_despawned.emit()


func _handle_movement_physics() -> void:
	if not movement_strategy or not is_instance_valid(stats_container):
		return
	
	# Progression Layered Call: Grabs baseline speed and wraps transient debuffs (like chills) on top
	var max_speed = stats_container.get_final_stat_value(Stat.Type.MOVEMENT_SPEED)
	var direction := Vector2.ZERO
	direction.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	direction.y = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	
	var target_velocity := direction.normalized()
	velocity = movement_strategy.calculate_velocity(velocity, target_velocity, max_speed, global_position, 0.0)
	move_and_slide()


func apply_contextual_upgrade(choice: UpgradeChoice) -> void:
	var definition = choice.definition
	if not is_instance_valid(definition): 
		return
		
	# --- INTELLIGENT OVERLOAD ROUTING PASS ---
	if choice.is_infusion and choice.target_slot_index > 0:
		# Scenario A: Player-allocated elemental socket card.
		# We dynamically bake the chosen slot index straight into the tracking registry key.
		run_ledger_component.log_slot_specific_purchase(definition, choice.target_slot_index)
		
		# Force a manual recalculation pass on the chosen weapon lane immediately
		var targeted_weapon = ability_container.get_ability_by_slot(choice.target_slot_index)
		if is_instance_valid(targeted_weapon):
			targeted_weapon.apply_infusion_socket(choice.infusion_element, definition.upgrade_id)
			
		print("[CENTRAL LEDGER LOGGED] Dynamic Infusion allocated to Slot %d for upgrade: %s" % [
			choice.target_slot_index, 
			definition.display_name
		])
	else:
		# Scenario B: Standard hard-coded scope cards (Core, Global Passives, Pre-Restricted Slots)
		run_ledger_component.log_purchase(definition)
		print("[CENTRAL LEDGER LOGGED] Standard upgrade logged: %s | Active Tier: %d" % [
			definition.display_name, 
			run_ledger_component.purchase_registry[definition.upgrade_id]
		])

	# 2. Execute downstream structural unlocks/mutations contextually
	match definition.payload_type:
		UpgradeDefinition.PayloadType.ABILITY_UNLOCK:
			_process_structural_ability_unlock(choice)
		UpgradeDefinition.PayloadType.STAT_MODIFIER:
			if definition.scope == UpgradeDefinition.ScopeType.CHARACTER_CORE:
				if is_instance_valid(definition.stat_modifier_payload):
					stats_container.get_final_stat_value(definition.stat_modifier_payload.target_stat_type)


func _process_structural_ability_unlock(choice: UpgradeChoice) -> void:
	var definition = choice.definition
	if not is_instance_valid(ability_container) or not is_instance_valid(definition.ability_data_payload):
		return
		
	var target_slot_idx: int = definition.ability_data_payload.slot_index
	var existing_ability = ability_container.get_ability_by_slot(target_slot_idx)
	
	if not is_instance_valid(existing_ability):
		# SCENARIO A: First-time mounting into an empty slot
		var new_ability = ability_container.add_ability_from_data(definition.ability_data_payload)
		if is_instance_valid(new_ability):
			print("[UNLOCK SUCCESS] New ability wrapper mounted on Slot Lane: ", target_slot_idx)
	else:
		# SCENARIO B: Weapon evolution or structural morphology driver swap
		ability_container.execute_ability_evolution(definition.ability_data_payload)
		print("[EVOLUTION SUCCESS] Active slot morphed on Slot Lane: ", target_slot_idx)


func _on_payload_collected(payload: PickupPayload) -> void:
	match payload.type:
		"experience":
			if is_instance_valid(progression_component):
				progression_component.gain_experience(payload.value)
