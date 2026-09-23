class_name Player
extends Entity

@export_group("Components")
@export var collector_component: CollectorComponent
@export var progression_component: ProgressionComponent
@export var upgrade_ledger_component: UpgradeLedgerComponent


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


func _physics_process(_delta: float) -> void:
	_handle_movement_physics()


func _exit_tree() -> void:
	if EventBus.active_player == self:
		EventBus.active_player = null


func _handle_movement_physics() -> void:
	if not movement_strategy or not stats_container:
		return
	
	var max_speed = stats_container.get_stat_value(Stat.Type.MOVEMENT_SPEED, 1.0)
	var acceleration = stats_container.get_stat_value(Stat.Type.ACCELERATION, 1.0)
	var friction = stats_container.get_stat_value(Stat.Type.FRICTION, 1.0)
	var direction: Vector2 = Vector2.ZERO
	
	direction.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	direction.y = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	
	var target_velocity: Vector2 = direction.normalized()
	
	velocity = movement_strategy.calculate_velocity(velocity, target_velocity, max_speed, acceleration, friction, 0.0)
	move_and_slide()


## UNIFIED SINGLE VALUE SCALING COMPILE:
func compile_character_eligible_pool(player_character_level: int) -> void:	
	var compiled_upgrades: Array[UpgradeTracker] = []
	var compiled_unlocks: Array[UpgradeTracker] = []
	
	for tracker in upgrade_ledger_component.available_upgrades:
		var definition = tracker.definition
		if not is_instance_valid(definition) or tracker.current_purchases >= tracker.max_purchases:
			continue
			
		# Dynamic level step gating calculation pass
		var dynamic_req_level = tracker.required_character_level + (tracker.current_purchases * 2)
		if player_character_level < dynamic_req_level:
			continue
			
		if definition.payload_type == UpgradeDefinition.PayloadType.STAT_MODIFIER:
			tracker.tier_index = tracker.current_purchases + 1
			compiled_upgrades.append(tracker)
					
	for tracker in upgrade_ledger_component.available_evolutions:
		var definition = tracker.definition
		if not is_instance_valid(definition) or tracker.current_purchases >= tracker.max_purchases:
			continue

		if player_character_level < tracker.required_character_level:
			continue
			
		if definition.payload_type == UpgradeDefinition.PayloadType.ABILITY_UNLOCK:
			tracker.tier_index = tracker.current_purchases + 1
			compiled_unlocks.append(tracker)

	upgrade_ledger_component.clear_caches()
	upgrade_ledger_component.overwrite_cached_pools(compiled_upgrades, compiled_unlocks)


## Refactored Entry Point Router Passing Choice Data
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
	var definition = choice.definition
	if not is_instance_valid(ability_container):
		return
			
	for slot_idx in range(1, 5):
		var weapon = ability_container.get_ability_by_slot(slot_idx)
		if not is_instance_valid(weapon):
			continue
				
		var weapon_tags = weapon.tag_component.get_active_tags() if is_instance_valid(weapon.tag_component) else []
		var match_found = false
		for modifier_tag in definition.global_modifier_tags:
			if weapon_tags.has(modifier_tag):
				match_found = true
				break
						
		if match_found and is_instance_valid(weapon.stats_container):
			var global_modifier_instance: StatModifier = definition.stat_modifier_payload.duplicate()
			var current_tier: int = choice.source_tracker.current_purchases
			if current_tier == 0: current_tier = 1
			global_modifier_instance.value = definition.stat_modifier_payload.value * current_tier
			
			global_modifier_instance.id = ModifierFactory.generate_id(
				ModifierFactory.OriginSource.GLOBAL_UPGRADE,
				choice.source_tracker,
				weapon
			)
			weapon.stats_container.add_modifier(definition.target_stat_type, global_modifier_instance)


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
			ability_container.apply_global_modifiers_to_ability(new_ability)
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
