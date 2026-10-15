extends SceneTree

var frame: int = 0
var world: Node

func _process(_delta: float) -> bool:
	frame += 1
	if frame == 1:
		world = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
		root.add_child(world)
	elif frame == 4:
		var test_path := OS.get_environment("LOGIC_TEST")
		if test_path.is_empty():
			test_path = "res://tools/headless/logic_test.gd"
		var test = load(test_path).new()
		quit(test.run(self, world))
	return false
