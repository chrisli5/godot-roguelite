extends RefCounted
## Per-section fixture for the headless tests. Every section starts from the same clean state and
## frees what it created, so no check can depend on what an earlier section left behind.
##
## begin_section(): resets the shared player (ledger, abilities), RunSession, UpgradeManager state and the
## once-per-run warning flags. end_section(): frees every tracked node and resets again.

const ARCANE_BOLT_DATA := "res://resources/abilities/arcane_bolt/arcane_bolt_data.tres"

var tree: SceneTree
var world: Node
var _tracked: Array[Node] = []
## The shared error capture (Task AA); created by the first run_section().
var capture: ErrorCapture = null
var _warning_total: int = 0


func _init(scene_tree: SceneTree, world_node: Node) -> void:
	tree = scene_tree
	world = world_node


## Runs `section` between begin_section() and end_section() under the error capture, then records one check through
## `check_fn(cond: bool, msg: String)`: "error guard <section>: no unexpected engine errors". Warnings are counted, never failed.
func run_section(section: Callable, check_fn: Callable) -> void:
	var section_name := String(section.get_method())
	if capture == null:
		capture = ErrorCapture.new()
		capture.install()
	capture.begin()
	begin_section()
	await section.call()
	end_section()
	var entries := capture.drain()
	var verdict := ExpectedErrors.filter(section_name, capture.errors_only(entries))
	var unexpected: Array = verdict["unexpected"]
	var warnings := entries.size() - capture.errors_only(entries).size()
	if warnings > 0:
		print("WARNINGS %s: %d" % [section_name, warnings])
		_warning_total += warnings
	for entry in verdict["unused_entries"]:
		print("INFO  unused allow-list entry in %s: %s" % [section_name, entry.get("fragment", "")])
	var detail := ""
	for i in range(mini(3, unexpected.size())):
		var error: Dictionary = unexpected[i]
		detail += "
      %s:%d %s" % [error.get("file", ""), error.get("line", 0), error.get("message", "")]
	check_fn.call(unexpected.is_empty(), "error guard %s: no unexpected engine errors (%d allowed)%s" % [section_name, (verdict["allowed"] as Array).size(), detail])


## Uninstalls the error capture and prints the warning total. Call once at the end of a run.
func finish_guard() -> void:
	if capture != null:
		capture.uninstall()
		capture = null
	print("WARNINGS total: %d" % _warning_total)


func begin_section() -> void:
	CombatVolume._warned_missing_radius = false
	GeometryDriver._warned_area_fallback = false
	CircleBurstShape._warned_missing_radius = false
	reset_player_state()


func end_section() -> void:
	for node in _tracked:
		if is_instance_valid(node):
			if node.is_inside_tree():
				node.queue_free()
			else:
				node.free()
	_tracked.clear()
	reset_player_state()
	tree.paused = false


## Remembers a node so end_section() frees it. Returns the node.
func track(node: Node) -> Node:
	_tracked.append(node)
	return node


func get_player() -> Player:
	var event_bus := tree.root.get_node("EventBus")
	return instance_from_id(event_bus.active_player_instance_id) as Player


func get_upgrade_manager() -> UpgradeManager:
	return world.get_node("SystemControllers/UpgradeManager") as UpgradeManager


## The world's player with an empty ledger and no abilities, RunSession reset and the manager idle.
func fresh_player() -> Player:
	reset_player_state()
	return get_player()


func reset_player_state() -> void:
	var player := get_player()
	if is_instance_valid(player):
		player.run_ledger_component.restore_state({}, [])
		for slot in range(AbilityContainer.MIN_SLOT, AbilityContainer.MAX_SLOT + 1):
			player.ability_container.remove_ability_by_slot(slot)
		player.stats_container.invalidate_all_caches()
	RunSession.reset()
	var manager := get_upgrade_manager()
	if is_instance_valid(manager):
		manager._level_up_queue.clear()
		manager._presenting_level = 0
		manager._is_presenting_ui = false
		manager._is_offer_draft = false
		manager._unofferable_slots.clear()
		manager._cached_full_pool.clear()


func mount_arcane_bolt(player: Player) -> Ability:
	return player.ability_container.add_ability_from_data(load(ARCANE_BOLT_DATA))


## Spawns a bat. `data` replaces the shipped bat data when given (a test passes a throwaway duplicate).
func spawn_bat(data: EnemyData = null) -> Enemy:
	var bat := (load("res://scenes/entities/enemies/enemy.tscn") as PackedScene).instantiate() as Enemy
	bat.initialize_entity(data if data != null else load("res://resources/entities/enemy/bat.tres"))
	world.get_node("GameWorld/EntitiesContainer").add_child(bat)
	track(bat)
	return bat


## Builds an in-memory StatsContainer from {Stat.Type: float}. With a ledger it behaves like an ability lane in `slot`.
func make_stats(values: Dictionary, slot: int = 0, ledger: RunLedgerComponent = null) -> StatsContainer:
	var container := StatsContainer.new()
	track(container)
	if ledger != null:
		container.configure_slot_context(slot, ledger)
	var typed: Dictionary[Stat.Type, float] = {}
	for key in values:
		typed[key] = values[key]
	var profile := StatsProfile.new()
	profile.base_stats = typed
	container.initialize_profile(profile)
	return container
