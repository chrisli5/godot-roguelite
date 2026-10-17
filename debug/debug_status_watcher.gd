class_name DebugStatusWatcher
extends Node
## Debug only. Prints [STATUS] applied / refreshed / expired for every enemy (as it enters the tree, and those already
## present), whatever applied the status, including ability hits. Ticks are printed only for enemies passed to
## `watch_with_ticks`. Every line is gated by `enabled`.

static var enabled: bool = true
## Lines printed so far (lets a test tell silence from output).
static var lines_logged: int = 0

var _watched_components: Array[StatusEffectComponent] = []
var _tick_watched_components: Array[StatusEffectComponent] = []


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	for node in get_tree().root.find_children("*", "Enemy", true, false):
		watch_lifecycle.call_deferred(node as Enemy)


func _on_node_added(node: Node) -> void:
	if node is Enemy:
		# Deferred: the enemy's own components are ready by then.
		watch_lifecycle.call_deferred(node as Enemy)


## Lifecycle messages plus ticks for this enemy (used by the Burn / Chill buttons).
func watch_with_ticks(enemy: Enemy) -> void:
	watch_lifecycle(enemy)
	if not is_instance_valid(enemy) or not is_instance_valid(enemy.status_effect_component):
		return
	var component := enemy.status_effect_component
	if _tick_watched_components.has(component):
		return
	_tick_watched_components.append(component)
	var enemy_name := String(enemy.name)
	component.ticked.connect(func(i: StatusEffectInstance, damage: float) -> void:
		_log("[STATUS] %s: %s tick %.2f (ramp x%.2f, %.1fs left)" % [enemy_name, i.template.effect_id, damage, i.get_ramp_multiplier(), i.time_remaining]))


## Applied / refreshed / expired messages for this enemy, whatever applied the status.
func watch_lifecycle(enemy: Enemy) -> void:
	if not is_instance_valid(enemy) or not is_instance_valid(enemy.status_effect_component):
		return
	var component := enemy.status_effect_component
	if _watched_components.has(component):
		return
	_watched_components.append(component)
	enemy.tree_exited.connect(func() -> void:
		_watched_components.erase(component)
		_tick_watched_components.erase(component))
	var enemy_name := String(enemy.name)
	component.applied.connect(func(i: StatusEffectInstance) -> void:
		_log("[STATUS] %s: %s applied (%.1fs)" % [enemy_name, i.template.effect_id, i.time_remaining]))
	component.refreshed.connect(func(i: StatusEffectInstance) -> void:
		_log("[STATUS] %s: %s refreshed (stacks %d, %.1fs, ramp x%.2f)" % [enemy_name, i.template.effect_id, i.stacks, i.time_remaining, i.get_ramp_multiplier()]))
	component.expired.connect(func(i: StatusEffectInstance) -> void:
		_log("[STATUS] %s: %s expired" % [enemy_name, i.template.effect_id]))


static func _log(line: String) -> void:
	if not enabled:
		return
	lines_logged += 1
	print(line)
