extends RefCounted
## World smoke run: lets the world scene run 600 process frames under the error capture and fails on any engine
## or script error. Warnings are summarized, never failed. Run it through the runner:
## LOGIC_TEST=res://tools/headless/world_smoke.gd $GODOT --headless --path . -s res://tools/headless/runner.gd

const FRAMES: int = 600


## Returns 1 if any error was recorded, else 0. Same signature as the other runner scripts.
func run(scene_tree: SceneTree, _world_node: Node) -> int:
	var capture := ErrorCapture.new()
	capture.install()
	capture.begin()
	for i in range(FRAMES):
		await scene_tree.process_frame
	var entries := capture.drain()
	capture.uninstall()
	var errors := capture.errors_only(entries)
	for error in errors:
		print("FAIL  world smoke: %s:%d %s" % [error.get("file", ""), error.get("line", 0), error.get("message", "")])
	var warnings := entries.size() - errors.size()
	print("WARNINGS world smoke: %d" % warnings)
	if errors.is_empty():
		print("PASS  world smoke: %d frames, no errors" % FRAMES)
	print("WORLDSMOKE done errors=%d" % errors.size())
	return 1 if not errors.is_empty() else 0
