extends SceneTree

var failures: int = 0
var checked: int = 0

var _done: bool = false

func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_scan("res://")
	print("LOADCHECK checked=%d failures=%d" % [checked, failures])
	quit(1 if failures > 0 else 0)
	return true

func _scan(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		if sub.begins_with(".") or sub == "addons" or dir_path.path_join(sub) == "res://tools":
			continue
		_scan(dir_path.path_join(sub))
	for file in dir.get_files():
		var ext := file.get_extension()
		if ext in ["gd", "tscn", "tres"]:
			var path := dir_path.path_join(file)
			checked += 1
			var res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
			if res == null:
				failures += 1
				print("LOADCHECK FAIL: ", path)
