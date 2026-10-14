class_name UpgradeManager
extends Node

## Holds the raw full collection of available run upgrades that can be rolled.
## Typically seeded from a master Act database resource or individual player configuration arrays.
@export var master_upgrade_pool: Array[UpgradeBlueprintProfile] = []

var _cached_full_pool: Array[UpgradeChoice] = []
var _level_up_queue: Array[int] = []
var _is_presenting_ui: bool = false
## True while a forced evolution / Overclock offer is on screen (no reroll, no random fill).
var _is_offer_draft: bool = false
## Slots whose offer could not be built; skipped so they cannot block the queue.
var _unofferable_slots: Array[int] = []
var _pending_check_scheduled: bool = false


func _ready() -> void:
	EventBus.player_leveled_up.connect(_on_player_leveled_up)
	EventBus.upgrade_selected.connect(_on_ui_upgrade_selected)
	EventBus.upgrade_reroll_requested.connect(reroll_current_options)
	EventBus.infusion_allocation_confirmed.connect(_on_infusion_allocation_confirmed)
	EventBus.player_spawned.connect(_on_player_spawned)
	
	# The player may already exist if this manager is created late.
	if instance_from_id(EventBus.active_player_instance_id) is Player:
		_schedule_pending_check()


func _on_player_spawned(_target_player_id: int) -> void:
	_schedule_pending_check()


func _schedule_pending_check() -> void:
	if _pending_check_scheduled:
		return
	_pending_check_scheduled = true
	_start_pending_drafts.call_deferred()


## Room start: present a pending offer or queued level-ups, unless a draft is already showing.
func _start_pending_drafts() -> void:
	_pending_check_scheduled = false
	if _is_presenting_ui:
		return
	var player := instance_from_id(EventBus.active_player_instance_id) as Player
	if not is_instance_valid(player):
		return
	if _level_up_queue.is_empty() and _find_next_offer_slot(player) == 0:
		return
	_try_process_next_level_up()


func _on_player_leveled_up(new_level: int) -> void:
	_level_up_queue.append(new_level)
	if not _is_presenting_ui:
		_try_process_next_level_up()


func _try_process_next_level_up() -> void:
	# Forced offers (evolution / Overclock) come before any queued level-up draft.
	var offer_player := instance_from_id(EventBus.active_player_instance_id) as Player
	if is_instance_valid(offer_player):
		var offer_slot := _find_next_offer_slot(offer_player)
		if offer_slot > 0:
			var offer_choices := _build_offer_choices(offer_player, offer_slot)
			if offer_choices.is_empty():
				push_error("UpgradeManager: no offer cards could be built for slot %d." % offer_slot)
				_unofferable_slots.append(offer_slot)
			else:
				_is_presenting_ui = true
				get_tree().paused = true
				_is_offer_draft = true
				_cached_full_pool = offer_choices
				EventBus.upgrade_options_ready.emit(offer_choices)
				return
	
	if _level_up_queue.is_empty():
		get_tree().paused = false
		_is_presenting_ui = false
		return
		
	_is_presenting_ui = true
	get_tree().paused = true 

	var current_player: Player = instance_from_id(EventBus.active_player_instance_id) as Player
	var next_level_to_process: int = _level_up_queue.pop_front()
	
	if is_instance_valid(current_player):
		# Pass the central player reference and level context to compile our subset pool
		_cached_full_pool = generate_selection_pool(current_player, next_level_to_process)
		var rolled_options = _roll_random_subset(_cached_full_pool, 3)
		if rolled_options.is_empty():
			# Never present an empty draft: it would leave the game paused on an empty screen.
			push_warning("UpgradeManager: no upgrades available for level %d, skipping its draft." % next_level_to_process)
			get_tree().process_frame.connect(_try_process_next_level_up, CONNECT_ONE_SHOT)
			return
		_is_offer_draft = false
		EventBus.upgrade_options_ready.emit(rolled_options)


func trigger_infusion_draft_event() -> void:
	var current_player: Player = instance_from_id(EventBus.active_player_instance_id) as Player
	if not is_instance_valid(current_player):
		return
		
	_is_presenting_ui = true
	get_tree().paused = true
	
	var available_choices: Array[UpgradeChoice] = _generate_infusion_pool(current_player)
	if available_choices.is_empty():
		get_tree().paused = false
		_is_presenting_ui = false
		return
		
	_cached_full_pool = available_choices
	_is_offer_draft = false
	var rolled_options = _roll_random_subset(_cached_full_pool, 3)
	EventBus.upgrade_options_ready.emit(rolled_options)


