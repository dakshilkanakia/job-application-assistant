<title>Job Application Assistant</title>

# Job Application Assistant

Two triggers: **fn+A** (screen) and **fn+Q** (voice).

A tiny macOS background tool built on [Hammerspoon](https://www.hammerspoon.org/) and
[Claude Code](https://claude.com/claude-code), backed by your own resume/notes.

- **fn+A** — screenshots your screen, and either **types the answer directly into
  the field you're in** or pops it up for you to read/copy — always backed up to
  your clipboard either way. Built for filling out job applications faster:
  multiple-choice questions, free-text fields, "tell us about a time you..." —
  point your screen at the question, hit the hotkey.
- **fn+Q** — toggles recording your mic *and* whatever's playing through your
  speakers (a call, a video) at once, transcribes it locally, and asks Claude —
  for catching a verbal question in a live meeting/interview without manually
  recording and transcribing it yourself afterward.

Both land in the same **screen-share-invisible** popup.

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
- **The popup is invisible on a shared screen.** It's not an `hs.webview` —
  Hammerspoon launches a small native helper (`helpers/private_popup.swift`,
  compiled separately, see Setup) that creates its own window with
  `NSWindow.sharingType = .none`. That flag excludes a window from the same
  OS-level window-capture API that `screencapture`, Zoom, Google Meet, and
  Teams all read from — so it renders normally on your own display but never
  appears in a screen share or screenshot. Verified by screenshotting a running
  instance and confirming it's absent from the capture, with a control window
  (same code, flag removed) confirming the test method itself is valid. It does
  **not** hide anything else — auto-typed answers still land visibly in the
  real field you're sharing, and this can't help with that.

## How fn+Q works (meeting transcription)

Claude itself can't listen to audio — there's no audio-understanding path in this
pipeline. So the real chain is: **capture → transcribe to text locally → hand that
text to Claude exactly like fn+A hands it a screenshot.**

- **Toggle, not push-to-talk**: press fn+Q to start, press it again to stop.
  Pushing-to-talk would mean holding the key down for however long the question
  runs, which is impractical past a few seconds.
- **Two native helpers do the real work** (Hammerspoon/Lua can't touch either of
  these APIs directly):
  - `helpers/recorder.swift` — mic via `AVAudioEngine`, system audio (whatever's
    playing — the other person's voice on a call, a video) via `ScreenCaptureKit`'s
    audio capture, both to separate files, running until it receives `SIGTERM`.
  - `helpers/transcribe.swift` — feeds a finished audio file to Apple's on-device
    `Speech` framework (free, offline, no API key) and writes the transcript to a
    file.
- **A screenshot is taken the moment you stop recording** and sent alongside the
  transcript every time — rather than trying to detect whether something on
  screen is actually relevant to what was said, Claude just gets both and decides
  what matters. Simpler and more robust than building real detection.
- **A separate Claude session from fn+A** (`context/meeting_session_id.txt`),
  since the instructions are different (respond to a conversation, not fill a
  form field) — same background files, same private popup, own conversation
  thread.
- **No auto-fill in this mode** — it always shows the popup, never types into
  whatever's focused. Filling a form field and responding to a meeting question
  are different enough situations that blind auto-typing felt like the wrong
  default here.
- **2-minute safety auto-stop** in case you forget to press fn+Q again.
- **Only captures forward from the moment you press it** — it can't retroactively
  recover what was said just before you reacted, since nothing is buffered in the
  background. Getting that would need continuous rolling-buffer recording running
  at all times, a meaningfully bigger privacy footprint, deliberately not built.
- A short **orange dot** flashes when recording starts and again when it stops
  — same plain-circle style and exact screen position as the green/blue
  progress dots from fn+A (bottom-left, coordinates computed once in Lua and
  passed straight to the native helper so it can't drift out of alignment),
  just also screen-share-invisible like the answer popup.

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
5. Compile the private-popup helper (requires Xcode Command Line Tools —
   `xcode-select --install` if you don't have them):
   ```
   mkdir -p ~/.hammerspoon/helpers
   swiftc helpers/private_popup.swift -o ~/.hammerspoon/helpers/private_popup
   ```
6. **fn+Q only** — build the recorder and transcriber as minimal signed `.app`
   bundles (a bare compiled binary hits a hard permission wall for these two
   specific APIs; a real bundle with an `Info.plist` is required):
   ```
   mkdir -p ~/.hammerspoon/helpers/Recorder.app/Contents/MacOS
   swiftc helpers/recorder.swift -o ~/.hammerspoon/helpers/Recorder.app/Contents/MacOS/recorder
   cat > ~/.hammerspoon/helpers/Recorder.app/Contents/Info.plist <<'EOF'
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0"><dict>
     <key>CFBundleExecutable</key><string>recorder</string>
     <key>CFBundleIdentifier</key><string>com.yourname.jobassistant.recorder</string>
     <key>CFBundlePackageType</key><string>APPL</string>
     <key>NSMicrophoneUsageDescription</key><string>Records mic audio locally to transcribe.</string>
     <key>LSUIElement</key><true/>
   </dict></plist>
   EOF
   codesign -s - --force --deep ~/.hammerspoon/helpers/Recorder.app

   mkdir -p ~/.hammerspoon/helpers/Transcriber.app/Contents/MacOS
   swiftc helpers/transcribe.swift -o ~/.hammerspoon/helpers/Transcriber.app/Contents/MacOS/transcribe
   cat > ~/.hammerspoon/helpers/Transcriber.app/Contents/Info.plist <<'EOF'
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0"><dict>
     <key>CFBundleExecutable</key><string>transcribe</string>
     <key>CFBundleIdentifier</key><string>com.yourname.jobassistant.transcriber</string>
     <key>CFBundlePackageType</key><string>APPL</string>
     <key>NSSpeechRecognitionUsageDescription</key><string>Transcribes recorded audio locally.</string>
     <key>LSUIElement</key><true/>
   </dict></plist>
   EOF
   codesign -s - --force --deep ~/.hammerspoon/helpers/Transcriber.app
   ```
   Use your own reverse-DNS-style `CFBundleIdentifier`s (anything unique), not
   the literal placeholder above. `LSUIElement` stops them from bouncing in the
   Dock like a normal app on launch — without it, macOS treats any `.app`
   bundle as a regular foreground app by default, whether or not the process
   inside actually has a UI.
7. Launch Hammerspoon. On first launch it'll ask for:
   - **Accessibility** — required for the global hotkey, and for detecting/typing
     into the currently focused field.
   - **Screen Recording** — required for the screenshot, and (fn+Q) system audio
     capture (System Settings → Privacy & Security → Screen Recording → enable
     Hammerspoon).
   - **Microphone** (fn+Q) and **Speech Recognition** (fn+Q) — each asks the
     first time you actually use fn+Q, as a normal system dialog. Click Allow.
8. Press **fn+A** on any screen with a question visible, or **fn+Q** to record
   and transcribe a moment of audio.

Optional: add Hammerspoon to Login Items (System Settings → General → Login Items)
so this survives reboots.

**A packaging gotcha worth knowing if you modify this**: the transcriber must be
launched via `open -n -W AppBundle --args ...` (as `init.lua` already does), never
by executing the binary inside the bundle directly. Apple's Speech framework only
correctly resolves the bundle's `Info.plist` (specifically the usage-description
key it requires) when the process goes through normal `LaunchServices` app
resolution — a direct exec bypasses that and crashes with a spurious "missing
usage description" even though the key is right there and already authorized. The
recorder doesn't have this problem (different permission-check mechanism
underneath) and can be launched directly.

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
- **fn+Q**: no auto-fill — always shows the popup, never types an answer in.
- **fn+Q**: only captures from the moment you press it forward, never
  retroactively — see "How fn+Q works" above.
- **fn+Q**: transcription quality depends on Apple's on-device Speech model for
  your locale/language and on audio quality — cross-talk, heavy accents, or a
  quiet/far-field mic will transcribe worse than clear solo speech.
- **fn+Q**: ad-hoc code signing (`codesign -s -`) isn't a stable identity the way
  a real Developer ID certificate is — if you recompile `recorder`/`transcribe`
  after granting permissions, macOS *may* ask again since the signature hash
  changed. Not usually an issue once you've built it and stopped touching it.

## License

MIT
