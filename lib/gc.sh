# gc.sh — bs gc command (garbage collection)

_bs_gc() {
  _bs_detect_context

  local repo="$BS_REPO"

  if [[ -z "$repo" ]]; then
    echo "Error: not in a bs-managed project context"
    echo "Run 'bs gc' from within a project or its branch spaces"
    return 1
  fi

  # Need source repo to check origin
  local source="$BS_SOURCE"
  if [[ -z "$source" || ! -d "$source" ]]; then
    echo "Error: cannot find source repo for project '$repo'"
    return 1
  fi

  echo "Checking branch spaces for $repo..."
  echo ""

  # Fetch latest from origin
  git -C "$source" fetch --quiet origin

  local candidates=()
  local candidate_reasons=()

  for sanitized_branch in $(_bs_list_branches "$repo"); do
    local branch
    branch="$(_bs_unsanitize_branch "$sanitized_branch")"
    local clone_path
    clone_path="$(_bs_clone_path "$repo" "$branch")"

    local reason=""

    # Check if branch exists on origin
    if ! git -C "$source" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
      reason="deleted on origin"
    else
      # Check if branch is merged (into any branch)
      # A branch is "merged" if its HEAD commit is reachable from another branch
      local branch_head
      branch_head="$(git -C "$source" rev-parse "origin/$branch" 2>/dev/null)"

      if [[ -n "$branch_head" ]]; then
        # Check if this commit exists in any other branch
        local merged_into
        merged_into="$(git -C "$source" branch -r --contains "$branch_head" 2>/dev/null | grep -v "origin/$branch" | head -1 | xargs)"
        if [[ -n "$merged_into" ]]; then
          reason="merged into ${merged_into#origin/}"
        fi
      fi
    fi

    if [[ -n "$reason" ]]; then
      candidates+=("$branch")
      candidate_reasons+=("$reason")
    fi
  done

  if [[ ${#candidates[@]} -eq 0 ]]; then
    echo "No branch spaces to clean up."
    return 0
  fi

  echo "Found ${#candidates[@]} candidate(s) for removal:"
  echo ""

  for i in "${!candidates[@]}"; do
    local branch="${candidates[$i]}"
    local reason="${candidate_reasons[$i]}"
    local clone_path
    clone_path="$(_bs_clone_path "$repo" "$branch")"

    local meta
    meta="$(_bs_get_branch_meta "$repo" "$branch")"
    local desc=""
    if [[ -n "$meta" ]]; then
      desc="$(echo "$meta" | grep -o '"desc"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)"
    fi

    printf "  %-30s %-20s %s\n" "$branch" "($reason)" "$desc"
  done

  echo ""

  # Confirm
  if command -v gum >/dev/null 2>&1; then
    if ! gum confirm "Remove these branch spaces?"; then
      echo "Aborted"
      return 0
    fi
  else
    read -r -p "Remove these branch spaces? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      echo "Aborted"
      return 0
    fi
  fi

  # Check if we're currently in one of the candidates
  local current_clone=""
  if [[ "$BS_CONTEXT" == "clone" ]]; then
    current_clone="$BS_BRANCH"
  fi

  local need_cd=false
  for branch in "${candidates[@]}"; do
    local sanitized
    sanitized="$(_bs_sanitize_branch "$branch")"
    if [[ "$sanitized" == "$current_clone" ]]; then
      need_cd=true
      break
    fi
  done

  if [[ "$need_cd" == true ]]; then
    cd "$source" || cd "$HOME"
  fi

  # Remove candidates
  for branch in "${candidates[@]}"; do
    local clone_path
    clone_path="$(_bs_clone_path "$repo" "$branch")"

    rm -rf "$clone_path"
    _bs_delete_branch_meta "$repo" "$branch"
    echo "Removed: $branch"
  done

  echo ""
  echo "Cleaned up ${#candidates[@]} branch space(s)"

  if [[ "$need_cd" == true ]]; then
    echo "Now in: $(pwd)"
  fi
}
