class_name DebugStatusTrigger
extends Node
## Debug only. B applies Burn, C applies Chill to the enemy nearest the player.

@export var burn_effect: StatusEffect
@export var chill_effect: StatusEffect
@export_group("Simulated Source Stats")
@export var debug_dot_damage: float = 5.0
@export var debug_duration_bonus: float = 0.0
@export_group("Logging")
@export var log_events: bool = true

var _watched_components: Array[StatusEffectComponent] = []


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_B:
		_apply_to_nearest_enemy(burn_effect)
	elif event.keycode == KEY_C:
		_apply_to_nearest_enemy(chill_effect)


func _apply_to_nearest_enemy(effect: StatusEffect) -> void:
	if not is_instance_valid(effect):
		push_warning("DebugStatusTrigger: effect resource not assigned.")
		return
	var enemy := _find_nearest_enemy()
	if enemy == null:
		return
	if log_events:
		_watch(enemy)
	enemy.status_effect_component.apply_effect(effect, debug_dot_damage, debug_duration_bonus)


func _find_nearest_enemy() -> Enemy:
	var origin := Vector2.ZERO
	var player := instance_from_id(EventBus.active_player_instance_id) as Node2D
	if is_instance_valid(player):
		origin = player.global_position
	
	var nearest: Enemy = null
	var nearest_distance := INF
	for node in get_tree().current_scene.find_children("*", "Enemy", true, false):
		var enemy := node as Enemy
		if enemy == null or not is_instance_valid(enemy.status_effect_component):
			continue
		var distance := origin.distance_squared_to(enemy.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = enemy
	return nearest


func _watch(enemy: Enemy) -> void:
	var component := enemy.status_effect_component
	if _watched_components.has(component):
		return
	_watched_components.append(component)
	var enemy_name := String(enemy.name)
	component.applied.connect(func(i: StatusEffectInstance) -> void:
		print("[STATUS] %s: %s applied (%.1fs)" % [enemy_name, i.template.effect_id, i.time_remaining]))
	component.refreshed.connect(func(i: StatusEffectInstance) -> void:
		print("[STATUS] %s: %s refreshed (stacks %d, %.1fs, ramp x%.2f)" % [enemy_name, i.template.effect_id, i.stacks, i.time_remaining, i.get_ramp_multiplier()]))
	component.ticked.connect(func(i: StatusEffectInstance, damage: float) -> void:
		print("[STATUS] %s: %s tick %.2f (ramp x%.2f, %.1fs left)" % [enemy_name, i.template.effect_id, damage, i.get_ramp_multiplier(), i.time_remaining]))
	component.expired.connect(func(i: StatusEffectInstance) -> void:
		print("[STATUS] %s: %s expired" % [enemy_name, i.template.effect_id]))
