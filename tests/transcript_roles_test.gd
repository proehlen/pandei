extends GdUnitTestSuite

func test_update_kinds_map_to_roles() -> void:
	assert_that(TranscriptRoles.role_for_update({"sessionUpdate": "agent_message_chunk"})).is_equal(TranscriptRoles.ROLE_AGENT)
	assert_that(TranscriptRoles.role_for_update({"sessionUpdate": "agent_thought_chunk"})).is_equal(TranscriptRoles.ROLE_THOUGHT)
	assert_that(TranscriptRoles.role_for_update({"sessionUpdate": "user_message_chunk"})).is_equal(TranscriptRoles.ROLE_USER)
	assert_that(TranscriptRoles.role_for_update({"sessionUpdate": "tool_call"})).is_equal(TranscriptRoles.ROLE_TOOL)
	assert_that(TranscriptRoles.role_for_update({"sessionUpdate": "tool_call_update"})).is_equal(TranscriptRoles.ROLE_TOOL)
	assert_that(TranscriptRoles.role_for_update({"sessionUpdate": "usage_update"})).is_equal(TranscriptRoles.ROLE_SYS)
	assert_that(TranscriptRoles.role_for_update({})).is_equal(TranscriptRoles.ROLE_SYS)

func test_prefixes_are_distinct_per_role() -> void:
	# thoughts are not in this list: they no longer render an inline "thinking: "
	# prefix but a clickable label line (see thought_label below)
	var prefixes := [
		TranscriptRoles.prefix_for_role(TranscriptRoles.ROLE_USER),
		TranscriptRoles.prefix_for_role(TranscriptRoles.ROLE_AGENT),
		TranscriptRoles.prefix_for_role(TranscriptRoles.ROLE_TOOL),
	]
	var seen := {}
	for p in prefixes:
		seen[p] = true
	assert_that(seen.size()).is_equal(prefixes.size())  # all distinct
	assert_that(TranscriptRoles.prefix_for_role(TranscriptRoles.ROLE_USER)).is_equal("You: ")
	assert_that(TranscriptRoles.prefix_for_role(TranscriptRoles.ROLE_AGENT)).is_equal("Vibe: ")

func test_thought_label_is_thinking_while_streaming_and_thought_when_done() -> void:
	assert_that(TranscriptRoles.thought_label(true)).is_equal("thinking")
	assert_that(TranscriptRoles.thought_label(false)).is_equal("thought")

func test_thought_label_animated_cycles_trailing_dots() -> void:
	assert_that(TranscriptRoles.thought_label_animated(0)).is_equal("thinking")
	assert_that(TranscriptRoles.thought_label_animated(1)).is_equal("thinking.")
	assert_that(TranscriptRoles.thought_label_animated(2)).is_equal("thinking..")
	assert_that(TranscriptRoles.thought_label_animated(3)).is_equal("thinking...")
	assert_that(TranscriptRoles.thought_label_animated(4)).is_equal("thinking")  # wraps

func test_locations_of_extracts_tool_call_locations() -> void:
	assert_that(TranscriptRoles.locations_of({"sessionUpdate": "tool_call"})).is_equal([])
	var u := {"sessionUpdate": "tool_call", "locations": [{"path": "/home/peter/pandei/src/x.gd", "line": 12}]}
	assert_that(TranscriptRoles.locations_of(u)).is_equal([{"path": "/home/peter/pandei/src/x.gd", "line": 12}])
	assert_that(TranscriptRoles.locations_of({"locations": "bogus"})).is_equal([])
