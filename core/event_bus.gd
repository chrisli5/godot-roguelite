extends Node

@warning_ignore_start("unused_signal")
signal player_spawned(target_player_id: int)
signal player_despawned()
signal player_leveled_up(new_level: int)
signal ability_modification_completed(slot_index: int)

signal infusion_allocation_requested(chosen_choice: UpgradeChoice)
signal infusion_allocation_confirmed(chosen_choice: UpgradeChoice)

signal new_run_started(act_config: ActConfiguration)
signal room_completion_confirmed
signal map_node_selected
signal spawn_requested(node_to_spawn: Node2D)

signal upgrade_options_ready(options: Array[UpgradeChoice])
signal upgrade_selected(chosen_choice: UpgradeChoice)
signal upgrade_reroll_requested

signal scene_change_requested(target_scene_id: String)
signal scene_transition_started
signal scene_transition_finished
@warning_ignore_restore("unused_signal")

var active_player_instance_id: int = 0

func _ready() -> void:
	player_spawned.connect(_on_player_spawned)

func _on_player_spawned(instance_id: int):
	active_player_instance_id = instance_id

func _on_player_despawned():
	active_player_instance_id = 0
