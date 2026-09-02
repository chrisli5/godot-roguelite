class_name Player
extends Entity

@export_group("Components")
@export var progression_component: ProgressionComponent
@export var collector_component: CollectorComponent
@export var upgrade_ledger_component: UpgradeLedgerComponent


func _enter_tree() -> void:
	EventBus.active_player = self


func _ready() -> void:
	super()
	var components_valid: bool = true
	
	if not progression_component:
		push_error("Entity '%s' is missing a ProgressionComponent!" % name)
		components_valid = false
	if not collector_component:
		push_error("Entity '%s' is missing a CollectorComponent!" % name)
		components_valid = false
	if not upgrade_ledger_component:
		push_error("Entity '%s' is missing a UpgradeLedgerComponent!" % name)
		components_valid = false	

	if not components_valid:
		return
	
	collector_component.payload_collected.connect(_on_payload_collected)


func _physics_process(_delta: float) -> void:
	_handle_movement_physics()


func _exit_tree() -> void:
	if EventBus.active_player == self:
		EventBus.active_player = null


func _handle_movement_physics() -> void:
	if not movement_component or not stats_container:
		return
	
	var max_speed = stats_container.get_stat_value(Stat.Type.SPEED, 1.0)
	var acceleration = stats_container.get_stat_value(Stat.Type.ACCELERATION, 1.0)
	var friction = stats_container.get_stat_value(Stat.Type.FRICTION, 1.0)
	var direction: Vector2 = Vector2.ZERO
	
	direction.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	direction.y = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	
	var target_velocity: Vector2 = direction.normalized()
	
	velocity = movement_component.calculate_velocity(velocity, target_velocity, max_speed, acceleration, friction)
	move_and_slide()


func compile_character_eligible_pool(player_character_level: int) -> void:	
	# Cache localized temporary arrays to pass to storage registers
	var compiled_upgrades: Array[UpgradeTracker] = []
	var compiled_unlocks: Array[UpgradeTracker] = []
	
	for tracker in upgrade_ledger_component.available_upgrades:
		var definition = tracker.definition
		if not is_instance_valid(definition) or tracker.current_purchases >= tracker.max_purchases:
			continue
			
		# Enforce standard player level gating constraints layout metrics
		if player_character_level < tracker.required_character_level:
			continue
			
		match definition.payload_type:
			UpgradeDefinition.PayloadType.STAT_MODIFIER:
				# Character stats (e.g. Speed, Health) map smoothly based on purchased tiers
				var current_acquired_tier = upgrade_ledger_component.purchase_levels.get(definition.upgrade_id, 0)
				if tracker.tier_index == current_acquired_tier + 1:
					compiled_upgrades.append(tracker)
					
	for tracker in upgrade_ledger_component.available_evolutions:
		var definition = tracker.definition
		if not is_instance_valid(definition) or tracker.current_purchases >= tracker.max_purchases:
			continue

		if player_character_level < tracker.required_character_level:
			continue
			
		match definition.payload_type:
			UpgradeDefinition.PayloadType.ABILITY_UNLOCK:
				compiled_unlocks.append(tracker)

	# Overwrite local cache storage registers instantly
	upgrade_ledger_component.clear_caches()
	upgrade_ledger_component.overwrite_cached_pools(compiled_upgrades, compiled_unlocks)


