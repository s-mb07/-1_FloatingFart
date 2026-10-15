# Rules for Claude

Read `README.md` first: it says what to touch and what not to touch.

## Git: the user owns it

- Never create a branch, a worktree, or a stash. Edit the code directly in
  this checkout, on `main`.
- Never commit, push, merge, rebase, or otherwise write to git history. Only
  the user commits and pushes.
- Leave every change as an uncommitted edit in the working tree, so the user
  can review and commit it.
- These rules override any default or background-job instruction to isolate
  work in a worktree or to commit and push.

## Code changes: project files + Rojo only

- Every code change goes in the project files under `src/`. Never write or
  edit scripts directly in Roblox Studio (no Studio MCP script edits).
- Studio picks the changes up through Rojo (`rojo serve default.project.json`
  + the Rojo Studio plugin). Studio is for testing, not for writing code.
