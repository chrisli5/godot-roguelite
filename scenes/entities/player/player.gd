class_name Player
extends Entity

@export_group("Components")
@export var collector_component: CollectorComponent
@export var progression_component: ProgressionComponent
@export var upgrade_ledger_component: UpgradeLedgerComponent
@export var configuration_data: PlayerData


func _enter_tree() -> void:
	EventBus.active_player = self


func _ready() -> void:
	super()
	var required_player_components: Array[String] = [
		"collector_component",
		"progression_component",
		"upgrade_ledger_component"
	]
	
	if not ComponentValidator.validate_components(self, required_player_components):
		set_physics_process(false)
		return
	
	collector_component.payload_collected.connect(_on_payload_collected)
	
	if is_instance_valid(upgrade_ledger_component) and is_instance_valid(configuration_data):
		upgrade_ledger_component.initialize_ledger(configuration_data.player_core_blueprints)


func _physics_process(_delta: float) -> void:
	_handle_movement_physics()


func _exit_tree() -> void:
	if EventBus.active_player == self:
		EventBus.active_player = null


func _handle_movement_physics() -> void:
	if not movement_strategy or not stats_container:
		return
	
	var max_speed = stats_container.get_stat_value(Stat.Type.MOVEMENT_SPEED, 1.0)
	var direction: Vector2 = Vector2.ZERO
	
	direction.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	direction.y = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	
	var target_velocity: Vector2 = direction.normalized()
	
	velocity = movement_strategy.calculate_velocity(velocity, target_velocity, max_speed, global_position, 0.0, null)
	move_and_slide()


func compile_character_eligible_pool(player_character_level: int) -> void:	
	if is_instance_valid(upgrade_ledger_component):
		upgrade_ledger_component.compile_standard_eligible_pool(player_character_level)


func apply_contextual_upgrade(choice: UpgradeChoice) -> void:
	var definition = choice.definition
	if not is_instance_valid(definition):
		return
		
	if definition.draft_behavior_tags.has(Tags.Type.INFUSION):
		_process_elemental_infusion(choice)
		return
	if definition.payload_type == UpgradeDefinition.PayloadType.STAT_MODIFIER and not definition.global_modifier_tags.is_empty():
		_process_global_modifier(choice)
		return
	if definition.payload_type == UpgradeDefinition.PayloadType.STAT_MODIFIER:
		_process_local_stat_modifier(choice)
		return
	if definition.payload_type == UpgradeDefinition.PayloadType.ABILITY_UNLOCK:
		_process_structural_ability_mutation(choice)
		return


func _process_elemental_infusion(choice: UpgradeChoice) -> void:
	var definition = choice.definition
	if not is_instance_valid(ability_container) or choice.target_slot_index <= 0:
		return
		
	var target_weapon = ability_container.get_ability_by_slot(choice.target_slot_index)
	if not is_instance_valid(target_weapon):
		return
		
	var picked_element: Tags.Type = Tags.Type.NONE
	for tag in definition.draft_behavior_tags:
		if tag != Tags.Type.INFUSION:
			picked_element = tag
			break
			
	# Update DNA taxonomy tags and log purchase entries inside local weapon register
	target_weapon.apply_infusion_socket(picked_element, definition.upgrade_id)
	
	# Uniform Scaling Calculation Pass
	var modifier_instance: StatModifier = definition.stat_modifier_payload.duplicate()
	var current_tier: int = choice.source_tracker.current_purchases
	if current_tier == 0: current_tier = 1
	modifier_instance.value = definition.stat_modifier_payload.value * current_tier
	
	modifier_instance.id = ModifierFactory.generate_id(
		ModifierFactory.OriginSource.LOCAL_UPGRADE,
		choice.source_tracker,
		target_weapon,
		"infusion_socket"
	)
	
	ability_container.add_stat_modifier_to_slot(choice.target_slot_index, definition.target_stat_type, modifier_instance)