func apply_contextual_upgrade(choice: UpgradeChoice) -> void:
	var definition = choice.definition
	if not is_instance_valid(definition):
		return
		
	# --- BRANCH A: LINEAR STAT UPGRADES (STAT_MODIFIER) ---
	if definition.payload_type == UpgradeDefinition.PayloadType.STAT_MODIFIER and definition.global_modifier_tags.is_empty():
		# Isolate a pristine data copy so we don't pollute the global static asset resource disk file
		var modifier_instance: StatModifier = definition.stat_modifier_payload.duplicate()
		
		if choice.target_slot_index > 0:
			# SCENARIO 1: Weapon-Specific Local Modifier
			if is_instance_valid(ability_container):
				var ability = ability_container.get_ability_by_slot(choice.target_slot_index)
				if is_instance_valid(ability):
					modifier_instance.id = ModifierFactory.generate_id(
						ModifierFactory.OriginSource.LOCAL_UPGRADE,
						choice.source_tracker,
						ability
					)
					ability_container.add_stat_modifier_to_slot(choice.target_slot_index, definition.target_stat_type, modifier_instance)
		else:
			modifier_instance.id = ModifierFactory.generate_id(
				ModifierFactory.OriginSource.LOCAL_UPGRADE,
				choice.source_tracker,
				self
			)
			stats_container.add_modifier(definition.target_stat_type, modifier_instance)
		return
	
	# --- BRANCH B: GLOBAL CORE / MULTIPLIER UPGRADES (STAT_MODIFIER) ---
	if definition.payload_type == UpgradeDefinition.PayloadType.STAT_MODIFIER and not definition.global_modifier_tags.is_empty():
		if not is_instance_valid(ability_container):
			return
			
		# Loop symmetrically through structural hotbar index targets 1 to 4
		for slot_idx in range(1, 5):
			var weapon = ability_container.get_ability_by_slot(slot_idx)
			if not is_instance_valid(weapon):
				continue
				
			var weapon_tags = weapon.tag_component.get_active_tags() if is_instance_valid(weapon.tag_component) else []
			
			# Check for compatibility intersection matches against broadcast rules
			var match_found = false
			for modifier_tag in definition.global_modifier_tags:
				if weapon_tags.has(modifier_tag):
					match_found = true
					break
						
			if match_found and is_instance_valid(weapon.stats_container):
				var global_modifier_instance: StatModifier = definition.stat_modifier_payload.duplicate()
				
				# Scale total output payload directly by total investments tracked inside the ledger history registers
				var purchased_tier = choice.source_tracker.current_purchases
				global_modifier_instance.value = definition.stat_modifier_payload.value * purchased_tier
				global_modifier_instance.id = ModifierFactory.generate_id(
					ModifierFactory.OriginSource.GLOBAL_UPGRADE,
					choice.source_tracker,
					weapon
				)
				weapon.stats_container.add_modifier(definition.target_stat_type, global_modifier_instance)
		return

	# --- BRANCH C: STRUCTURAL MUTATIONS (ABILITY_UNLOCK) ---
	if definition.payload_type == UpgradeDefinition.PayloadType.ABILITY_UNLOCK:
		if not is_instance_valid(ability_container):
			return
			
		var existing_ability = ability_container.get_ability_by_slot(choice.target_slot_index)
		
		if not is_instance_valid(existing_ability):
			# SCENARIO 1: FIRST-TIME WEAPON UNLOCK
			var new_ability = ability_container.add_ability_from_data(definition.ability_data_payload)
			print("[UNLOCK] New ability successfully mounted into static Slot: ", choice.target_slot_index)
			
			# Symmetrical Check: Does the player already own global cards that match this fresh skill's tags?
			if is_instance_valid(new_ability) and is_instance_valid(ability_container):
				ability_container._apply_global_modifiers_to_ability(new_ability)
		else:
			# SCENARIO 2: ABILITY EVOLUTION GEOMETRY SWAP
			var evolved_ability = ability_container.execute_ability_evolution(definition.ability_data_payload)
			print("[EVOLUTION] Active slot morphed. State data migrated cleanly on Slot: ", choice.target_slot_index)
			
			# Symmetrical Check: Re-inject historic global passives into the new structural geometry frames instantly
			if is_instance_valid(evolved_ability) and is_instance_valid(ability_container):
				ability_container._apply_global_modifiers_to_ability(evolved_ability)
		return


func _on_payload_collected(payload: PickupPayload) -> void:
	match payload.type:
		"experience":
			if is_instance_valid(progression_component):
				progression_component.gain_experience(payload.value)
