class_name UpgradeManager
extends Node

## Holds the raw full collection of available run upgrades that can be rolled.
## Typically seeded from a master Act database resource or individual player configuration arrays.
@export var master_upgrade_pool: Array[UpgradeBlueprintProfile] = []

var _cached_full_pool: Array[UpgradeChoice] = []
var _level_up_queue: Array[int] = []
## Level whose draft is on screen (popped from the queue but not yet resolved), or 0.
var _presenting_level: int = 0
var _is_presenting_ui: bool = false
## True while a forced evolution / Overclock offer is on screen (no reroll, no random fill).
var _is_offer_draft: bool = false
## Slots whose offer could not be built; skipped so they cannot block the queue.
var _unofferable_slots: Array[int] = []
var _pending_check_scheduled: bool = false


func _ready() -> void:
	# Restore unresolved drafts from before the room change. Processing starts from the
	# player_spawned handler once the player exists.
	if RunSession.state != null and not RunSession.state.pending_draft_levels.is_empty():
		_level_up_queue = RunSession.state.pending_draft_levels.duplicate()
	
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


## Writes unresolved draft levels (presenting level first, then the queue) into RunSession.
## Called after every change to _level_up_queue or _presenting_level.
func _sync_pending_to_run_state() -> void:
	if RunSession.state == null:
		RunSession.reset()
	var pending: Array[int] = []
	if _presenting_level > 0:
		pending.append(_presenting_level)
	pending.append_array(_level_up_queue)
	RunSession.state.pending_draft_levels = pending


func _on_player_leveled_up(new_level: int) -> void:
	_level_up_queue.append(new_level)
	_sync_pending_to_run_state()
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
	_presenting_level = next_level_to_process
	_sync_pending_to_run_state()
	
	if is_instance_valid(current_player):
		# Pass the central player reference and level context to compile our subset pool
		_cached_full_pool = generate_selection_pool(current_player, next_level_to_process)
		var rolled_options = _roll_random_subset(_cached_full_pool, 3)
		if rolled_options.is_empty():
			# Never present an empty draft: it would leave the game paused on an empty screen.
			push_warning("UpgradeManager: no upgrades available for level %d, skipping its draft." % next_level_to_process)
			_presenting_level = 0
			_sync_pending_to_run_state()
			get_tree().process_frame.connect(_try_process_next_level_up, CONNECT_ONE_SHOT)
			return
		_is_offer_draft = false
		EventBus.upgrade_options_ready.emit(rolled_options)


## Debug/support entry point: re-runs the offer and queued level-up check without touching draft state. Does nothing while a draft is on screen.
func recheck_offers() -> void:
	if _is_presenting_ui:
		return
	_try_process_next_level_up.call_deferred()


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
				# The per-element ceiling is per ability and is enforced above, in _any_ability_accepts_element ->
				# InfusionTrackerComponent.is_element_socket_allowed. Infusions are bought under slot-specific keys, so a
				# plain-key tier check here would never fire.
				var current_tier = target_player.run_ledger_component.purchase_registry.get(definition.upgrade_id, 0)
				
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


## Offer cards for `slot`: every evolution whose recipe is met (not yet bought), then, when a compound exists for the
## slot's element pair, its compound evolution and compound Overclock cards; the generic Overclock card is offered
## only when there is no compound Overclock card for the pair.
## The pair exists only at tier 1 with exactly two elements, both at the tier 1 soft cap.
func _build_offer_choices(player: Player, slot: int) -> Array[UpgradeChoice]:
	var choices: Array[UpgradeChoice] = []
	var ability: Ability = player.ability_container.get_ability_by_slot(slot)
	if not is_instance_valid(ability) or not is_instance_valid(ability.infusion_tracker_component) 			or not is_instance_valid(ability.evolution_gate_component):
		return choices
	
	var all_definitions: Array[UpgradeDefinition] = []
	var overclock_definition: UpgradeDefinition = null
	var compound_evolution: UpgradeDefinition = null
	var compound_overclock: UpgradeDefinition = null
	var pair := get_compound_pair(ability)
	for profile in master_upgrade_pool:
		if not is_instance_valid(profile): continue
		for definition in profile.definition_bundle:
			if not is_instance_valid(definition): continue
			all_definitions.append(definition)
			if definition.is_compound_card():
				if _is_compound_for_pair(definition, pair) and player.run_ledger_component.purchase_registry.get(PurchaseKey.make(definition.upgrade_id, slot), 0) <= 0:
					if definition.payload_type == UpgradeDefinition.PayloadType.ABILITY_UNLOCK and compound_evolution == null:
						compound_evolution = definition
					elif definition.payload_type == UpgradeDefinition.PayloadType.ABILITY_OVERCLOCK and compound_overclock == null:
						compound_overclock = definition
				continue
			if overclock_definition == null and definition.payload_type == UpgradeDefinition.PayloadType.ABILITY_OVERCLOCK:
				overclock_definition = definition
	
	var evolutions := ability.evolution_gate_component.evaluate_evolution_recipes(
		all_definitions, ability.infusion_tracker_component.infusion_levels, ability.data
	)
	for definition in evolutions:
		if player.run_ledger_component.purchase_registry.get(definition.upgrade_id, 0) > 0:
			continue
		choices.append(_make_offer_choice(definition, slot, ability))
	
	if compound_evolution != null:
		choices.append(_make_offer_choice(compound_evolution, slot, ability))
	if compound_overclock != null:
		choices.append(_make_offer_choice(compound_overclock, slot, ability))
	elif overclock_definition != null:
		choices.append(_make_offer_choice(overclock_definition, slot, ability))
	else:
		push_error("UpgradeManager: no ABILITY_OVERCLOCK definition in master_upgrade_pool.")
	return choices