func _generate_infusion_pool(target_player: Player) -> Array[UpgradeChoice]:
	var infusion_pool: Array[UpgradeChoice] = []

	for profile in master_upgrade_pool:
		if not is_instance_valid(profile): continue
		for definition in profile.definition_bundle:
			if definition.is_infusion():
				if not _any_ability_accepts_element(target_player, definition.get_infusion_element()):
					continue
				var current_tier = target_player.run_ledger_component.purchase_registry.get(definition.upgrade_id, 0)
				if current_tier >= profile.total_tiers: continue
				
				var choice = UpgradeChoice.new()
				var tracker := UpgradeTracker.new()
				tracker.definition = definition
				tracker.current_purchases = current_tier
				tracker.max_purchases = profile.total_tiers
				
				choice.source_tracker = tracker
				choice.target_slot_index = 0
				choice.target_display_name = "Global Elements"
				infusion_pool.append(choice)
		
	return infusion_pool


## First slot (ascending) whose ability is eligible for an evolution / Overclock offer, or 0 if none.
func _find_next_offer_slot(player: Player) -> int:
	for slot_idx in range(AbilityContainer.MIN_SLOT, AbilityContainer.MAX_SLOT + 1):
		if _unofferable_slots.has(slot_idx):
			continue
		var ability: Ability = player.ability_container.get_ability_by_slot(slot_idx)
		if not is_instance_valid(ability):
			continue
		var tracker := ability.infusion_tracker_component
		var gate := ability.evolution_gate_component
		if not is_instance_valid(tracker) or not is_instance_valid(gate):
			continue
		if gate.is_offer_eligible(tracker.infusion_levels):
			return slot_idx
	return 0


## Offer cards for `slot`: every evolution whose recipe is met (not yet bought), then one Overclock card.
func _build_offer_choices(player: Player, slot: int) -> Array[UpgradeChoice]:
	var choices: Array[UpgradeChoice] = []
	var ability: Ability = player.ability_container.get_ability_by_slot(slot)
	if not is_instance_valid(ability) or not is_instance_valid(ability.infusion_tracker_component) 			or not is_instance_valid(ability.evolution_gate_component):
		return choices
	
	var all_definitions: Array[UpgradeDefinition] = []
	var overclock_definition: UpgradeDefinition = null
	for profile in master_upgrade_pool:
		if not is_instance_valid(profile): continue
		for definition in profile.definition_bundle:
			if not is_instance_valid(definition): continue
			all_definitions.append(definition)
			if overclock_definition == null and definition.payload_type == UpgradeDefinition.PayloadType.ABILITY_OVERCLOCK:
				overclock_definition = definition
	
	var evolutions := ability.evolution_gate_component.evaluate_evolution_recipes(
		all_definitions, ability.infusion_tracker_component.infusion_levels, ability.data
	)
	for definition in evolutions:
		if player.run_ledger_component.purchase_registry.get(definition.upgrade_id, 0) > 0:
			continue
		choices.append(_make_offer_choice(definition, slot, ability))
	
	if overclock_definition != null:
		choices.append(_make_offer_choice(overclock_definition, slot, ability))
	else:
		push_error("UpgradeManager: no ABILITY_OVERCLOCK definition in master_upgrade_pool.")
	return choices


func _make_offer_choice(definition: UpgradeDefinition, slot: int, ability: Ability) -> UpgradeChoice:
	var tracker := UpgradeTracker.new()
	tracker.definition = definition
	tracker.current_purchases = 0
	tracker.max_purchases = 1
	
	var choice := UpgradeChoice.new()
	choice.source_tracker = tracker
	choice.target_slot_index = slot
	choice.target_display_name = ability.display_name
	choice.is_forced_offer = true
	return choice


## True if at least one of the player's abilities can currently socket `element`.
## Uses the same checks as InfusionAllocationUI._render_eligible_weapon_rows.
func _any_ability_accepts_element(player: Player, element: Tags.Type) -> bool:
	for slot_idx in range(AbilityContainer.MIN_SLOT, AbilityContainer.MAX_SLOT + 1):
		var ability: Ability = player.ability_container.get_ability_by_slot(slot_idx)
		if not is_instance_valid(ability):
			continue
		var tracker := ability.infusion_tracker_component
		var gate := ability.evolution_gate_component
		if not is_instance_valid(tracker) or not is_instance_valid(gate):
			continue
		if tracker.is_element_socket_allowed(element, gate.current_state, gate.is_permanently_overclocked):
			return true
	return false


