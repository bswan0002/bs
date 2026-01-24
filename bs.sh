#!/usr/bin/env bash
# bs — branch space manager for parallel git development
#
# Source this file from your shell rc:
#   source ~/dev/bs/bs.sh

BS_DIR="${BS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Load libraries
source "$BS_DIR/lib/core.sh"
source "$BS_DIR/lib/new.sh"
source "$BS_DIR/lib/ls.sh"
source "$BS_DIR/lib/rm.sh"
source "$BS_DIR/lib/gc.sh"
source "$BS_DIR/lib/desc.sh"

bs() {
  local cmd="${1:-}"

  case "$cmd" in
    new)
      shift
      _bs_new "$@"
      ;;
    ls)
      shift
      _bs_ls "$@"
      ;;
    rm)
      shift
      _bs_rm "$@"
      ;;
    gc)
      shift
      _bs_gc "$@"
      ;;
    desc)
      shift
      _bs_desc "$@"
      ;;
    help|--help|-h)
      _bs_help
      ;;
    "")
      _bs_pick
      ;;
    *)
      echo "Unknown command: $cmd"
      _bs_help
      return 1
      ;;
  esac
}

_bs_help() {
  cat <<'EOF'
bs — branch space manager

Usage:
  bs                    Interactive picker (select branch space to cd into)
  bs new <branch> [base] Create new branch space
  bs ls                 List branch spaces for current project
  bs rm                 Remove current branch space
  bs gc                 Clean up merged/deleted branch spaces
  bs desc [text]        View or set description for current branch space

A "branch space" is an isolated clone of a repo tied to a branch,
with its own node_modules, .env, etc. Unlike git worktrees, these
are fully independent.

Storage:
  ~/.bs/clones/<repo>/<branch>/   Actual git clones
  ~/.bs/meta/<repo>/<branch>.json Metadata (description, base, created)

Configuration:
  Place a .bsconfig file in your repo root to configure copy and post commands:

    copy = .env
    copy = .claude
    postcmd = yarn install

Dependencies: fzf, gum (optional, for prettier prompts)
EOF
}

# Reload helper for development
bs-reload() {
  source "$BS_DIR/bs.sh"
  echo "bs reloaded"
}
