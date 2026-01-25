# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

BS (Branch Space Manager) is a shell-based CLI tool for managing isolated git clones ("branch spaces") for parallel development. Unlike git worktrees, branch spaces are fully independent with their own `node_modules`, `.env`, build artifacts, etc.

**Language**: Bash/Shell
**Dependency**: gum (https://github.com/charmbracelet/gum)

## Development Commands

```bash
bs-reload              # Re-source bs.sh after making changes
zsh -n lib/<file>.sh   # Syntax check a shell file
```

## Architecture

### File Structure
- `bs.sh` — Entry point, command dispatcher, sources all lib modules
- `lib/core.sh` — Shared utilities: context detection, path helpers, metadata I/O
- `lib/new.sh` — `bs new` command
- `lib/ls.sh` — `bs ls` and picker (`bs` with no args)
- `lib/rm.sh` — `bs rm` command
- `lib/gc.sh` — `bs gc` garbage collection
- `lib/desc.sh` — `bs desc` description management

### Storage Layout
```
~/.bs/
  clones/<repo>/<repo>-<branch>/   # Actual git clones
  meta/<repo>/
    _project.json                   # { "source": "/path/to/main/repo", "registered": "..." }
    <branch>.json                   # { "desc": "...", "base": "main", "created": "..." }
```

### Key Patterns

**Context Detection** (`_bs_detect_context`): Determines execution context by checking cwd against `~/.bs/clones/`. Sets `BS_CONTEXT` to `main`, `clone`, `unmanaged`, or `none`.

**Branch Name Sanitization**: Forward slashes in branch names become `--` in filesystem paths (`feature/foo` → `feature--foo`). Use `_bs_sanitize_branch` / `_bs_unsanitize_branch`.

**Reference Clones**: Uses `git clone --reference` to share object store with source repo for speed. This means source repo cannot be deleted/moved after creating branch spaces.

**Metadata Parsing**: JSON metadata is parsed with grep/cut (e.g., `grep -o '"source"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4`).

### Adding New Commands

1. Create `lib/<cmd>.sh` with `_bs_<cmd>()` function
2. Add `source "$BS_DIR/lib/<cmd>.sh"` in `bs.sh`
3. Add case statement entry in `bs()` function

## Configuration

`.bsconfig` in repo root configures new branch space setup:
```
copy = .env              # Copy files/dirs from main repo
copy = .claude
postcmd = yarn install   # Run after clone
```
