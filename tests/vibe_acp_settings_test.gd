extends GdUnitTestSuite
## Resume-decision logic for the Vibe dock startup. The pure
## should_auto_resume() needs no EditorSettings; the EditorSettings-backed
## accessors are exercised in their headless (null settings) defaults.

func test_should_auto_resume_matrix() -> void:
	# no stored session -> nothing to resume
	assert_that(VibeAcpSettings.should_auto_resume("", false, true)).is_false()
	assert_that(VibeAcpSettings.should_auto_resume("", true, true)).is_false()
	# idle stored session + auto-resume explicitly enabled -> resume
	assert_that(VibeAcpSettings.should_auto_resume("abc", false, true)).is_true()
	# interrupted (editor closed mid-turn) -> never auto-resume, even if enabled
	assert_that(VibeAcpSettings.should_auto_resume("abc", true, true)).is_false()
	# auto-resume disabled (the default) -> never resume
	assert_that(VibeAcpSettings.should_auto_resume("abc", false, false)).is_false()
	assert_that(VibeAcpSettings.should_auto_resume("abc", true, false)).is_false()

func test_headless_defaults_are_safe() -> void:
	# Outside the editor EditorSettings is null: accessors must return the
	# safe defaults and setters must be no-ops, not errors.
	assert_that(VibeAcpSettings.is_auto_resume()).is_false()  # auto-resume OFF by default
	assert_that(VibeAcpSettings.get_last_session()).is_equal("")
	assert_that(VibeAcpSettings.get_last_session_busy()).is_false()
	assert_that(VibeAcpSettings.is_last_session_interrupted()).is_false()
	VibeAcpSettings.set_auto_resume(true)
	VibeAcpSettings.set_last_session("x")
	VibeAcpSettings.set_last_session_busy(true)
	assert_that(VibeAcpSettings.is_auto_resume()).is_false()
	assert_that(VibeAcpSettings.get_last_session()).is_equal("")
	assert_that(VibeAcpSettings.get_last_session_busy()).is_false()
