extends Node

@warning_ignore("unused_signal")
signal player_leveled_up(new_level: int)
@warning_ignore("unused_signal")
signal upgrade_selected(chosen_choice: UpgradeChoice)
@warning_ignore("unused_signal")
signal upgrade_reroll_requested()

var active_player: Player = null
