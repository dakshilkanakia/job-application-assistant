-- fn+F5 assistant: screenshot -> claude -p (headless, Read-only, resumed session)
-- -> floating answer + clipboard.
--
-- Setup: see README.md. Put your own resume/references/notes in ./context and
-- fix CLAUDE_BIN below (GUI apps often don't inherit your shell's PATH).

-- Run `which claude` in Terminal and paste the absolute path here.
local CLAUDE_BIN = "/usr/local/bin/claude"
local SCREENCAPTURE_BIN = "/usr/sbin/screencapture"
local SHOT_PATH = "/tmp/fn_f5_assistant_screen.png"

local CONTEXT_DIR = hs.configdir .. "/context"
local SESSION_ID_PATH = CONTEXT_DIR .. "/session_id.txt"

local ANSWER_INSTRUCTIONS =
  "Find the visible question/field (form question, multiple choice, coding prompt, whatever is " ..
  "on screen) and give a direct, ready-to-paste answer using MY real background where relevant " ..
  "(specific projects, numbers, technologies) instead of a generic answer. If it's multiple " ..
  "choice, state the choice first then a one-line reason. If it's a text field, write the actual " ..
  "answer text, no preamble, no 'Here is...'. Keep it as short as the question allows."

-- First-ever call: load background material once, this becomes part of the session.
-- Edit the file list below to match whatever you actually put in ./context.
local FIRST_PROMPT = "You are helping me quickly while I fill out job application forms, " ..
  "repeatedly, over a long session. First read my background material: " ..
  CONTEXT_DIR .. "/resume.pdf, " .. CONTEXT_DIR .. "/references.pdf, and " ..
  CONTEXT_DIR .. "/behavioural.txt (past behavioral answers with real project details). " ..
  "Remember this for later screenshots I send you in this same session — don't re-read these " ..
  "files unless I explicitly ask. Then read the screenshot at " .. SHOT_PATH .. ". " ..
  ANSWER_INSTRUCTIONS

-- Every later call: resume the same session, skip re-reading background files entirely.
local RESUME_PROMPT = "New screenshot at " .. SHOT_PATH .. " (same background info you already " ..
  "have from earlier in this session, don't re-read the resume/references/behavioural files). " ..
  ANSWER_INSTRUCTIONS

local function getOrCreateSessionId()
  local f = io.open(SESSION_ID_PATH, "r")
  if f then
    local id = f:read("*l")
    f:close()
    if id and #id > 0 then return id, false end
  end
  local handle = io.popen("uuidgen")
  local id = handle:read("*l")
  handle:close()
  local out = io.open(SESSION_ID_PATH, "w")
  out:write(id)
  out:close()
  return id, true
end

local answerWindow = nil

local function closeAnswerWindow()
  if answerWindow then
    answerWindow:delete()
    answerWindow = nil
  end
end

local function showAnswer(text)
  closeAnswerWindow()

  local screen = hs.screen.mainScreen():frame()
  local w, h = 460, 320
  local rect = hs.geometry.rect(screen.x + screen.w - w - 24, screen.y + 60, w, h)

  answerWindow = hs.webview.new(rect)
    :windowStyle({"titled", "closable", "resizable", "utility"})
    :windowTitle("Claude")
    :allowTextEntry(false)
    :level(hs.drawing.windowLevels.floating)

  local escaped = text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub("\n", "<br>")
  local html = [[
    <html><body style="font-family:-apple-system,sans-serif;font-size:14px;
      padding:14px;background:#1e1e1e;color:#f0f0f0;margin:0;">
      <div>]] .. escaped .. [[</div>
      <div style="margin-top:14px;font-size:11px;color:#888;">Copied to clipboard. Press F6 to dismiss.</div>
    </body></html>
  ]]
  answerWindow:html(html)
  answerWindow:show()
end

local function claudeCall(args, callback)
  local task = hs.task.new(CLAUDE_BIN, callback, args)
  task:setWorkingDirectory(CONTEXT_DIR)
  task:start()
end

local function handleFinalResult(exitCode, stdOut, stdErr)
  if exitCode ~= 0 or not stdOut or stdOut:match("^%s*$") then
    hs.alert.show("Claude error: " .. (stdErr ~= "" and stdErr or ("exit " .. exitCode)))
    return
  end
  hs.pasteboard.setContents(stdOut)
  showAnswer(stdOut)
end

local function runFreshWithContext(sessionId)
  claudeCall({"-p", FIRST_PROMPT, "--allowedTools", "Read", "--session-id", sessionId}, handleFinalResult)
end

local function runClaudeOnScreenshot()
  local sessionId, isNew = getOrCreateSessionId()
  if isNew then
    runFreshWithContext(sessionId)
    return
  end
  claudeCall({"-p", RESUME_PROMPT, "--allowedTools", "Read", "--resume", sessionId}, function(exitCode, stdOut, stdErr)
    if exitCode ~= 0 and stdErr and stdErr:match("No conversation found") then
      -- session expired/was deleted server-side; recreate it under the same id
      runFreshWithContext(sessionId)
      return
    end
    handleFinalResult(exitCode, stdOut, stdErr)
  end)
end

local function captureAndAsk()
  hs.alert.show("Reading screen...", 1)
  hs.task.new(SCREENCAPTURE_BIN, function(exitCode, _, stdErr)
    if exitCode ~= 0 then
      hs.alert.show("Screenshot failed: " .. stdErr)
      return
    end
    runClaudeOnScreenshot()
  end, {"-x", SHOT_PATH}):start()
end

-- fn+F5 trigger. hs.hotkey.bind's modifier list doesn't reliably support "fn"
-- across Hammerspoon versions (it's not a real Carbon hotkey modifier), so we
-- watch raw keyDown events instead and check the fn flag ourselves.
local F5_KEYCODE = hs.keycodes.map["f5"]

fnF5Watcher = hs.eventtap.new({hs.eventtap.event.types.keyDown}, function(event)
  if event:getKeyCode() == F5_KEYCODE and event:getFlags().fn then
    captureAndAsk()
    return true -- swallow the event, don't pass it through
  end
  return false
end)
fnF5Watcher:start()

hs.hotkey.bind({}, "F6", closeAnswerWindow)

hs.alert.show("fn+F5 assistant loaded")
