extends Node

@warning_ignore_start("unused_signal")
signal player_leveled_up(new_level: int)
signal upgrade_selected(chosen_choice: UpgradeChoice)
signal upgrade_reroll_requested()

signal new_run_started(act_config: ActConfiguration)
signal room_completion_confirmed
signal map_node_selected
signal spawn_requested(node_to_spawn: Node2D, container_type: WorldManager.ContainerType)

signal scene_change_requested(target_scene_id: String)
signal scene_transition_started
signal scene_transition_finished
@warning_ignore_restore("unused_signal")

var active_player: Player = null
