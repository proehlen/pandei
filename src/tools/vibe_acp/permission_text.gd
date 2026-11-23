class_name PermissionText
extends RefCounted
## Human-readable approval text for VibePermissionDialog.
## Pure (no UI) so GdUnit4 tests can cover it without a scene tree.
##
## Why this exists: ACP session/request_permission often carries only a
## toolCallId hash (e.g. "effect-4a1cb37b-…"), which is impossible to eyeball
## before approving. The dock saw the matching tool_call session update
## earlier (title/kind/rawInput), so it passes those updates in known_by_id
## and the hash gets resolved into a real summary of what is being approved.

const RAW_JSON_CAP := 1200   # max chars of the scrollable raw payload
const FIELD_CAP := 300      # max chars per summary line
const MAX_INPUT_LINES := 8  # max summary lines produced from rawInput

## Bounded multi-line summary shown at the top of the dialog.
static func summarize(tool_call: Dictionary, known_by_id: Dictionary = {}) -> String:
	var m := merged_view(tool_call, known_by_id)
	var lines: Array[String] = []
	var kind := str(m.get("kind", ""))
	var title := str(m.get("title", ""))
	if title == "":
		title = ("a '%s' tool call" % kind) if kind != "" else "a tool call"
	lines.append("Tool: " + _clip(title))
	if kind != "":
		lines.append("Kind: " + kind)
	for line in _input_lines(m.get("rawInput", null)):
		lines.append(line)
	var loc_parts: Array[String] = []
	for loc in TranscriptRoles.locations_of(m):
		if loc is Dictionary:
			var p := str(loc.get("path", ""))
			var ln := int(loc.get("line", 0))
			if p != "":
				loc_parts.append(p + (":%d" % ln if ln > 0 else ""))
	if loc_parts.size() > 0:
		lines.append("Locations: " + ", ".join(loc_parts))
	var id := str(m.get("toolCallId", ""))
	if id != "":
		lines.append("Tool call ID: " + _short_id(id))
	return "\n".join(lines)

## Scrollable raw payload for the dialog's detail area (capped so the dialog
## keeps a bounded height no matter how big the request is).
static func raw_json(tool_call: Dictionary, known_by_id: Dictionary = {}) -> String:
	var raw := JSON.stringify(merged_view(tool_call, known_by_id), "  ")
	if raw.length() > RAW_JSON_CAP:
		raw = raw.substr(0, RAW_JSON_CAP) + "\n… truncated"
	return raw

## Request payload overlaid on the earlier tool_call update with the same
## toolCallId (request keys win), so a hash-only request gains title/kind/
## rawInput/locations from what the agent announced before asking permission.
static func merged_view(tool_call: Dictionary, known_by_id: Dictionary) -> Dictionary:
	var id := str(tool_call.get("toolCallId", ""))
	var known: Variant = known_by_id.get(id, {}) if id != "" else {}
	if not known is Dictionary or (known as Dictionary).is_empty():
		return tool_call
	var merged: Dictionary = (known as Dictionary).duplicate(true)
	for k in tool_call:
		merged[k] = tool_call[k]
	return merged

static func _input_lines(raw: Variant) -> Array[String]:
	var lines: Array[String] = []
	if raw == null:
		return lines
	if raw is String:
		if str(raw) != "":
			lines.append("Input: " + _clip(str(raw)))
		return lines
	if raw is Dictionary:
		var d: Dictionary = raw
		if d.has("command"):
			lines.append("Command: " + _clip(str(d["command"])))
		if d.has("path"):
			var suffix := ""
			var content: Variant = d.get("content", "")
			if content is String and str(content) != "":
				suffix = " (%d chars of content)" % str(content).length()
			lines.append("File: " + str(d["path"]) + suffix)
		for k in d.keys():
			if str(k) == "command" or str(k) == "path" or str(k) == "content":
				continue
			if lines.size() >= MAX_INPUT_LINES:
				lines.append("… more fields in the raw payload below")
				break
			lines.append("%s: %s" % [str(k), _clip(_stringify(d[k]))])
		return lines
	lines.append("Input: " + _clip(_stringify(raw)))
	return lines

static func _stringify(v: Variant) -> String:
	return JSON.stringify(v) if (v is Dictionary or v is Array) else str(v)

static func _clip(s: String) -> String:
	return s if s.length() <= FIELD_CAP else s.substr(0, FIELD_CAP) + "…"

## Shortened id for the header line; the full id stays in the raw payload.
static func _short_id(id: String) -> String:
	return id if id.length() <= 20 else id.substr(0, 12) + "…" + id.substr(id.length() - 4)
