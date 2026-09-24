<title>Job Application Assistant</title>

# Job Application Assistant

Trigger: **fn+A**.

A tiny macOS background tool: press **fn+A** anywhere, it screenshots your screen,
hands it to a local [Claude Code](https://claude.com/claude-code) session along with
your own background material (resume, notes, whatever), and either **types the
answer directly into the field you're in** or pops it up for you to read/copy —
always backed up to your clipboard either way.

Built for filling out job applications faster: multiple-choice questions, free-text
fields, "tell us about a time you..." — point your screen at the question, hit the
hotkey.

## How it works

- [Hammerspoon](https://www.hammerspoon.org/) runs `init.lua` in the background and
  listens for **fn+A** via a raw event tap (not a normal hotkey binding — macOS's Fn
  modifier isn't exposed to Hammerspoon's regular `hs.hotkey.bind` API reliably).
- On trigger: it snapshots which field is currently focused (via the Accessibility
  API), `screencapture` grabs the screen silently, then `claude -p` (Claude Code's
  headless mode, restricted to the `Read` tool only) reads it and answers.
- **Session reuse, not re-reading**: the first-ever run reads your background files
  and starts a Claude Code session under a fixed UUID (saved to
  `context/session_id.txt`). Every run after that resumes that same session and
  skips re-reading the files — cheaper and faster. If the session ever expires or
  gets pruned, it self-heals by re-loading the context once, automatically.
- **Result handling depends on what's on screen**:
  - One question/field visible, nothing else: the answer is typed directly into
    the focused field via simulated keystrokes, no popup.
  - Several fields visible, one of them focused: that one gets typed in, *and* a
    popup still lists every other visible question's answer so you can handle the
    rest yourself.
  - Several fields, can't tell which is focused (e.g. a review screen): nothing
    gets typed, just the popup with everything listed.
  - Dropdowns, checkboxes, and radio buttons are never auto-filled (clicking the
    right option is a different, riskier mechanism, deliberately out of scope for
    now) — those always fall back to the popup telling you the right choice.
- **Auto-fill safety guards**: it only types if the field that's focused right now
  is the *exact same one* that was focused when you pressed fn+A (so clicking
  elsewhere while it's thinking cancels auto-fill, falls back to the popup), and
  only into real text fields — never password fields. If an answer required
  guessing a fact not in your background material (e.g. an exact zip code),
  auto-fill is skipped entirely for that answer and it goes to the popup instead,
  flagged with a ⚠ caveat note, so a guess never gets typed in blind.
- **Esc** or **F6** dismisses the popup when one's shown.

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
   - **Accessibility** — required for the global hotkey, and for detecting/typing
     into the currently focused field.
   - **Screen Recording** — required for the screenshot (System Settings → Privacy &
     Security → Screen Recording → enable Hammerspoon).
6. Press **fn+A** on any screen with a question visible.

Optional: add Hammerspoon to Login Items (System Settings → General → Login Items)
so this survives reboots.

## Known limitations

- Screenshots the *entire* main display, not just the focused window.
- The popup window always appears on your primary display, even with multiple
  monitors (auto-typed answers aren't affected by this — they go wherever the
  field actually is).
- No timeout — a slow response just leaves you waiting. The only progress
  indicator is a small green dot in the bottom-left corner for the first 3
  seconds; if it takes longer than that, there's no further feedback until the
  answer (or an error alert) shows up. A blue dot flashes briefly when an
  answer is auto-typed.
- Auto-fill relies on the focused field visually showing a normal browser focus
  indicator (highlighted border, blinking cursor) in the screenshot, and on the
  app exposing proper Accessibility roles — most native apps and standard web
  forms do, some custom-rendered widgets (canvas-based editors, some heavily
  customized web components) may not, and fall back to the popup.
- A multi-line answer (e.g. code) typed into a single-line field could hit
  Enter mid-type and trigger an unintended action in that field — unlikely
  since code questions are almost always multi-line text areas, not zero.
- Session-resume caching is time-sensitive: rapid presses within the same sitting
  are cheap (prompt caching), but long gaps between uses mean an occasional
  full-price context resend even without an explicit re-read.

## License

MIT