## Elements in infusion-level index order (see Tags.get_index_from_element).
const ELEMENT_ORDER: Array[Tags.Type] = [Tags.Type.FIRE, Tags.Type.FROST, Tags.Type.LIGHTNING, Tags.Type.WIND, Tags.Type.EARTH]


## The element pair of `ability` for compound offers: exactly two elements with a level above 0, both at the tier 1
## soft cap, and the gate in TIER_1_BASE. Empty otherwise.
func get_compound_pair(ability: Ability) -> Array[Tags.Type]:
	var pair: Array[Tags.Type] = []
	if not is_instance_valid(ability) or not is_instance_valid(ability.infusion_tracker_component) or not is_instance_valid(ability.evolution_gate_component):
		return pair
	if ability.evolution_gate_component.current_state != EvolutionGateComponent.EvolutionState.TIER_1_BASE:
		return pair
	var levels := ability.infusion_tracker_component.infusion_levels
	for index in range(levels.size()):
		if levels[index] <= 0:
			continue
		if levels[index] != InfusionTrackerComponent.INFUSION_SOFT_CAP_T1 or pair.size() == 2:
			pair.clear()
			return pair
		pair.append(ELEMENT_ORDER[index])
	if pair.size() != 2:
		pair.clear()
	return pair


## True if `definition` is a compound card whose pair equals `pair` as a set.
func _is_compound_for_pair(definition: UpgradeDefinition, pair: Array[Tags.Type]) -> bool:
	if pair.size() != 2 or not definition.is_compound_card():
		return false
	return definition.compound_pair.has(pair[0]) and definition.compound_pair.has(pair[1]) and pair[0] != pair[1]


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
				
			# Evolution, Overclock and compound cards are only ever offered through the forced offer flow
			if definition.is_compound_card():
				continue
			if definition.payload_type == UpgradeDefinition.PayloadType.ABILITY_OVERCLOCK:
				continue
			if definition.payload_type == UpgradeDefinition.PayloadType.ABILITY_UNLOCK and definition.evolves_from != null:
				continue
			
			# Level Gating: Dynamic scale calculation pass
			var dynamic_req_level = profile.initial_unlock_level + (current_tier * profile.levels_per_tier)
			if processing_level < dynamic_req_level:
				continue

			# Infusions are drafted only through the separate infusion draft
			if definition.is_infusion():
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
					for slot_idx in range(AbilityContainer.MIN_SLOT, AbilityContainer.MAX_SLOT + 1):
						var ability = container.get_ability_by_slot(slot_idx)
						if is_instance_valid(ability) and is_instance_valid(ability.tag_component):
							for req_tag in definition.target_tags:
								if ability.tag_component.has_permanent_tag(req_tag):
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
	
	_presenting_level = 0
	_sync_pending_to_run_state()
	_is_offer_draft = false
	_cached_full_pool.clear()
	# Resolve coroutine tree updates on the next process frame tick cleanly
	get_tree().process_frame.connect(_try_process_next_level_up, CONNECT_ONE_SHOT)


func _on_infusion_allocation_confirmed(finalized_choice: UpgradeChoice) -> void:
	var current_player: Player = instance_from_id(EventBus.active_player_instance_id) as Player
	
	if is_instance_valid(current_player):
		# Forward finalized placement data safely down to player mutation channels
		current_player.apply_contextual_upgrade(finalized_choice)
		
	_presenting_level = 0
	_sync_pending_to_run_state()
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
