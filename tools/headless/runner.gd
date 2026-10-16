extends SceneTree

var frame: int = 0
var world: Node

func _process(_delta: float) -> bool:
	frame += 1
	if frame == 1:
		world = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
		root.add_child(world)
	elif frame == 4:
		_run_test()
	return false


## Runs the logic test as its own coroutine: _process must not suspend, because returning from it ends the main loop.
func _run_test() -> void:
	var test_path := OS.get_environment("LOGIC_TEST")
	if test_path.is_empty():
		test_path = "res://tools/headless/logic_test.gd"
	var test = load(test_path).new()
	quit(await test.run(self, world))
