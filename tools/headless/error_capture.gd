class_name ErrorCapture
extends Logger
## Records the engine errors, script errors and warnings Godot prints, so a headless check can fail on them.
## install() registers it with OS.add_logger; begin() starts a fresh window; drain() returns what was recorded since.
## Log callbacks may come from any thread, so every access to the buffer holds a mutex.

var _mutex := Mutex.new()
var _entries: Array[Dictionary] = []
var _recording: bool = false
var _installed: bool = false
var _error_count: int = 0
var _warning_count: int = 0


## Registers this logger with the engine. Call once per run, and uninstall() at the end.
func install() -> void:
	if _installed:
		return
	_installed = true
	OS.add_logger(self)


## Removes this logger from the engine and stops recording.
func uninstall() -> void:
	if not _installed:
		return
	_installed = false
	_mutex.lock()
	_recording = false
	_mutex.unlock()
	OS.remove_logger(self)


## Clears everything recorded and starts recording.
func begin() -> void:
	_mutex.lock()
	_entries.clear()
	_error_count = 0
	_warning_count = 0
	_recording = true
	_mutex.unlock()


## Returns everything recorded so far and clears it. Recording continues.
func drain() -> Array[Dictionary]:
	_mutex.lock()
	var result := _entries.duplicate()
	_entries.clear()
	_mutex.unlock()
	var typed: Array[Dictionary] = []
	typed.assign(result)
	return typed


## The entries of `entries` whose kind is "error" or "script" (everything but warnings).
func errors_only(entries: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in entries:
		if entry.get("kind", "error") != "warning":
			result.append(entry)
	return result


## Errors recorded since begin() (not reduced by drain()).
func error_count() -> int:
	_mutex.lock()
	var count := _error_count
	_mutex.unlock()
	return count


## Warnings recorded since begin() (not reduced by drain()).
func warning_count() -> int:
	_mutex.lock()
	var count := _warning_count
	_mutex.unlock()
	return count


func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	var kind := "error"
	if error_type == Logger.ERROR_TYPE_WARNING:
		kind = "warning"
	elif error_type == Logger.ERROR_TYPE_SCRIPT:
		kind = "script"
	var message := code if rationale.is_empty() else (rationale if code.is_empty() else "%s %s" % [code, rationale])
	_mutex.lock()
	if _recording:
		_entries.append({
			"function": function, "file": file, "line": line, "code": code,
			"rationale": rationale, "kind": kind, "message": message,
		})
		if kind == "warning":
			_warning_count += 1
		else:
			_error_count += 1
	_mutex.unlock()


func _log_message(_message: String, _error: bool) -> void:
	pass