## MASTER COMPILED SELECTION POOL:
## Evaluates the player's single central ledger, looks up max ceilings from profiles,
## and contextually routes appropriate targets dynamically.
func generate_selection_pool(target_player: Player, processing_level: int) -> Array[UpgradeChoice]:
	var full_pool: Array[UpgradeChoice] = []
	var ledger := target_player.run_ledger_component
	var container := target_player.ability_container
	
	for profile in master_upgrade_pool:
		if not is_instance_valid(profile): continue
		
		for definition in profile.definition_bundle:
			var current_tier = ledger.purchase_registry.get(definition.upgrade_id, 0)
			
			# Ceiling Gating: Skip if player has already maxed out this card's tiers
			var max_allowed = 1 if definition.payload_type == UpgradeDefinition.PayloadType.ABILITY_UNLOCK else profile.total_tiers
			if current_tier >= max_allowed:
				continue
				
			# Evolution and Overclock cards are only ever offered through the forced offer flow
			if definition.payload_type == UpgradeDefinition.PayloadType.ABILITY_OVERCLOCK:
				continue
			if definition.payload_type == UpgradeDefinition.PayloadType.ABILITY_UNLOCK and definition.evolves_from != null:
				continue
			
			# Level Gating: Dynamic scale calculation pass
			var dynamic_req_level = profile.initial_unlock_level + (current_tier * profile.levels_per_tier)
			if processing_level < dynamic_req_level:
				continue

			# Infusion Gating: Skip elements that no ability can socket (they would soft-lock the allocation screen)
			if definition.is_infusion() and not _any_ability_accepts_element(target_player, definition.get_infusion_element()):
				continue

			# Build core tracking instance container
			var tracker := UpgradeTracker.new()
			tracker.definition = definition
			tracker.current_purchases = current_tier
			tracker.max_purchases = max_allowed

			# --- CONTEXTUAL ROUTING MATRIX ---
			match definition.scope:
				UpgradeDefinition.ScopeType.CHARACTER_CORE:
					var choice = UpgradeChoice.new()
					choice.source_tracker = tracker
					choice.target_slot_index = 0
					choice.target_display_name = "Character Core"
					full_pool.append(choice)
					
				UpgradeDefinition.ScopeType.LOCAL_SLOT:
					# Direct Weapon Upgrade: Link context specifically to the target slot index lane
					var target_ability = container.get_ability_by_slot(definition.restrict_to_slot)
					if is_instance_valid(target_ability):
						var choice = UpgradeChoice.new()
						choice.source_tracker = tracker
						choice.target_slot_index = definition.restrict_to_slot
						choice.target_display_name = target_ability.display_name
						full_pool.append(choice)
						
				UpgradeDefinition.ScopeType.GLOBAL_TAG_MATCH:
					# Broad Passive: Loops through active weapons to see if ANY match the requested taxonomy tags
					var match_found := false
					for slot_idx in range(1, 5):
						var ability = container.get_ability_by_slot(slot_idx)
						if is_instance_valid(ability) and is_instance_valid(ability.tag_component):
							for req_tag in definition.target_tags:
								if ability.tag_component.has_tag(req_tag):
									match_found = true
									break
									
					if match_found:
						var choice = UpgradeChoice.new()
						choice.source_tracker = tracker
						choice.target_slot_index = 0
						choice.target_display_name = "Matching Active Tags"
						full_pool.append(choice)
						
	return full_pool


func _on_ui_upgrade_selected(chosen_choice: UpgradeChoice) -> void:
	var current_player: Player = instance_from_id(EventBus.active_player_instance_id) as Player
	if not is_instance_valid(chosen_choice) or not is_instance_valid(current_player):
		return

	# --- ELEMENTAL INFUSION RE-ROUTING ---
	if chosen_choice.is_infusion:
		print("[INFUSION DRAFT] Rerouting choices straight to the element allocation screen layout...")
		EventBus.infusion_allocation_requested.emit(chosen_choice)
		_cached_full_pool.clear()
		return 

	# Forward transaction package directly to the central Player RunLedger
	current_player.apply_contextual_upgrade(chosen_choice)
	
	_is_offer_draft = false
	_cached_full_pool.clear()
	# Resolve coroutine tree updates on the next process frame tick cleanly
	get_tree().process_frame.connect(_try_process_next_level_up, CONNECT_ONE_SHOT)


func _on_infusion_allocation_confirmed(finalized_choice: UpgradeChoice) -> void:
	var current_player: Player = instance_from_id(EventBus.active_player_instance_id) as Player
	
	if is_instance_valid(current_player):
		# Forward finalized placement data safely down to player mutation channels
		current_player.apply_contextual_upgrade(finalized_choice)
		
	_is_presenting_ui = false
	# Deferred: InfusionAllocationUI unpauses right after emitting, which would undo the pause of an offer draft.
	_try_process_next_level_up.call_deferred()


func reroll_current_options() -> void:
	if _is_offer_draft or not _is_presenting_ui or _cached_full_pool.is_empty():
		return

	var fresh_rolled_options := _roll_random_subset(_cached_full_pool, 3)
	EventBus.upgrade_options_ready.emit(fresh_rolled_options)


func _roll_random_subset(pool: Array[UpgradeChoice], count: int) -> Array[UpgradeChoice]:
	var results: Array[UpgradeChoice] = []
	if pool.is_empty(): 
		return results
		
	var working_pool = pool.duplicate()
	working_pool.shuffle()
	
	var actual_count = min(count, working_pool.size())
	for i in range(actual_count):
		results.append(working_pool[i])
		
	return results