func _process_local_stat_modifier(choice: UpgradeChoice) -> void:
	var definition = choice.definition
	var modifier_instance: StatModifier = definition.stat_modifier_payload.duplicate()
	
	var current_tier: int = choice.source_tracker.current_purchases
	if current_tier == 0: current_tier = 1
	modifier_instance.value = definition.stat_modifier_payload.value * current_tier
	
	if choice.target_slot_index > 0:
		var ability = ability_container.get_ability_by_slot(choice.target_slot_index)
		if is_instance_valid(ability):
			modifier_instance.id = ModifierFactory.generate_id(
				ModifierFactory.OriginSource.LOCAL_UPGRADE,
				choice.source_tracker,
				ability,
				"local_linear_stat"
			)
			ability_container.add_stat_modifier_to_slot(choice.target_slot_index, definition.target_stat_type, modifier_instance)
	else:
		modifier_instance.id = ModifierFactory.generate_id(
			ModifierFactory.OriginSource.LOCAL_UPGRADE,
			choice.source_tracker,
			self,
			"character_linear_stat"
		)
		stats_container.add_modifier(definition.target_stat_type, modifier_instance)


func _process_global_modifier(choice: UpgradeChoice) -> void:
	# 1. Configuration Dependency Check
	var definition = choice.definition
	if not is_instance_valid(definition) or not is_instance_valid(ability_container):
		return
		
	# 2. Extract context out of our tracking registers
	var base_upgrade_id: String = definition.upgrade_id
	var player_ledger = upgrade_ledger_component
	
	if is_instance_valid(player_ledger):
		# Log purchase entry in player memory if it hasn't been handled yet
		player_ledger.log_purchase_entry(base_upgrade_id)
		
		# Compile the active tier level from player memory matrix logs
		var purchased_tier: int = player_ledger.purchase_levels.get(base_upgrade_id, 0)
		print("[GLOBAL PASSIVE PURCHASE] %s successfully leveled up to Tier %d." % [definition.display_name, purchased_tier])
	else:
		push_warning("[PLAYER LEGER] Missing player upgrade ledger sub-component reference on global passive purchase.")

	if ability_container.has_method("refresh_all_global_modifiers"):
		ability_container.refresh_all_global_modifiers()
	else:
		push_error("[ABILITYCONTAINER] Cannot synchronize global modifiers. Method 'refresh_all_global_modifiers' not found.")


func _process_structural_ability_mutation(choice: UpgradeChoice) -> void:
	var definition = choice.definition
	if not is_instance_valid(ability_container) or not is_instance_valid(definition.ability_data_payload):
		return
		
	var existing_ability = ability_container.get_ability_by_slot(choice.target_slot_index)
	
	if not is_instance_valid(existing_ability):
		# SCENARIO A: FIRST-TIME SLOT DEPLOYMENT (Empty Slate Node)
		# A brand new wrapper is generated, meaning we MUST apply active global cards right now
		var new_ability = ability_container.add_ability_from_data(definition.ability_data_payload)
		print("[UNLOCK] New wrapper mounted into static Slot: ", choice.target_slot_index)
		
		if is_instance_valid(new_ability):
			ability_container.sync_global_modifiers_for_slot(choice.target_slot_index)
	else:
		# SCENARIO B: STRATEGY GEOMETRY SWAP / OVERCLOCK VARIANT
		# The core node wrapper is preserved. The mutate_base_profile() sequence 
		# inside StatsContainer automatically saves and migrates our modifiers.
		ability_container.execute_ability_evolution(definition.ability_data_payload)
		print("[MUTATION] Active slot morphed. Strategy and profile swapped cleanly on Slot: ", choice.target_slot_index)


func _on_payload_collected(payload: PickupPayload) -> void:
	match payload.type:
		"experience":
			if is_instance_valid(progression_component):
				progression_component.gain_experience(payload.value)
