class_name RunSession
extends RefCounted

## Holds the current run's RunState for as long as the game process is alive.
## A static class instead of an autoload, so no project settings need to change.
## Lifecycle: reset() when a new run starts, Player writes into it as it leaves a room,
## and the next room's Player reads from it as it spawns.

static var state: RunState = null


static func reset() -> void:
	state = RunState.new()


static func has_player_snapshot() -> bool:
	return state != null and state.has_player_snapshot
