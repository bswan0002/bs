# cd.sh — bs cd command for switching between projects and branch spaces

_bs_cd() {
  local project="$1"
  local branch="$2"

  # Interactive mode: no args - pick project first
  if [[ -z "$project" ]]; then
    local projects
    projects="$(_bs_list_projects)"

    if [[ -z "$projects" ]]; then
      echo "No bs-managed projects found."
      return 1
    fi

    project="$(echo "$projects" | gum filter --height=15 --placeholder="Type to filter..." --header="Select project:")"
    [[ -z "$project" ]] && return 1
  fi

  # Validate project exists
  local meta_file="$BS_META/$project/_project.json"
  if [[ ! -f "$meta_file" ]]; then
    echo "bs cd: unknown project '$project'"
    return 1
  fi

  # Get source path from project metadata
  local source
  source="$(grep -o '"source"[[:space:]]*:[[:space:]]*"[^"]*"' "$meta_file" | cut -d'"' -f4)"

  # If branch specified directly, cd to it
  if [[ -n "$branch" ]]; then
    # Check for "main" as special case
    if [[ "$branch" == "main" || "$branch" == "source" ]]; then
      if [[ -d "$source" ]]; then
        cd "$source"
        echo "Switched to: $source"
        return 0
      else
        echo "bs cd: source repo not found at $source"
        return 1
      fi
    fi

    # Try to find the branch space
    local clone_path
    clone_path="$(_bs_clone_path "$project" "$branch")"
    if [[ -d "$clone_path" ]]; then
      cd "$clone_path"
      echo "Switched to: $clone_path"
      return 0
    else
      echo "bs cd: branch space '$branch' not found for project '$project'"
      return 1
    fi
  fi

  # No branch specified - show branch picker
  local options=""
  local line

  # Add main repo option first
  if [[ -n "$source" && -d "$source" ]]; then
    local main_status
    main_status="$(_bs_get_status "$source")"
    line="$(printf "%-28s  %-18s  %-5s  %s" "main (source)" "" "" "$main_status")"
    options="$line|$source"
  fi

  # Add branch spaces
  local sanitized_branch branch_name clone_path meta desc created age git_status
  for sanitized_branch in $(_bs_list_branches "$project"); do
    # Skip entries containing = (stale shell state)
    [[ "$sanitized_branch" == *"="* ]] && continue

    branch_name="$(_bs_unsanitize_branch "$sanitized_branch")"
    clone_path="$(_bs_clone_path "$project" "$branch_name")"
    meta="$(_bs_get_branch_meta "$project" "$branch_name")"

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
    local display_branch="${branch_name:0:26}"
    local display_desc="${desc:0:16}"

    line="$(printf "%-28s  %-18s  %-5s  %s" "$display_branch" "$display_desc" "$age" "$git_status")"

    [[ -n "$options" ]] && options+=$'\n'
    options+="$line|$clone_path"
  done

  if [[ -z "$options" ]]; then
    echo "No branch spaces for $project."
    return 1
  fi

  # Run gum filter with styled header
  local header="  $(printf '%-28s  %-18s  %-5s  %s' 'BRANCH' 'DESCRIPTION' 'AGE' 'STATUS')"
  local selected
  selected="$(echo "$options" | cut -d'|' -f1 | gum filter \
    --height=15 \
    --header="$header" \
    --placeholder="Type to search..." \
    --indicator.foreground="212")"

  [[ -z "$selected" ]] && return 1

  # Match selection back to target path
  local target_path
  target_path="$(echo "$options" | grep -F "$selected" | head -1 | cut -d'|' -f2)"

  if [[ -d "$target_path" ]]; then
    cd "$target_path"
    echo "Switched to: $target_path"
  else
    echo "bs cd: path not found"
    return 1
  fi
}
