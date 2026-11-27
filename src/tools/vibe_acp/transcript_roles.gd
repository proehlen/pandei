class_name TranscriptRoles
extends RefCounted
## Maps ACP session/update payloads to transcript roles and display prefixes.
## UI-free (no colors here) so GdUnit4 tests can cover the mapping.

const ROLE_SYS := "sys"
const ROLE_USER := "user"
const ROLE_AGENT := "agent"
const ROLE_THOUGHT := "thought"
const ROLE_TOOL := "tool"
const ROLE_ERROR := "error"

const THOUGHT_LABEL_STREAMING := "Thinking"
const THOUGHT_LABEL_DONE := "Thought"

static func role_for_update(update: Dictionary) -> String:
	match str(update.get("sessionUpdate", "")):
		"agent_message_chunk":
			return ROLE_AGENT
		"agent_thought_chunk":
			return ROLE_THOUGHT
		"user_message_chunk":
			return ROLE_USER
		"tool_call", "tool_call_update":
			return ROLE_TOOL
	return ROLE_SYS

## tool_call/tool_call_update locations: [{path, line}, ...] (may be absent).
static func locations_of(update: Dictionary) -> Array:
	var l: Variant = update.get("locations", [])
	return l if l is Array else []

## Label of a thought block: "Thinking" while it streams, "Thought" once it
## finished (same wording as the vibe CLI, capitalized). Thought text is not
## rendered inline — the label is a link that opens the full text in a dialog.
static func thought_label(streaming: bool) -> String:
	return THOUGHT_LABEL_STREAMING if streaming else THOUGHT_LABEL_DONE

## Streaming label with animated trailing dots: "Thinking", "Thinking.", …
static func thought_label_animated(tick: int) -> String:
	return THOUGHT_LABEL_STREAMING + ".".repeat(tick % 4)

## Visual "mode" of a transcript item, used for blank-line separation: a whole
## blank line is inserted when the mode changes, and consecutive items of the same
## mode (e.g. a run of tool lines, or several "Thought" links) stay grouped.
static func mode_of_role(role: String) -> String:
	match role:
		ROLE_USER:
			return "user"
		ROLE_AGENT:
			return "agent"
		ROLE_THOUGHT:
			return "thought"
		ROLE_TOOL:
			return "tool"
	return "sys"

static func prefix_for_role(role: String) -> String:
	match role:
		ROLE_USER:
			return "You: "
		ROLE_AGENT:
			return "Vibe: "
		ROLE_TOOL:
			return "tool: "
		ROLE_ERROR:
			return "[err] "
	return "[sys] "
