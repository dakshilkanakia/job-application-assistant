-- fn+A assistant: screenshot -> claude -p (headless, Read-only, resumed session)
-- -> auto-fill, or a screen-share-invisible popup + clipboard.
--
-- Setup: see README.md. Put your own resume/references/notes in ./context and
-- fix CLAUDE_BIN below (GUI apps often don't inherit your shell's PATH).

require("hs.ipc")
hs.ipc.cliInstall() -- lets you test/debug via `hs -c "..."` from Terminal

local ax = require("hs.axuielement")
local json = require("hs.json")

-- Run `which claude` in Terminal and paste the absolute path here.
local CLAUDE_BIN = "/usr/local/bin/claude"
local SCREENCAPTURE_BIN = "/usr/sbin/screencapture"
local SHOT_PATH = "/tmp/cc_assistant_screen.png"

-- Native helper window (not hs.webview) because it sets NSWindow.sharingType
-- = .none, which excludes it from the OS-level window-capture API that
-- Zoom/Meet/Teams/screencapture all consume — so it's invisible on a shared
-- screen but still visible to you locally. Verified 2026-09-24 by screenshotting
-- a running instance and confirming it does not appear in the capture.
local POPUP_HELPER_BIN = hs.configdir .. "/helpers/private_popup"
local POPUP_PAYLOAD_PATH = "/tmp/cc_assistant_popup_payload.json"

local CONTEXT_DIR = hs.configdir .. "/context"
local SESSION_ID_PATH = CONTEXT_DIR .. "/session_id.txt"

local CAVEAT_MARKER = "---CAVEAT---"
local MULTI_MARKER = "---MULTI---"
local FOCUS_MARKER = "---FOCUS---"

-- Every "block" below means: a short label line, then a newline, then the
-- answer itself (which can span multiple lines, e.g. code), with a full blank
-- line between one block and the next.
local ANSWER_INSTRUCTIONS =
  "The screen may show a long form with MANY fields — most already filled in, or not yet " ..
  "relevant — or just one question/prompt (e.g. a coding prompt) with nothing else. " ..
  "Answer EVERY visible question/field that isn't already filled in with unrelated content, not " ..
  "just one. Each answer should use MY real background where relevant (specific projects, " ..
  "numbers, technologies) instead of a generic answer. If it's multiple choice, state the choice " ..
  "first then a one-line reason. If it's a text field, write the actual answer text, no " ..
  "preamble, no 'Here is...'. Keep each answer as short as its question allows. " ..
  "Format your response based on how many questions there are:\n" ..
  "- Exactly ONE question/field visible total: output just its raw answer, no label, no marker.\n" ..
  "- SEVERAL questions/fields: look for the ONE that currently has visible cursor focus (a " ..
  "highlighted border/outline, or a blinking text cursor — the normal browser focus indicator).\n" ..
  "  - If you can identify it: start your response with the exact line '" .. FOCUS_MARKER ..
  "' on its own, then put THAT question's answer first as a block (short label line, newline, " ..
  "the answer), then a blank line, then every other visible question as further blocks in the " ..
  "same format, each separated by a blank line.\n" ..
  "  - If you can't tell which one is focused (no visible indicator, or it's a review/summary " ..
  "screen with nothing actively focused): start your response with the exact line '" ..
  MULTI_MARKER .. "' instead, then every visible question as label+answer blocks separated by " ..
  "blank lines, in whatever order they appear on screen.\n" ..
  "If you have to guess a fact that isn't in my background material (an exact zip code, a date, " ..
  "whatever) and think I should double-check it: still give the raw paste-ready guess in its " ..
  "answer, then at the very END of your ENTIRE response (after everything else) add a new line " ..
  "with the exact text '" .. CAVEAT_MARKER .. "', then a short note listing which answer(s) were " ..
  "guesses and why. Omit this entirely if no caveat is needed anywhere."

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
local busyDot = nil
local triggerFocusedElement = nil -- snapshotted the instant fn+A is pressed

local SAFE_TEXT_ROLES = {AXTextField = true, AXTextArea = true, AXComboBox = true}

