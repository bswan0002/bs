# ls.sh — bs ls and bs (no args) commands

# Non-interactive list
_bs_ls() {
  _bs_detect_context

  local repo="$BS_REPO"

  # If no context, show all projects
  if [[ -z "$repo" ]]; then
    echo "All bs-managed projects:"
    echo ""
    for proj in $(_bs_list_projects); do
      local source=""
      local project_meta="$BS_META/$proj/_project.json"
      if [[ -f "$project_meta" ]]; then
        source="$(grep -o '"source"[[:space:]]*:[[:space:]]*"[^"]*"' "$project_meta" | cut -d'"' -f4)"
      fi
      printf "  %-20s %s\n" "$proj" "$source"
    done
    return 0
  fi

  echo "Branch spaces for $repo:"
  echo ""

  # Header
  printf "  %-30s %-30s %-6s %s\n" "BRANCH" "DESCRIPTION" "AGE" "STATUS"
  printf "  %-30s %-30s %-6s %s\n" "------" "-----------" "---" "------"

  # Show main repo if source exists
  if [[ -n "$BS_SOURCE" && -d "$BS_SOURCE" ]]; then
    local main_status
    main_status="$(_bs_get_status "$BS_SOURCE")"
    printf "  %-30s %-30s %-6s %s\n" "main (source)" "" "" "$main_status"
  fi

  # List branch spaces
  for sanitized_branch in $(_bs_list_branches "$repo"); do
    local branch
    branch="$(_bs_unsanitize_branch "$sanitized_branch")"
    local clone_path
    clone_path="$(_bs_clone_path "$repo" "$branch")"

    local meta
    meta="$(_bs_get_branch_meta "$repo" "$branch")"

    local desc=""
    local created=""
    if [[ -n "$meta" ]]; then
      desc="$(echo "$meta" | grep -o '"desc"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)"
      created="$(echo "$meta" | grep -o '"created"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)"
    fi

    local age=""
    [[ -n "$created" ]] && age="$(_bs_format_age "$created")"

    local status=""
    [[ -d "$clone_path" ]] && status="$(_bs_get_status "$clone_path")"

    # Truncate long values
    local display_branch="${branch:0:28}"
    local display_desc="${desc:0:28}"

    printf "  %-30s %-30s %-6s %s\n" "$display_branch" "$display_desc" "$age" "$status"
  done
}

# Interactive picker (bs with no args)
_bs_pick() {
  _bs_detect_context

  local repo="$BS_REPO"

  # If no context, pick project first
  if [[ -z "$repo" ]]; then
    local projects
    projects="$(_bs_list_projects)"

    if [[ -z "$projects" ]]; then
      echo "No bs-managed projects found."
      echo "Use 'bs new <branch>' from within a git repository to create your first branch space."
      return 0
    fi

    repo="$(echo "$projects" | fzf --height=20 --prompt='Select project: ')"
    if [[ -z "$repo" ]]; then
      return 0
    fi

    # Load project meta for source
    local project_meta="$BS_META/$repo/_project.json"
    if [[ -f "$project_meta" ]]; then
      BS_SOURCE="$(grep -o '"source"[[:space:]]*:[[:space:]]*"[^"]*"' "$project_meta" | cut -d'"' -f4)"
    fi
  fi

  # Build picker options
  local options=""

  # Add main repo option
  if [[ -n "$BS_SOURCE" && -d "$BS_SOURCE" ]]; then
    local main_status
    main_status="$(_bs_get_status "$BS_SOURCE")"
    options="main (source)|${BS_SOURCE}||${main_status}"
  fi

  # Add branch spaces
  for sanitized_branch in $(_bs_list_branches "$repo"); do
    local branch
    branch="$(_bs_unsanitize_branch "$sanitized_branch")"
    local clone_path
    clone_path="$(_bs_clone_path "$repo" "$branch")"

    local meta
    meta="$(_bs_get_branch_meta "$repo" "$branch")"

    local desc=""
    local created=""
    if [[ -n "$meta" ]]; then
      desc="$(echo "$meta" | grep -o '"desc"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)"
      created="$(echo "$meta" | grep -o '"created"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)"
    fi

    local age=""
    [[ -n "$created" ]] && age="$(_bs_format_age "$created")"

    local status=""
    [[ -d "$clone_path" ]] && status="$(_bs_get_status "$clone_path")"

    [[ -n "$options" ]] && options+=$'\n'
    options+="${branch}|${clone_path}|${desc}|${age}|${status}"
  done

  if [[ -z "$options" ]]; then
    echo "No branch spaces for $repo."
    echo "Use 'bs new <branch>' to create one."
    return 0
  fi

  # Run fzf with formatted display
  local selection
  selection="$(
    echo "$options" |
      awk -F'|' '{printf "%-30s │ %-25s │ %-5s │ %s\n", $1, $3, $4, $5}' |
      fzf \
        --height=20 \
        --prompt="$repo > " \
        --print-query \
        --header="BRANCH                         │ DESCRIPTION               │ AGE   │ STATUS"
  )"

  # Parse fzf output (first line is query, rest is selection)
  local query selected_line
  query="$(echo "$selection" | head -1)"
  selected_line="$(echo "$selection" | tail -n +2 | head -1)"

  # If nothing selected but query entered, offer to create
  if [[ -z "$selected_line" && -n "$query" ]]; then
    # Check it's not an existing branch
    if ! _bs_branch_exists "$repo" "$query"; then
      if command -v gum &>/dev/null; then
        if gum confirm "Create new branch space '$query'?"; then
          _bs_new "$query"
        fi
      else
        read -r -p "Create new branch space '$query'? [y/N] " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
          _bs_new "$query"
        fi
      fi
    fi
    return 0
  fi

  [[ -z "$selected_line" ]] && return 0

  # Extract branch name from selection (first column, trimmed)
  local selected_branch
  selected_branch="$(echo "$selected_line" | cut -d'│' -f1 | xargs)"

  # Handle main repo selection
  if [[ "$selected_branch" == "main (source)" ]]; then
    if [[ -n "$BS_SOURCE" && -d "$BS_SOURCE" ]]; then
      cd "$BS_SOURCE"
      echo "Switched to main repo: $BS_SOURCE"
    fi
    return 0
  fi

  # cd to selected branch space
  local clone_path
  clone_path="$(_bs_clone_path "$repo" "$selected_branch")"
  if [[ -d "$clone_path" ]]; then
    cd "$clone_path"
    echo "Switched to branch space: $selected_branch"
  else
    echo "Error: clone path not found: $clone_path"
    return 1
  fi
}
