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

static func prefix_for_role(role: String) -> String:
	match role:
		ROLE_USER:
			return "You: "
		ROLE_AGENT:
			return "Vibe: "
		ROLE_THOUGHT:
			return "thinking: "
		ROLE_TOOL:
			return "tool: "
		ROLE_ERROR:
			return "[err] "
	return "[sys] "