local function captureFocusedElement()
  local ok, el = pcall(function()
    return ax.systemWideElement():attributeValue("AXFocusedUIElement")
  end)
  if ok then triggerFocusedElement = el else triggerFocusedElement = nil end
end

-- True only if the field we captured at trigger time is still focused right
-- now, and it's a normal (non-password) text field. This is the guard against
-- typing an answer into the wrong place if focus moved while Claude thought.
local function canAutoFill()
  if not triggerFocusedElement then return false end
  local ok, nowFocused = pcall(function()
    return ax.systemWideElement():attributeValue("AXFocusedUIElement")
  end)
  if not ok or not nowFocused or nowFocused ~= triggerFocusedElement then return false end

  local role = triggerFocusedElement:attributeValue("AXRole")
  local subrole = triggerFocusedElement:attributeValue("AXSubrole")
  if subrole == "AXSecureTextField" then return false end
  return SAFE_TEXT_ROLES[role] == true
end

local function showFillConfirmation()
  local screen = hs.screen.mainScreen():frame()
  local size = 10
  local rect = hs.geometry.rect(screen.x + 12, screen.y + screen.h - size - 12, size, size)
  local dot = hs.canvas.new(rect)
  dot[1] = {
    type = "circle",
    action = "fill",
    fillColor = {red = 0.2, green = 0.5, blue = 1, alpha = 0.95}, -- blue = auto-filled
  }
  dot:level(hs.canvas.windowLevels.floating)
  dot:clickActivating(false)
  dot:show()
  hs.timer.doAfter(1.2, function() dot:delete() end)
end

local function hideBusyDot()
  if busyDot then
    busyDot:delete()
    busyDot = nil
  end
end

local function showBusyDot()
  hideBusyDot()
  local screen = hs.screen.mainScreen():frame()
  local size = 10
  local rect = hs.geometry.rect(screen.x + 12, screen.y + screen.h - size - 12, size, size)
  local dot = hs.canvas.new(rect)
  dot[1] = {
    type = "circle",
    action = "fill",
    fillColor = {red = 0.2, green = 0.85, blue = 0.3, alpha = 0.95},
  }
  dot:level(hs.canvas.windowLevels.floating)
  dot:clickActivating(false)
  dot:show()
  busyDot = dot
  -- fixed 3s flash, independent of how long the actual task takes; guard against
  -- a newer dot (from a second press) getting deleted early by this stale timer
  hs.timer.doAfter(3, function()
    if busyDot == dot then hideBusyDot() end
  end)
end

local function closeAnswerWindow()
  if answerWindow then
    answerWindow:terminate()
    answerWindow = nil
  end
end

-- Launches the native private-popup helper (see POPUP_HELPER_BIN) instead of
-- an hs.webview, so the answer window is invisible on a shared screen.
local function showAnswer(displayText, caveatNote, footerNote)
  closeAnswerWindow()

  local payload = json.encode({
    answer = displayText,
    caveat = caveatNote,
    footer = footerNote or "Copied to clipboard. Press Esc or F6 to dismiss.",
  })
  local f = io.open(POPUP_PAYLOAD_PATH, "w")
  f:write(payload)
  f:close()

  answerWindow = hs.task.new(POPUP_HELPER_BIN, function() end, {POPUP_PAYLOAD_PATH})
  answerWindow:start()
end

local function claudeCall(args, callback)
  local task = hs.task.new(CLAUDE_BIN, callback, args)
  task:setWorkingDirectory(CONTEXT_DIR)
  task:start()
end

-- Pulls the caveat note (if any) off the very end of the response. A caveat
-- always disables auto-fill for that response — a guessed fact should be
-- eyeballed before it's typed anywhere, never typed in blind.
local function extractCaveat(text)
  local pat = "^(.-)\n?" .. CAVEAT_MARKER:gsub("%-", "%%-") .. "\n?(.*)$"
  local main, note = text:match(pat)
  if main then
    return (main:gsub("%s+$", "")), (note:gsub("^%s+", ""):gsub("%s+$", ""))
  end
  return (text:gsub("%s+$", "")), nil
end

