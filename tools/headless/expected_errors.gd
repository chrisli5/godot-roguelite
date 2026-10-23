class_name ExpectedErrors
extends RefCounted
## Engine errors the headless tests know about and accept. Each entry names the section it is allowed in, a
## fragment of the message, how many times it may appear in that section, and why it is accepted.
## A new section that deliberately triggers an engine error must add an entry. Keep this list small.

const EXPECTED: Array[Dictionary] = []


## Splits the error entries of `section` into {"unexpected", "allowed", "unused_entries"}, using EXPECTED.
static func filter(section: String, errors: Array[Dictionary], entries: Array[Dictionary] = EXPECTED) -> Dictionary:
	var unexpected: Array[Dictionary] = []
	var allowed: Array[Dictionary] = []
	var used: Dictionary = {}
	for error in errors:
		var matched := -1
		for i in range(entries.size()):
			var entry := entries[i]
			if str(entry.get("section", "")) != section:
				continue
			var fragment := str(entry.get("fragment", ""))
			if fragment.is_empty() or not str(error.get("message", "")).contains(fragment):
				continue
			if int(used.get(i, 0)) >= int(entry.get("max_count", 0)):
				continue
			matched = i
			break
		if matched >= 0:
			used[matched] = int(used.get(matched, 0)) + 1
			allowed.append(error)
		else:
			unexpected.append(error)
	var unused: Array[Dictionary] = []
	for i in range(entries.size()):
		if str(entries[i].get("section", "")) == section and not used.has(i):
			unused.append(entries[i])
	return {"unexpected": unexpected, "allowed": allowed, "unused_entries": unused}
