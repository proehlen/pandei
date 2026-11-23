# Vibe ACP (Godot editor plugin)

Chat with [Mistral Vibe](https://mistral.ai) from a bottom-panel dock inside the
Godot editor, via the **Agent Client Protocol (ACP)**: the plugin spawns
`vibe-acp` and speaks newline-delimited JSON-RPC 2.0 with it over the process's
stdio pipe. No bridge process or network socket is needed — Godot 4's
`OS.execute_with_pipe()` returns a non-blocking bidirectional `FileAccess`,
which the plugin polls from `_process`.

## Enable

Project → Editor Settings → Plugins → **Vibe ACP** (enabled by default in this
repo via `project.godot`). The dock appears in the bottom panel under the
**Vibe** tab. It auto-connects on editor start (`vibe_acp/auto_connect`).

The plugin needs the `vibe-acp` executable (installed with
`uv tool install mistral-vibe`). It is auto-detected from `~/.local/bin` and
`PATH`; override with the `vibe_acp/executable` editor setting. Sign in via the
CLI once (`vibe --setup`) if you haven't — the plugin does not implement
browser auth.

## Using the dock

- **Connect / disconnect** — Connect is hidden while connected (auto-connect is
  on); a small ✕ button disconnects and kills the agent process.
- **Session dropdown** — populated automatically (`session/list`); pick one to
  resume it (`session/load`). **List/refresh** re-queries. **New** starts a
  fresh session and clears the transcript.
- **Mode dropdown** — approval mode (`session/set_mode`: ask / accept-edits /
  smart-approve / auto-approve), persisted in `vibe_acp/approval_mode`.
- **Compact** — sends `/compact` so the agent summarizes its context.
- **Transcript** — roles are visually distinct: `You:` (blue), `Vibe:`,
  `thinking:` (gray italic), `tool:` (yellow), `[sys]`/`[err]`. Tool lines with
  file locations render clickable `res://path:line` links that open the file in
  the editor. Long lines wrap.
- **Input** — Ctrl/Cmd+Enter sends; **Stop** sends `session/cancel`.
- Tool-call approvals pop a dialog (`session/request_permission`); file writes
  via `fs/write_text_file` pop a confirmation. Both are cancelled automatically
  if the agent disconnects.

## Architecture

```
addons/vibe_acp/plugin.cfg      # shim only; script path must be RELATIVE ("../../src/...")
src/tools/vibe_acp/
├── plugin.gd                   # EditorPlugin: adds/removes the dock
├── vibe_dock.gd                # UI + client lifecycle + dialogs + rendering
├── permission_dialog.gd        # session/request_permission UI
├── acp_client.gd               # high-level ACP ops (initialize/new/load/list/prompt/cancel/set_mode)
├── acp_dispatcher.gd           # routes responses / notifications / server→client requests
├── acp_connection.gd           # poll()-based message pump, request ids
├── acp_codec.gd                # newline-delimited JSON-RPC framing (AcpCodec.LineBuffer)
├── acp_transport.gd / pipe_transport.gd  # transport iface + vibe-acp stdio pipe
├── acp_fs_handler.gd           # fs/read|write confined to the project root
├── transcript_roles.gd         # update-kind → role/prefix mapping (UI-free)
└── vibe_acp_settings.gd        # EditorSettings keys
tests/                          # GdUnit4 suites (codec, dispatcher, client, fs, roles, rendering)
```

Data flow: `vibe_dock._process` → `AcpClient.pump()` → `AcpConnection.poll()`
→ `AcpDispatcher.handle_message()` → signals → dock renders.

## Editor settings keys

| Key | Default | Meaning |
|---|---|---|
| `vibe_acp/executable` | auto-detect | path to the `vibe-acp` binary |
| `vibe_acp/auto_connect` | `true` | connect on editor start |
| `vibe_acp/last_session_id` | — | session to resume (written only after your first prompt) |
| `vibe_acp/approval_mode` | — | approval mode applied on session start |

## Tests / verification

```bash
godot --headless --path . --import
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/ --ignoreHeadlessMode
```

## Known limitations

- **No history replay after resume**: `session/load` does not resend past
  `session/update`s, so the transcript starts empty after an editor restart.
  Full history lives in `~/.vibe/logs/session/…` (view with `vibe --resume`).
- **Sessions with zero input are not persisted** by vibe-acp; that's why
  `last_session_id` is only stored after the first prompt is sent.
- `terminal/*` requests are declined — the agent uses its own shell tools.
- Emoji in agent messages need a system emoji font (e.g.
  `sudo apt install fonts-noto-color-emoji`) and an editor restart.
- `plugin.cfg`'s `script=` must be a path **relative** to the cfg file.
