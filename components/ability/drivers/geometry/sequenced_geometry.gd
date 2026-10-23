@abstract
class_name SequencedGeometry
extends GeometryDriver
## Base for geometries that deliver in steps with a delay between them (chain link, fissure).
## A subclass reads everything it needs at cast time, then hands its steps to _begin_sequence.

## Seconds between steps; 0 delivers every step at once, synchronously. Divided by (1 + SPEED_BONUS) at cast time.
@export var step_delay: float = 0.0

var _sequence_running: bool = false
var _sequence_generation: int = 0
var _sequence_step_count: int = 0
var _sequence_next_step: int = 0
var _sequence_gap: float = 0.0
var _sequence_elapsed: float = 0.0
var _sequence_on_step: Callable


func _ready() -> void:
	set_physics_process(_sequence_running)


## Runs step 0 now, then step i at i * `delay` seconds. `on_step` is `func(index: int) -> bool`; returning false ends
## the sequence early. A `delay` of 0 or less runs every step synchronously before this returns.
## Emits delivery_finished once, after the last step or the early stop. Replaces a sequence that is still running
## without a finish for the old one.
func _begin_sequence(step_count: int, delay: float, on_step: Callable) -> void:
	_sequence_generation += 1
	var generation := _sequence_generation
	_sequence_running = false
	set_physics_process(false)
	if step_count <= 0:
		delivery_finished.emit()
		return
	if not on_step.call(0) or generation != _sequence_generation:
		if generation == _sequence_generation:
			delivery_finished.emit()
		return
	if delay <= 0.0:
		for index in range(1, step_count):
			if not on_step.call(index):
				break
			if generation != _sequence_generation:
				return
		delivery_finished.emit()
		return
	if step_count == 1:
		delivery_finished.emit()
		return
	_sequence_on_step = on_step
	_sequence_step_count = step_count
	_sequence_next_step = 1
	_sequence_gap = delay
	_sequence_elapsed = 0.0
	_sequence_running = true
	set_physics_process(true)


## The step delay for a cast with `stats`: step_delay / (1 + SPEED_BONUS).
func _sequence_delay(stats: StatsContainer) -> float:
	return StatBonus.interval(stats, step_delay)


func _physics_process(delta: float) -> void:
	if not _sequence_running:
		set_physics_process(false)
		return
	_sequence_elapsed += delta
	var generation := _sequence_generation
	while _sequence_next_step < _sequence_step_count and _sequence_elapsed >= _sequence_next_step * _sequence_gap:
		var index := _sequence_next_step
		_sequence_next_step += 1
		var keep_going: bool = _sequence_on_step.call(index)
		if generation != _sequence_generation:
			return
		if not keep_going:
			_finish_sequence()
			return
	if _sequence_next_step >= _sequence_step_count:
		_finish_sequence()


func _finish_sequence() -> void:
	_sequence_running = false
	set_physics_process(false)
	_sequence_on_step = Callable()
	delivery_finished.emit()