-- Splits blank-line-separated "label\nanswer" blocks.
local function splitBlocks(text)
  local blocks = {}
  for block in (text .. "\n\n"):gmatch("(.-)\n\n+") do
    local trimmed = block:gsub("^%s+", ""):gsub("%s+$", "")
    if #trimmed > 0 then table.insert(blocks, trimmed) end
  end
  if #blocks == 0 and #text:gsub("%s", "") > 0 then table.insert(blocks, text) end
  return blocks
end

-- A block is "label line\nanswer text" — answer text may itself be multi-line.
local function blockAnswerOnly(block)
  local _, answerBody = block:match("^(.-)\n(.*)$")
  if not answerBody or #answerBody:gsub("%s", "") == 0 then return block end
  return answerBody
end

local function stripPrefix(text, marker)
  return (text:gsub("^%s*" .. marker:gsub("%-", "%%-") .. "%s*\n?", ""))
end

local function handleFinalResult(exitCode, stdOut, stdErr)
  hideBusyDot()
  if exitCode ~= 0 or not stdOut or stdOut:match("^%s*$") then
    hs.alert.show("Claude error: " .. (stdErr ~= "" and stdErr or ("exit " .. exitCode)))
    return
  end

  local mainText, caveatNote = extractCaveat(stdOut)
  local hasCaveat = caveatNote ~= nil

  local isFocus = mainText:match("^%s*" .. FOCUS_MARKER:gsub("%-", "%%-")) ~= nil
  local isMulti = (not isFocus) and mainText:match("^%s*" .. MULTI_MARKER:gsub("%-", "%%-")) ~= nil

  if isFocus then
    -- Multiple fields visible, but one is focused: type just that one, and
    -- still show the popup with everything else for manual copy/paste.
    local body = stripPrefix(mainText, FOCUS_MARKER)
    local blocks = splitBlocks(body)
    local typedText = blockAnswerOnly(blocks[1] or body):gsub("%s+$", "")
    hs.pasteboard.setContents(typedText)
    if not hasCaveat and canAutoFill() then
      hs.eventtap.keyStrokes(typedText)
      showFillConfirmation()
    end
    showAnswer(body, caveatNote, "First answer typed + copied to clipboard, rest listed below. Esc/F6 to dismiss.")
    return
  end

  if isMulti then
    -- Several fields, couldn't tell which is focused: manual-only, no typing.
    local body = stripPrefix(mainText, MULTI_MARKER)
    hs.pasteboard.setContents(body)
    showAnswer(body, caveatNote)
    return
  end

  -- True single-question screen (e.g. a coding prompt with nothing else).
  hs.pasteboard.setContents(mainText)
  if not hasCaveat and canAutoFill() then
    hs.eventtap.keyStrokes(mainText)
    showFillConfirmation()
    return
  end
  showAnswer(mainText, caveatNote)
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
  captureFocusedElement()
  showBusyDot()
  hs.task.new(SCREENCAPTURE_BIN, function(exitCode, _, stdErr)
    if exitCode ~= 0 then
      hideBusyDot()
      hs.alert.show("Screenshot failed: " .. stdErr)
      return
    end
    runClaudeOnScreenshot()
  end, {"-x", SHOT_PATH}):start()
end

-- fn+A trigger. hs.hotkey.bind's modifier list doesn't reliably support "fn"
-- across Hammerspoon versions (it's not a real Carbon hotkey modifier), so we
-- watch raw keyDown events instead and check the fn flag ourselves.
local TRIGGER_KEYCODE = hs.keycodes.map["a"]
local ESCAPE_KEYCODE = hs.keycodes.map["escape"]

fnF5Watcher = hs.eventtap.new({hs.eventtap.event.types.keyDown}, function(event)
  local keyCode = event:getKeyCode()

  if keyCode == TRIGGER_KEYCODE and event:getFlags().fn then
    captureAndAsk()
    return true -- swallow the event, don't pass it through
  end

  -- Only swallow Escape while the popup is actually open, so it behaves
  -- normally (cancel dialogs, exit fields, etc.) everywhere else.
  if keyCode == ESCAPE_KEYCODE and answerWindow ~= nil then
    closeAnswerWindow()
    return true
  end

  return false
end)
fnF5Watcher:start()

hs.hotkey.bind({}, "F6", closeAnswerWindow)

hs.alert.show("fn+A assistant loaded")
