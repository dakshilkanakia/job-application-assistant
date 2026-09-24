# Your background files go here

Drop your own files in this folder, e.g.:

- `resume.pdf`
- `references.pdf`
- `behavioural.txt` (past behavioral-interview answers, notes, whatever gives Claude
  real specifics to draw on instead of generic answers)

PDF, plain text, and images all work — Claude Code's `Read` tool handles them natively.
If you use different filenames, update the file list in `FIRST_PROMPT` inside `init.lua`.

None of these files are committed to git (see `.gitignore`) — this folder is meant
to hold your personal, private material locally only.

`session_id.txt` is auto-generated on first run — don't create it manually.
