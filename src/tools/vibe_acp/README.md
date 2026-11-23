# Vibe ACP editor tool

Editor plugin that docks a chat panel ("Vibe") into Godot's bottom panel and
talks to a `vibe-acp` process over stdio using the Agent Client Protocol.
`plugin.gd` only registers the dock; all logic lives in this directory:

- `vibe_dock.gd` — the dock: header controls (Connect/Disconnect, New,
  Compact, Session and Mode dropdowns), transcript, input row, and the slim
  status bar (git branch dropdown, connection/session, turn state, token
  usage, separated by bars)
- `git_branch.gd` — current-branch read, local-branch listing and branch
  switching for the status-bar dropdown (pure `.git` file reads, except
  `switch_branch()`, which runs `git checkout` behind an injectable runner)
- `acp_client.gd` / `acp_connection.gd` / `acp_dispatcher.gd` / `acp_codec.gd`
  — ACP protocol client, connection, request dispatcher, JSON-RPC codec
- `pipe_transport.gd` / `acp_transport.gd` — stdio pipe transport abstraction
- `acp_fs_handler.gd` — `fs/read_text_file` / `fs/write_text_file` handling
- `permission_dialog.gd` / `permission_text.gd` — permission-request dialog
- `vibe_acp_settings.gd` — editor settings (executable, approval mode, stored
  session, auto-connect/auto-resume flags)
- `transcript_roles.gd` — transcript role colors and prefixes

Tests live in `tests/` (`vibe_dock_*_test.gd`, `git_branch_test.gd`,
`acp_*_test.gd`, …).

## TODO

- [ ] Sessions dropdown pre-selects the previous session: on starting Godot
      (and possibly also when starting a New session via the panel button —
      needs checking), the Sessions OptionButton has the previous session
      selected by default, making it impossible to select a different session
      without first selecting an even earlier one. Likely culprit:
      `_on_sessions_listed()` in `vibe_dock.gd` auto-selects the item whose
      metadata equals `client.session_id` after `list_sessions()`.
