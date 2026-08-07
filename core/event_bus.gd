extends Node

@warning_ignore("unused_signal")
signal player_leveled_up(new_level: int)
@warning_ignore("unused_signal")
signal upgrade_selected(chosen_choice: UpgradeChoice)
@warning_ignore("unused_signal")
signal upgrade_reroll_requested()
@warning_ignore("unused_signal")
signal scene_change_requested(target_scene_id: String)
@warning_ignore("unused_signal")
signal scene_transition_started
@warning_ignore("unused_signal")
signal scene_transition_finished

var active_player: Player = null
