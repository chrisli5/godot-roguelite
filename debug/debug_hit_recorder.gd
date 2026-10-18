class_name DebugHitRecorder
extends Node
## Debug only. Remembers the latest hit each player ability slot dealt to an enemy, as a plain copy taken at hit time
## (the payload itself is never kept). A hit belongs to the slot whose ability's StatsContainer matches
## `payload.stats_container_id`; impact-burst hits carry the same id (their payload is a duplicate of the source), so
## they are recorded too and replace the slot's previous entry. Hits matching no player ability are ignored.

var _hits: Dictionary = {}
var _watched_hurtboxes: Array[HurtboxComponent] = []


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	for node in get_tree().root.find_children("*", "Enemy", true, false):
		_watch.call_deferred(node as Enemy)


func _on_node_added(node: Node) -> void:
	if node is Enemy:
		# Deferred: the enemy's own components are ready by then.
		_watch.call_deferred(node as Enemy)


## The latest hit per slot: {slot: {msec, enemy_name, final_damage, ...}}. A copy; changing it changes nothing here.
func get_hits() -> Dictionary:
	return _hits.duplicate(true)


## Forgets every recorded hit.
func clear() -> void:
	_hits.clear()


func _watch(enemy: Enemy) -> void:
	if not is_instance_valid(enemy) or not is_instance_valid(enemy.hurtbox_component):
		return
	var hurtbox := enemy.hurtbox_component
	if _watched_hurtboxes.has(hurtbox):
		return
	_watched_hurtboxes.append(hurtbox)
	var enemy_name := String(enemy.name)
	hurtbox.hit_received.connect(func(payload: CombatPayload) -> void: _on_hit(enemy_name, payload))
	enemy.tree_exited.connect(func() -> void: _watched_hurtboxes.erase(hurtbox))


func _on_hit(enemy_name: String, payload: CombatPayload) -> void:
	if not is_instance_valid(payload):
		return
	var slot := _slot_of(payload.stats_container_id)
	if slot == 0:
		return

	var tag_names: Array = []
	for tag in payload.damage_tags:
		tag_names.append(String(Tags.Type.keys()[tag]))
	var status_ids: Array = []
	for effect in payload.status_effects_to_apply:
		status_ids.append(effect.effect_id)
	var burst_ids: Array = []
	for burst in payload.impact_bursts:
		burst_ids.append(String(burst.burst_id))

	_hits[slot] = {
		"msec": Time.get_ticks_msec(),
		"enemy_name": enemy_name,
		"final_damage": payload.final_damage,
		"is_critical_hit": payload.is_critical_hit,
		"is_burst": payload.is_burst,
		"damage_tags": tag_names,
		"status_ids": status_ids,
		"dot_damage_snapshot": payload.dot_damage_snapshot,
		"status_duration_snapshot": payload.status_duration_snapshot,
		"status_ramp_cap_snapshot": payload.status_ramp_cap_snapshot,
		"burst_ids": burst_ids,
	}


## The player ability slot whose StatsContainer has this instance id, or 0 when none matches.
func _slot_of(stats_container_id: int) -> int:
	var player := DebugActions.find_player()
	if not is_instance_valid(player) or not is_instance_valid(player.ability_container):
		return 0
	for slot in range(AbilityContainer.MIN_SLOT, AbilityContainer.MAX_SLOT + 1):
		var ability := player.ability_container.get_ability_by_slot(slot)
		if is_instance_valid(ability) and is_instance_valid(ability.stats_container) and ability.stats_container.get_instance_id() == stats_container_id:
			return slot
	return 0
