@AGENTS.md

## Claude Code specifics

- The hooks in `.claude/settings.json` block edits to guardrail files and commands that bypass
  checks, and ask for confirmation when an edit adds suppressions. If a hook blocks something, do
  not look for another way to do the same thing: explain it to the person.
- The Stop hook runs the policies and SwiftLint when you finish. If it reports failures, fix them
  before stopping.
- This project is usually edited on Linux and built on a macOS VM (`ssh tahoe`). Without building
  there, do not claim the code compiles.
