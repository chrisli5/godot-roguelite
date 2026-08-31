class_name Player
extends Entity

@export_group("Components")
@export var progression_component: ProgressionComponent
@export var collector_component: CollectorComponent
@export var upgrade_ledger_component: UpgradeLedgerComponent


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


func _enter_tree() -> void:
	EventBus.active_player = self


func _exit_tree() -> void:
	if EventBus.active_player == self:
		EventBus.active_player = null


func _physics_process(_delta: float) -> void:
	_handle_movement_physics()


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


func _on_payload_collected(payload: PickupPayload) -> void:
	match payload.type:
		"experience":
			if is_instance_valid(progression_component):
				progression_component.gain_experience(payload.value)
