# rm.sh — bs rm command

_bs_rm() {
  _bs_detect_context

  if [[ "$BS_CONTEXT" != "clone" ]]; then
    echo "Error: must be inside a branch space to remove it"
    echo "Current context: $BS_CONTEXT"
    return 1
  fi

  local repo="$BS_REPO"
  local branch="$BS_BRANCH"
  local clone_path; clone_path="$(_bs_clone_path "$repo" "$(_bs_unsanitize_branch "$branch")")"

  echo "Branch space: $branch"
  echo "Path: $clone_path"
  echo ""

  # Safety checks
  local has_warnings=false

  # Uncommitted changes
  if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    has_warnings=true
    echo "Warning: uncommitted changes:"
    git status --short
    echo ""
  fi

  # Unpushed commits
  local unpushed; unpushed="$(git log --oneline @{upstream}..HEAD 2>/dev/null)"
  if [[ -n "$unpushed" ]]; then
    has_warnings=true
    echo "Warning: unpushed commits:"
    echo "$unpushed"
    echo ""
  fi

  # Stashes
  local stashes; stashes="$(git stash list 2>/dev/null)"
  if [[ -n "$stashes" ]]; then
    has_warnings=true
    echo "Warning: stashes:"
    echo "$stashes"
    echo ""
  fi

  # Confirm deletion
  local confirm_msg="Remove branch space '$branch'?"
  [[ "$has_warnings" == true ]] && confirm_msg="Remove branch space '$branch' despite warnings?"

  if ! gum confirm "$confirm_msg"; then
    echo "Aborted"
    return 1
  fi

  # Get source to cd to after deletion
  local target_dir="$BS_SOURCE"
  if [[ -z "$target_dir" || ! -d "$target_dir" ]]; then
    target_dir="$HOME"
  fi

  # Remove clone and metadata
  cd "$target_dir" || cd "$HOME"

  gum spin --spinner dot --title "Removing branch space..." -- rm -rf "$clone_path"
  _bs_delete_branch_meta "$repo" "$(_bs_unsanitize_branch "$branch")"

  echo "Removed branch space '$branch'"
  echo "Now in: $(pwd)"
}
