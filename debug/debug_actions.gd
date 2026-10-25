class_name DebugActions
extends RefCounted
## All the logic behind the debug panel's buttons, as static functions, so a button and a headless test run the
## same code. Debug tools only: nothing here is used by the game itself.


## The live player, or null.
static func find_player() -> Player:
	return instance_from_id(EventBus.active_player_instance_id) as Player


## The world's UpgradeManager, or null.
static func find_upgrade_manager(tree: SceneTree) -> UpgradeManager:
	return tree.root.find_child("UpgradeManager", true, false) as UpgradeManager


## Gives the player experience (the old console's Level Up button).
static func level_up(player: Player, xp: float = 100.0) -> void:
	if not is_instance_valid(player) or not is_instance_valid(player.progression_component):
		push_warning("DebugActions: No active player character found to level up.")
		return
	player.progression_component.gain_experience(xp)
	print("[DEBUG SIMULATION] Forced player experience gain transaction.")


## Every card in the manager's pool that can be granted by bypassing the draft rules, as {definition, total_tiers},
## de-duplicated by upgrade_id. Infusion, Overclock and evolution cards are left out: they are reachable through the
## real draft / offer flow (or the rule-respecting infusion grant).
static func grantable_cards(manager: UpgradeManager) -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	if not is_instance_valid(manager):
		return cards
	var seen_ids: Array[String] = []
	for profile in manager.master_upgrade_pool:
		if not is_instance_valid(profile) or profile.definition_bundle.is_empty():
			continue
		for definition in profile.definition_bundle:
			if not is_instance_valid(definition) or definition.upgrade_id.is_empty():
				continue
			if seen_ids.has(definition.upgrade_id):
				continue
			seen_ids.append(definition.upgrade_id)
			if definition.is_infusion() or definition.is_compound_card() or definition.payload_type == UpgradeDefinition.PayloadType.ABILITY_OVERCLOCK:
				continue
			if definition.payload_type == UpgradeDefinition.PayloadType.ABILITY_UNLOCK and definition.evolves_from != null:
				continue
			cards.append({"definition": definition, "total_tiers": profile.total_tiers})
	return cards


## Grants a non-infusion card directly, bypassing the draft rules (the old console's Grant button).
static func grant_card(player: Player, definition: UpgradeDefinition, total_tiers: int) -> void:
	if not is_instance_valid(player):
		push_warning("DebugActions: Cannot grant upgrade. Active player context missing.")
		return
	var mock_tracker := UpgradeTracker.new()
	mock_tracker.definition = definition
	mock_tracker.max_purchases = total_tiers
	mock_tracker.current_purchases = player.run_ledger_component.purchase_registry.get(definition.upgrade_id, 0)

	var choice := UpgradeChoice.new()
	choice.source_tracker = mock_tracker
	choice.target_slot_index = definition.restrict_to_slot
	choice.target_display_name = "Debug Direct Injection"
	print("[DEBUG SIMULATION] Injecting upgrade directly: ", definition.display_name)
	player.apply_contextual_upgrade(choice)


## Opens the real infusion draft (random cards, then the allocation screen).
static func draft_infusion(manager: UpgradeManager) -> void:
	if not is_instance_valid(manager):
		push_warning("DebugActions: UpgradeManager instance missing from world root layout.")
		return
	print("[DEBUG TRIGGER] Dispatching standalone elemental infusion draft event...")
	manager.trigger_infusion_draft_event()


## The infusion definitions the real infusion draft can offer (same source as UpgradeManager._generate_infusion_pool:
## the pool's definitions with category INFUSION), de-duplicated by upgrade_id.
static func grantable_infusions(manager: UpgradeManager) -> Array[UpgradeDefinition]:
	var infusions: Array[UpgradeDefinition] = []
	if not is_instance_valid(manager):
		return infusions
	for profile in manager.master_upgrade_pool:
		if not is_instance_valid(profile):
			continue
		for definition in profile.definition_bundle:
			if not is_instance_valid(definition) or not definition.is_infusion():
				continue
			if definition.get_infusion_element() == Tags.Type.NONE:
				continue
			var already_listed := false
			for existing in infusions:
				if existing.upgrade_id == definition.upgrade_id:
					already_listed = true
					break
			if not already_listed:
				infusions.append(definition)
	return infusions


