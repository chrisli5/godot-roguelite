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
		stats_container.configure_slot_context(0, run_ledger_component)
	
	collector_component.payload_collected.connect(_on_payload_collected)
	
	# Pre-load initial player starting blueprints directly into the central run ledger
	if is_instance_valid(player_data) and player_data.player_core_blueprints:
		for profile in player_data.player_core_blueprints:
			if is_instance_valid(profile) and profile.definition_bundle:
				for definition in profile.definition_bundle:
					# Seed baseline upgrades as Tier 0 or unlock them based on starting rules
					pass
					
	# Rebuild the run (ledger, level, loadout, health) BEFORE announcing the player,
	# so every listener sees a fully restored character.
	_restore_run_state()
	
	EventBus.player_spawned.emit(get_instance_id())


func _physics_process(_delta: float) -> void:
	_handle_movement_physics()


func _exit_tree() -> void:
	capture_run_state()
	EventBus.player_despawned.emit()


## Writes everything that must outlive this room into RunSession. Room changes free the
## whole world scene, so this runs as the player leaves the tree.
func capture_run_state() -> void:
	if not is_instance_valid(health_component) or not is_instance_valid(run_ledger_component) \
			or not is_instance_valid(progression_component) or not is_instance_valid(ability_container):
		return
	# A dead player never carries over into another room
	if health_component.current_health <= 0.0:
		return
	
	if RunSession.state == null:
		RunSession.reset()
	var snapshot := RunSession.state
	snapshot.has_player_snapshot = true
	
	snapshot.purchase_registry.clear()
	for upgrade_id in run_ledger_component.purchase_registry:
		snapshot.purchase_registry[upgrade_id] = run_ledger_component.purchase_registry[upgrade_id]
	snapshot.active_upgrades.clear()
	for definition in run_ledger_component.active_upgrades:
		snapshot.active_upgrades.append(definition)
	
	snapshot.level = progression_component.current_level
	snapshot.current_xp = progression_component.current_xp
	snapshot.total_accumulated_xp = progression_component.total_accumulated_xp
	snapshot.current_health = health_component.current_health
	
	snapshot.loadout.clear()
	snapshot.ability_states.clear()
	for slot_index in ability_container.abilities:
		var ability: Ability = ability_container.abilities[slot_index]
		if is_instance_valid(ability) and is_instance_valid(ability.data):
			snapshot.loadout[slot_index] = ability.data
			snapshot.ability_states[slot_index] = ability.export_runtime_state()


## Rebuilds the saved run onto this freshly spawned player. Order matters: the ledger goes
## first because core stats and every mounted ability read it while they initialize.
func _restore_run_state() -> void:
	if not RunSession.has_player_snapshot():
		return
	var snapshot := RunSession.state
	
	run_ledger_component.restore_state(snapshot.purchase_registry, snapshot.active_upgrades)
	stats_container.invalidate_all_caches()
	
	progression_component.restore_state(snapshot.level, snapshot.current_xp, snapshot.total_accumulated_xp)
	
	for slot_index in snapshot.loadout:
		var ability := ability_container.add_ability_from_data(snapshot.loadout[slot_index])
		if is_instance_valid(ability):
			ability.import_runtime_state(snapshot.ability_states.get(slot_index, {}))
	
	# Vitals last: max health depends on the ledger-driven core stats restored above
	health_component.update_max_health(stats_container.get_final_stat_value(Stat.Type.MAX_HEALTH))
	health_component.restore_current_health(snapshot.current_health)


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
		
	# --- OVERCLOCK: permanently raises one ability's infusion cap (never falls through to log_purchase) ---
	if definition.payload_type == UpgradeDefinition.PayloadType.ABILITY_OVERCLOCK and choice.target_slot_index > 0:
		run_ledger_component.log_slot_specific_purchase(definition, choice.target_slot_index)
		var overclocked_ability := ability_container.get_ability_by_slot(choice.target_slot_index)
		if is_instance_valid(overclocked_ability) and is_instance_valid(overclocked_ability.evolution_gate_component):
			overclocked_ability.evolution_gate_component.is_permanently_overclocked = true
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
