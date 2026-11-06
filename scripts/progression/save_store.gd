class_name SaveStore
extends RefCounted
## The local save file (JSON). Small, versioned, written through a temp file and a backup so a crash mid-write cannot destroy it, and
## read defensively (a damaged or hand-edited file falls back to the backup, then to a clean default; it never crashes the game).
##
## It holds game progress only. It is NOT trusted by the server: the online Hall of Fame re-validates everything. It is not secret
## either (a player can edit it), which is why records are re-checked online and why account credentials live elsewhere.

const VERSION := 1

var path: String
var data: Dictionary = {}
## Set when load found a file it could not use (tests and the UI can tell the player).
var recovered_from_damage: bool = false

func _init(file_path: String = "user://progress.json") -> void:
	path = file_path
	data = default_data()

static func default_data() -> Dictionary:
	return {
		"version": VERSION,
		"modes": {"endless": empty_record(), "ruthless": empty_record()},
		# Written the moment a Ruthless run starts and cleared when it ends. If it is still set on the next launch the app was killed
		# mid-run: that run is closed as abandoned and can never be resumed (there is deliberately no level or state to resume from).
		"ruthless_run": {"active": false, "run_id": "", "started_unix": 0},
		"last_run": {},
		# Reports to the server that have not been delivered yet (see RunSync): [{"kind": "level"|"end", "run": server run id, ...}].
		"queue": [],
	}

static func empty_record() -> Dictionary:
	return {"best_level": 0, "best_seconds": 0.0, "best_unix": 0, "runs": 0, "extractions": 0}

## True if (level, seconds) beats the record: a higher completed level, or the same level in a faster time.
static func is_better(record: Dictionary, level: int, seconds: float) -> bool:
	var best_level := int(record.get("best_level", 0))
	if level > best_level:
		return true
	return level == best_level and level > 0 and seconds < float(record.get("best_seconds", INF))

func record(mode_key: String) -> Dictionary:
	var modes: Dictionary = data["modes"]
	return modes[mode_key]

## Returns true if the record was improved.
func submit_level(mode_key: String, level: int, seconds: float) -> bool:
	var rec := record(mode_key)
	if level < 1 or seconds < 0.0 or not is_better(rec, level, seconds):
		return false
	rec["best_level"] = level
	rec["best_seconds"] = seconds
	rec["best_unix"] = int(Time.get_unix_time_from_system())
	return true

func save() -> bool:
	var temp := path + ".tmp"
	var backup := path + ".bak"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(backup)
		DirAccess.rename_absolute(path, backup)
	if DirAccess.rename_absolute(temp, path) != OK:
		return false
	DirAccess.remove_absolute(backup)
	return true

## Load from disk, falling back to the backup and then to a clean default. Always leaves `data` valid.
func load_data() -> void:
	recovered_from_damage = false
	data = default_data()
	for candidate in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(candidate))
		if parsed is Dictionary:
			_merge(parsed)
			recovered_from_damage = candidate != path
			return
		recovered_from_damage = true

## Copy only the fields we know, with the right types, so a damaged file cannot inject nonsense.
func _merge(source: Dictionary) -> void:
	var modes: Variant = source.get("modes", {})
	if modes is Dictionary:
		for mode_key in ["endless", "ruthless"]:
			var raw: Variant = (modes as Dictionary).get(mode_key, {})
			if not raw is Dictionary:
				continue
			var from: Dictionary = raw
			var rec := record(mode_key)
			rec["best_level"] = maxi(int(from.get("best_level", 0)), 0)
			rec["best_seconds"] = maxf(float(from.get("best_seconds", 0.0)), 0.0)
			rec["best_unix"] = maxi(int(from.get("best_unix", 0)), 0)
			rec["runs"] = maxi(int(from.get("runs", 0)), 0)
			rec["extractions"] = maxi(int(from.get("extractions", 0)), 0)
	var run: Variant = source.get("ruthless_run", {})
	if run is Dictionary:
		var r: Dictionary = run
		data["ruthless_run"] = {"active": bool(r.get("active", false)), "run_id": str(r.get("run_id", "")), "started_unix": maxi(int(r.get("started_unix", 0)), 0)}
	var queue: Variant = source.get("queue", [])
	if queue is Array:
		for raw in queue:
			if raw is Dictionary and str(raw.get("kind", "")) in ["level", "end"] and str(raw.get("run", "")).length() == 36:
				var entry := {"kind": str(raw["kind"]), "run": str(raw["run"])}
				if entry["kind"] == "level":
					entry["level"] = maxi(int(raw.get("level", 0)), 0)
					entry["seconds"] = maxf(float(raw.get("seconds", 0.0)), 0.0)
				else:
					entry["reason"] = str(raw.get("reason", "left"))
				(data["queue"] as Array).append(entry)
	var last: Variant = source.get("last_run", {})
	if last is Dictionary:
		data["last_run"] = (last as Dictionary).duplicate()
