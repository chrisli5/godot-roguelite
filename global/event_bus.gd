extends Node

signal player_leveled_up(new_level: int)
signal upgrade_selected(chosen_choice: UpgradeChoice)

var active_player: Player = null
