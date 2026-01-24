# bs — branch space manager

A CLI tool for managing isolated git clones ("branch spaces") for parallel development.

## Why?

When working on multiple features simultaneously—especially with AI agents that each need their own working directory—git worktrees aren't enough. You want truly isolated environments with their own `node_modules`, `.env` files, build artifacts, etc.

`bs` manages these isolated clones:
- Stores them in a hidden location (`~/.bs/`) to keep your dev directory clean
- Tracks metadata like descriptions (useful for Jira ticket branches like `CLDYFE-1234`)
- Provides quick navigation between branch spaces
- Handles cleanup when branches are merged or deleted

## Installation

```bash
# Clone the repo
git clone <repo-url> ~/dev/bs

# Add to your shell rc (.zshrc or .bashrc)
source ~/dev/bs/bs.sh
```

Dependencies:
- `fzf` — required for interactive selection
- `gum` — optional, provides prettier confirmation prompts

## Usage

### Interactive picker

```bash
bs              # Pick a branch space to cd into
```

When run from within a project, shows branch spaces for that project. Otherwise, shows all projects first.

Typing a non-existent branch name and pressing enter will offer to create it.

### Create a branch space

```bash
bs new CLDYFE-1234              # Create from current branch (fzf picker for base)
bs new CLDYFE-1234 main         # Create from specific base branch
```

If the branch exists on origin, it's checked out directly. Otherwise, a new branch is created from the base.

### List branch spaces

```bash
bs ls           # Show all branch spaces for current project
```

### Remove current branch space

```bash
bs rm           # Prompts for confirmation, warns about uncommitted changes
```

### Clean up merged branches

```bash
bs gc           # Find and remove branch spaces where the branch was merged/deleted
```

### Manage descriptions

```bash
bs desc                     # Show current description
bs desc "login refactor"    # Set description
```

## Configuration

Create a `.bsconfig` file in your repo root to configure automatic setup for new branch spaces:

```
# Copy files/directories from main repo
copy = .env
copy = .claude

# Run command after clone
postcmd = yarn install
```

## Storage structure

```
~/.bs/
  clones/
    <repo-name>/
      <branch-name>/        # Actual git clone
  meta/
    <repo-name>/
      _project.json         # { "source": "/path/to/main/repo", "registered": "..." }
      <branch-name>.json    # { "desc": "...", "base": "main", "created": "..." }
```

Branch names with `/` are sanitized to `--` in paths (e.g., `feature/foo` → `feature--foo`).

## Limitations

- **Reference clones**: Branch spaces use `git clone --reference` for speed, which means they depend on the source repo's object store. Don't delete or move your main repo after creating branch spaces.
- **Single source location**: Each project should have one "main" repo location. That's the point—use `bs new` from there for all your branch work.

## Development

```bash
bs-reload       # Re-source bs.sh after making changes
```
