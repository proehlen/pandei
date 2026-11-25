# Vibe ACP (Godot editor plugin)

Chat with [Mistral Vibe](https://mistral.ai) from a bottom-panel dock inside the
Godot editor, via the **Agent Client Protocol (ACP)**: the plugin spawns
`vibe-acp` and speaks newline-delimited JSON-RPC 2.0 with it over the process's
stdio pipe. No bridge process or network socket is needed — Godot 4's
`OS.execute_with_pipe()` returns a non-blocking bidirectional `FileAccess`,
which the plugin polls from `_process`.

This README is the canonical doc for the tool. All plugin logic lives in this
directory (`src/tools/vibe_acp/`); `addons/vibe_acp/` contains only the
`plugin.cfg` shim that registers the plugin.

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
  resume it (`session/load`). The selection always mirrors the current session:
  it shows the current session's entry when that session appears in the list,
  and stays **blank** while the current session is not listed yet (a fresh
  session is not persisted by vibe-acp until its first prompt — right after
  editor start or **New**). **List/refresh** re-queries. **New** starts a fresh
  session and clears the transcript.
- **Startup session** — on editor start the dock opens a **new** session by
  default (no auto-resume), so quitting the editor mid-turn can never make the
  agent silently pick up an abandoned task on the next start. Resume a previous
  session manually via the Session dropdown. Set `vibe_acp/auto_resume=true` to
  auto-resume the last session instead — but even then, a session that was
  still working when the editor closed (`vibe_acp/last_session_busy`) is
  skipped and only resumable manually.
- **Mode dropdown** — approval mode (`session/set_mode`: ask / accept-edits /
  smart-approve / auto-approve), persisted in `vibe_acp/approval_mode`.
- **Compact** — sends `/compact` so the agent summarizes its context.
- **Status bar** — a slim row *beneath* the prompt input (smaller font, on a
  translucent dark background strip so it reads as its own section below the
  input, distinct from the editor's bottom panel/tab bar) holds all passive
  status text, keeping the header for interactive controls only. Sections are
  separated by vertical bars: the current **git branch** of the project
  (`git: <branch>`, `HEAD@<sha>` when detached, hidden when the project is not
  a git checkout; refreshed every second, so switching branches in a terminal
  shows up live) as a dropdown — pick another local branch to `git checkout`
  it, or the trailing **New…** entry to create and switch to a new branch via
  a name dialog (OK/Cancel), the connection/session state, the turn state
  (`working…` / `stopping…` / `idle`) and the token usage. Sections without
  text are hidden and exactly one bar separates consecutive visible sections.
- **Transcript** — roles are visually distinct: `You:` (blue), `Vibe:`,
  `thinking:` (gray italic), `tool:` (yellow), `[sys]`/`[err]`. Tool lines with
  file locations render clickable `res://path:line` links that open the file in
  the editor. Long lines wrap.
- **Input** — long prompts wrap inside the multi-line box. Ctrl/Cmd+Enter
  sends. The **Send** button is enabled exactly
  when Ctrl+Enter would work (both use the same `_can_send()` check: connected,
  a session is ready, and no turn is running). **Stop** sends
  `session/cancel` (a notification per the ACP spec — no response is expected
  or awaited) and is only enabled while a turn is actually running. Because
  the cancel is asynchronous — the turn ends when `prompt_finished` arrives —
  the button switches to a busy **Stopping…** state after being pressed, so it
  can't be spammed while a previous stop is still in flight.
- Tool-call approvals pop a dialog (`session/request_permission`); file writes
  via `fs/write_text_file` pop a confirmation. Both are cancelled automatically
  if the agent disconnects.

## Architecture

```
addons/vibe_acp/plugin.cfg      # shim only; script path must be RELATIVE ("../../src/...")
src/tools/vibe_acp/
├── plugin.gd                   # EditorPlugin: adds/removes the dock
├── vibe_dock.gd                # the dock: header controls (Connect/Disconnect, New, Compact, Session and Mode dropdowns), transcript, input row, and the slim status bar (git branch dropdown, connection/session, turn state, token usage, separated by bars)
├── permission_dialog.gd / permission_text.gd   # permission-request dialog
├── new_branch_dialog.gd        # "New branch" name dialog (OK/Cancel) behind the branch dropdown's New… entry
├── acp_client.gd               # high-level ACP ops: initialize/new/load/list/prompt/cancel/set_mode
├── acp_dispatcher.gd           # routes responses / notifications / server→client requests
├── acp_connection.gd           # poll()-based message pump, request ids
├── acp_codec.gd                # newline-delimited JSON-RPC framing (AcpCodec.LineBuffer)
├── acp_transport.gd / pipe_transport.gd  # transport iface + stdio pipe transport abstraction
├── acp_fs_handler.gd           # fs/read_text_file / fs/write_text_file, confined to the project root
├── git_branch.gd               # current-branch read, local-branch listing, branch switching and branch creation for the status-bar dropdown (pure .git file reads, except switch_branch()/create_branch(), which run git checkout behind an injectable runner)
├── transcript_roles.gd         # transcript role colors and prefixes (update-kind → role/prefix mapping, UI-free)
└── vibe_acp_settings.gd        # editor settings (executable, approval mode, stored session, auto-connect/auto-resume flags)
tests/                          # GdUnit4 suites (vibe_dock_*_test.gd, git_branch_test.gd, acp_*_test.gd, …)
```

Data flow: `vibe_dock._process` → `AcpClient.pump()` → `AcpConnection.poll()`
→ `AcpDispatcher.handle_message()` → signals → dock renders.

## Editor settings keys

| Key | Default | Meaning |
|---|---|---|
| `vibe_acp/executable` | auto-detect | path to the `vibe-acp` binary |
| `vibe_acp/auto_connect` | `true` | connect on editor start |
| `vibe_acp/auto_resume` | `false` | auto-resume the last session on editor start (interrupted sessions are never auto-resumed) |
| `vibe_acp/last_session_id` | — | last active session (written only after your first prompt) |
| `vibe_acp/last_session_busy` | `false` | internal: last session was mid-turn when the editor/agent went away |
| `vibe_acp/approval_mode` | — | approval mode applied on session start |

## Tests / verification

```bash
godot --headless --path . --import
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/ --ignoreHeadlessMode
```

## TODO

- **Editor crash when dragging the permission dialog** (2026-11-23): moving the
  "Vibe requests permission" dialog (`permission_dialog.gd`,
  `session/request_permission`) by its titlebar crashed the whole editor to
  desktop with **signal 11 (SIGSEGV)**. Details live in `~/.xsession-errors` —
  the file's only `handle_crash` entry: `Program crashed with signal 11`, engine
  `v4.7.2.stable.official (ed1daf0bf001b61586d9930840f2f1394092c079)`, binary
  `~/.local/share/godot/4.7.2/godot`, load address `0x400000`, 15-frame C++
  backtrace but **unsymbolized** (official stripped binary; top frames
  `main+0x229df84`, `main+0x17b68a0`, `main+0x1388d0c`, `main+0x1734ae4`,
  `main+0x1739b00`, `main+0x3e0be80`, … `main+0x11d08`, then libc startup). The
  editor's own log files (`~/.local/share/godot/app_userdata/pandei/logs/`) only
  contain headless runs (latest is the GdUnit4 suite, exit code 0), so the crash
  left no log there; no coredump either (`coredumpctl` not installed,
  `/var/lib/systemd/coredump/` empty, no journal entries). Next step: reproduce
  with a debug/self-compiled build and symbolize the offsets with `addr2line` to
  get real frames; until fixed, don't drag the dialog — answer it in place.
## Known limitations

- **No history replay after resume**: `session/load` does not resend past
  `session/update`s, so the transcript starts empty after an editor restart.
  Full history lives in `~/.vibe/logs/session/…` (view with `vibe --resume`).
- **Interrupted sessions are not auto-resumed**: if the editor is quit (or the
  agent process dies) while a prompt is in flight, `vibe_acp/last_session_busy`
  stays set and the next start opens a fresh session instead. The interrupted
  session remains in the Session dropdown for a manual resume.
- **Sessions with zero input are not persisted** by vibe-acp; that's why
  `last_session_id` is only stored after the first prompt is sent.
- `terminal/*` requests are declined — the agent uses its own shell tools.
- Emoji in agent messages need a system emoji font (e.g.
  `sudo apt install fonts-noto-color-emoji`) and an editor restart.
- `plugin.cfg`'s `script=` must be a path **relative** to the cfg file.