## Why `definition` cannot be socketed as `element` into `slot` right now, or "" if the real flow would allow it.
## Uses the allocation screen's own rule (InfusionTrackerComponent.is_element_socket_allowed with the ability's
## evolution state and Overclock flag). Changes nothing.
static func can_grant_infusion(player: Player, definition: UpgradeDefinition, element: int, slot: int) -> String:
	if not is_instance_valid(player) or not is_instance_valid(player.ability_container):
		return "no active player"
	if slot < AbilityContainer.MIN_SLOT or slot > AbilityContainer.MAX_SLOT:
		return "slot %d is outside %d to %d" % [slot, AbilityContainer.MIN_SLOT, AbilityContainer.MAX_SLOT]
	var ability: Ability = player.ability_container.get_ability_by_slot(slot)
	if not is_instance_valid(ability):
		return "no ability is mounted in slot %d" % slot
	var gate := ability.evolution_gate_component
	var tracker := ability.infusion_tracker_component
	if not is_instance_valid(gate) or not is_instance_valid(tracker):
		return "the ability in slot %d has no infusion components" % slot
	var element_name := _element_name(element)
	if not tracker.is_element_socket_allowed(element as Tags.Type, int(gate.current_state), gate.is_permanently_overclocked):
		return "%s is not accepted by %s in slot %d (cap or element limit)" % [element_name, ability.display_name, slot]
	if not is_instance_valid(definition) or not definition.is_infusion() or int(definition.get_infusion_element()) != element:
		return "the card does not match element %s" % element_name
	return ""


## Socket an infusion the way the real flow would, minus the random roll and the allocation screen. Refuses (and
## changes nothing) whatever the real flow would not allow. Returns "" on success, otherwise the reason.
## Does not touch the draft state or the pause: it applies the choice directly, then asks the manager to re-check offers.
static func grant_infusion(player: Player, manager: UpgradeManager, definition: UpgradeDefinition, element: int, slot: int) -> String:
	var reason := can_grant_infusion(player, definition, element, slot)
	if not reason.is_empty():
		push_warning("DebugActions: infusion grant refused: %s" % reason)
		return reason

	# Built like UpgradeManager._generate_infusion_pool builds the draft choice.
	var tracker := UpgradeTracker.new()
	tracker.definition = definition
	tracker.current_purchases = player.run_ledger_component.purchase_registry.get(definition.upgrade_id, 0)
	tracker.max_purchases = _total_tiers_of(manager, definition)
	var choice := UpgradeChoice.new()
	choice.source_tracker = tracker
	choice.target_slot_index = slot
	choice.target_display_name = player.ability_container.get_ability_by_slot(slot).display_name

	player.apply_contextual_upgrade(choice)
	if is_instance_valid(manager):
		manager.recheck_offers()
	return ""


## Respawns the player through the same capture and restore path a room change uses (the old F3).
static func respawn_player(host: Node) -> void:
	var player := find_player()
	if not is_instance_valid(player):
		return

	var scene_path := player.scene_file_path
	if scene_path.is_empty():
		push_error("DebugActions: Player has no scene_file_path to re-instantiate.")
		return

	var data := player.entity_data
	var spawn_position := player.global_position

	# Freeing the player triggers its capture step (Player._exit_tree)
	player.queue_free()
	await host.get_tree().process_frame

	var fresh := (load(scene_path) as PackedScene).instantiate() as Player
	fresh.initialize_entity(data)
	fresh.global_position = spawn_position
	EventBus.spawn_requested.emit(fresh)
	print("[DEBUG] Player respawned. Run state restored from RunSession.")


## The enemy nearest the player (nearest to the origin without a player), or null.
static func find_nearest_enemy(tree: SceneTree) -> Enemy:
	var origin := Vector2.ZERO
	var player := find_player()
	if is_instance_valid(player):
		origin = player.global_position

	var nearest: Enemy = null
	var nearest_distance := INF
	for node in tree.root.find_children("*", "Enemy", true, false):
		var enemy := node as Enemy
		if enemy == null or not is_instance_valid(enemy.status_effect_component):
			continue
		var distance := origin.distance_squared_to(enemy.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = enemy
	return nearest


## Applies `effect` to the nearest enemy with the simulated source magnitudes. False when there is no enemy.
static func apply_status_to_nearest(tree: SceneTree, effect: StatusEffect, dot_damage: float, duration_bonus: float, stack_cap_bonus: float = 0.0) -> bool:
	if not is_instance_valid(effect):
		push_warning("DebugActions: effect resource not assigned.")
		return false
	var enemy := find_nearest_enemy(tree)
	if enemy == null:
		return false
	enemy.status_effect_component.apply_effect(effect, dot_damage, duration_bonus, 0.0, stack_cap_bonus)
	return true


static func _element_name(element: int) -> String:
	if element >= 0 and element < Tags.Type.size():
		return String(Tags.Type.keys()[element])
	return str(element)


static func _total_tiers_of(manager: UpgradeManager, definition: UpgradeDefinition) -> int:
	if is_instance_valid(manager):
		for profile in manager.master_upgrade_pool:
			if not is_instance_valid(profile):
				continue
			for candidate in profile.definition_bundle:
				if candidate == definition:
					return profile.total_tiers
	return 1
