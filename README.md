<title>Job Application Assistant</title>

# Job Application Assistant

Trigger: **fn+F5**.

A tiny macOS background tool: press **fn+F5** anywhere, it screenshots your screen,
hands it to a local [Claude Code](https://claude.com/claude-code) session along with
your own background material (resume, notes, whatever), and pops up a direct answer
— also copied to your clipboard.

Built for filling out job applications faster: multiple-choice questions, free-text
fields, "tell us about a time you..." — point your screen at the question, hit the
hotkey, paste.

## How it works

- [Hammerspoon](https://www.hammerspoon.org/) runs `init.lua` in the background and
  listens for **fn+F5** via a raw event tap (not a normal hotkey binding — macOS's Fn
  modifier isn't exposed to Hammerspoon's regular `hs.hotkey.bind` API reliably).
- On trigger: `screencapture` grabs the screen silently, then `claude -p` (Claude
  Code's headless mode, restricted to the `Read` tool only) reads it and answers.
- **Session reuse, not re-reading**: the first-ever run reads your background files
  and starts a Claude Code session under a fixed UUID (saved to
  `context/session_id.txt`). Every run after that resumes that same session and
  skips re-reading the files — cheaper and faster. If the session ever expires or
  gets pruned, it self-heals by re-loading the context once, automatically.
- The answer is copied to your clipboard and shown in a small floating window
  (**F6** to dismiss).

## Setup

1. Install [Hammerspoon](https://www.hammerspoon.org/) (`brew install --cask hammerspoon`)
   and [Claude Code](https://claude.com/claude-code) (`npm install -g @anthropic-ai/claude-code`
   or see their docs).
2. Copy `init.lua` to `~/.hammerspoon/init.lua`.
3. Find your Claude Code binary path (`which claude`) and set `CLAUDE_BIN` at the top
   of `init.lua` to that absolute path — GUI apps like Hammerspoon don't inherit your
   shell's `PATH`, so a bare `"claude"` usually won't resolve.
4. Drop your own resume/notes into `~/.hammerspoon/context/` (see
   `context/README.md`), and update the file list in `FIRST_PROMPT` in `init.lua` if
   your filenames differ.
5. Launch Hammerspoon. On first launch it'll ask for:
   - **Accessibility** — required for the global hotkey.
   - **Screen Recording** — required for the screenshot (System Settings → Privacy &
     Security → Screen Recording → enable Hammerspoon).
6. Press **fn+F5** on any screen with a question visible.

Optional: add Hammerspoon to Login Items (System Settings → General → Login Items)
so this survives reboots.

## Known limitations

- Screenshots the *entire* main display, not just the focused window.
- The answer window always appears on your primary display, even with multiple
  monitors.
- No timeout — a slow response just leaves you waiting with no progress indicator
  beyond the initial "Reading screen..." flash.
- Session-resume caching is time-sensitive: rapid presses within the same sitting
  are cheap (prompt caching), but long gaps between uses mean an occasional
  full-price context resend even without an explicit re-read.

## License

MIT
