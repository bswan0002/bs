# desc.sh — bs desc command

_bs_desc() {
  _bs_detect_context

  if [[ "$BS_CONTEXT" != "clone" ]]; then
    echo "Error: must be inside a branch space"
    echo "Current context: $BS_CONTEXT"
    return 1
  fi

  local repo="$BS_REPO"
  local branch
  branch="$(_bs_unsanitize_branch "$BS_BRANCH")"

  local meta
  meta="$(_bs_get_branch_meta "$repo" "$branch")"

  if [[ -z "$1" ]]; then
    # Show current description
    if [[ -z "$meta" ]]; then
      echo "(no description)"
      return 0
    fi

    local desc
    desc="$(echo "$meta" | grep -o '"desc"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)"

    if [[ -z "$desc" ]]; then
      echo "(no description)"
    else
      echo "$desc"
    fi
  else
    # Set description
    local new_desc="$*"

    # Get existing base from meta
    local base=""
    if [[ -n "$meta" ]]; then
      base="$(echo "$meta" | grep -o '"base"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)"
    fi
    [[ -z "$base" ]] && base="$branch"

    _bs_set_branch_meta "$repo" "$branch" "$new_desc" "$base"
    echo "Description updated: $new_desc"
  fi
}
