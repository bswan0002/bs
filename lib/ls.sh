# ls.sh — bs ls and bs (no args) commands

# Non-interactive list with gum table
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

  # Build CSV data for gum table
  local data="BRANCH,DESCRIPTION,AGE,STATUS"

  # Show main repo if source exists
  if [[ -n "$BS_SOURCE" && -d "$BS_SOURCE" ]]; then
    local main_status; main_status="$(_bs_get_status "$BS_SOURCE")"
    data+=$'\n'"main (source),,,$main_status"
  fi

  # List branch spaces
  for sanitized_branch in $(_bs_list_branches "$repo"); do
    # Skip entries containing = (stale shell state)
    [[ "$sanitized_branch" == *"="* ]] && continue

    local branch; branch="$(_bs_unsanitize_branch "$sanitized_branch")"
    local clone_path; clone_path="$(_bs_clone_path "$repo" "$branch")"

    local meta; meta="$(_bs_get_branch_meta "$repo" "$branch")"

    local desc=""
    local created=""
    if [[ -n "$meta" ]]; then
      desc="$(echo "$meta" | grep -o '"desc"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)"
      created="$(echo "$meta" | grep -o '"created"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)"
    fi

    local age=""
    [[ -n "$created" ]] && age="$(_bs_format_age "$created")"

    local git_status=""
    [[ -d "$clone_path" ]] && git_status="$(_bs_get_status "$clone_path")"

    # Truncate long values for display
    local display_branch="${branch:0:26}"
    local display_desc="${desc:0:16}"

    data+=$'\n'"$display_branch,$display_desc,$age,$git_status"
  done

  # Render with gum table
  echo "$data" | gum table \
    --separator="," \
    --border="rounded" \
    --header.foreground="99" \
    --print
}

# Interactive picker (bs with no args)
_bs_pick() {
  _bs_detect_context

  local repo="$BS_REPO"
  local projects project_meta options line main_status
  local branch clone_path meta desc created age git_status
  local display_branch display_desc selected target_path new_branch

  # If no context, pick project first
  if [[ -z "$repo" ]]; then
    projects="$(_bs_list_projects)"

    if [[ -z "$projects" ]]; then
      echo "No bs-managed projects found."
      echo "Use 'bs new <branch>' from within a git repository to create your first branch space."
      return 0
    fi

    repo="$(echo "$projects" | gum filter --height=15 --placeholder="Type to filter..." --header="Select project:")"
    if [[ -z "$repo" ]]; then
      return 0
    fi

    # Load project meta for source
    project_meta="$BS_META/$repo/_project.json"
    if [[ -f "$project_meta" ]]; then
      BS_SOURCE="$(grep -o '"source"[[:space:]]*:[[:space:]]*"[^"]*"' "$project_meta" | cut -d'"' -f4)"
    fi
  fi

  # Build picker options: "formatted_display|path"
  options=""

  # Add main repo option
  if [[ -n "$BS_SOURCE" && -d "$BS_SOURCE" ]]; then
    main_status="$(_bs_get_status "$BS_SOURCE")"
    line="$(printf "%-28s  %-18s  %-5s  %s" "main (source)" "" "" "$main_status")"
    options="$line|$BS_SOURCE"
  fi

  # Add branch spaces
  for sanitized_branch in $(_bs_list_branches "$repo"); do
    # Skip entries containing = (stale shell state)
    [[ "$sanitized_branch" == *"="* ]] && continue

    branch="$(_bs_unsanitize_branch "$sanitized_branch")"
    clone_path="$(_bs_clone_path "$repo" "$branch")"

    meta="$(_bs_get_branch_meta "$repo" "$branch")"

    desc=""
    created=""
    if [[ -n "$meta" ]]; then
      desc="$(echo "$meta" | grep -o '"desc"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)"
      created="$(echo "$meta" | grep -o '"created"[[:space:]]*:[[:space:]]*"[^"]*"' | cut -d'"' -f4)"
    fi

    age=""
    [[ -n "$created" ]] && age="$(_bs_format_age "$created")"

    git_status=""
    [[ -d "$clone_path" ]] && git_status="$(_bs_get_status "$clone_path")"

    # Truncate long values for display
    display_branch="${branch:0:26}"
    display_desc="${desc:0:16}"

    line="$(printf "%-28s  %-18s  %-5s  %s" "$display_branch" "$display_desc" "$age" "$git_status")"

    [[ -n "$options" ]] && options+=$'\n'
    options+="$line|$clone_path"
  done

  # Add create option at the end
  line="$(printf "%-28s" "[+] Create new branch...")"
  [[ -n "$options" ]] && options+=$'\n'
  options+="$line|__CREATE__"

  if [[ -z "$options" ]]; then
    echo "No branch spaces for $repo."
    echo "Use 'bs new <branch>' to create one."
    return 0
  fi

  # Run gum filter with styled header (2-space prefix aligns with gum's bullet indent)
  local header="  $(printf '%-28s  %-18s  %-5s  %s' 'BRANCH' 'DESCRIPTION' 'AGE' 'STATUS')"
  selected="$(echo "$options" | cut -d'|' -f1 | gum filter \
    --height=15 \
    --header="$header" \
    --placeholder="Type to search..." \
    --indicator.foreground="212")"

  [[ -z "$selected" ]] && return 0

  # Match selection back to target path
  target_path="$(echo "$options" | grep -F "$selected" | head -1 | cut -d'|' -f2)"

  # Handle selection
  case "$target_path" in
    __CREATE__)
      new_branch="$(gum input --placeholder "Enter new branch name")"
      [[ -n "$new_branch" ]] && _bs_new "$new_branch"
      ;;
    *)
      if [[ -d "$target_path" ]]; then
        cd "$target_path"
        echo "Switched to: $target_path"
      fi
      ;;
  esac
}
