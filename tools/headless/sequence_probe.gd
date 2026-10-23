extends SequencedGeometry
## Test-only subclass of SequencedGeometry: records which steps ran and how many times delivery finished.

var steps_run: Array[int] = []
var finished_count: int = 0
## The step index at which on_step returns false (-1 never stops).
var stop_at: int = -1


func _init() -> void:
	delivery_finished.connect(_on_finished)


func execute_geometry(_query_results: Dictionary, _final_payload: CombatPayload) -> void:
	pass


## Starts a sequence of `count` steps `delay` seconds apart.
func start(count: int, delay: float) -> void:
	_begin_sequence(count, delay, _on_step)


func _on_step(index: int) -> bool:
	steps_run.append(index)
	return index != stop_at


func _on_finished() -> void:
	finished_count += 1
