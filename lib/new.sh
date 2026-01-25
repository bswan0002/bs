# new.sh — bs new command

_bs_new() {
  local branch="$1"
  local base_branch="$2"

  if [[ -z "$branch" ]]; then
    echo "Usage: bs new <branch-name> [base-branch]"
    return 1
  fi

  # Detect context
  _bs_detect_context

  if [[ "$BS_CONTEXT" == "none" ]]; then
    echo "Error: not inside a git repository"
    return 1
  fi

  # Get source info
  # config_root = where to read .bsconfig and copy files from (determined later)
  # source_root = main repo (used for git operations and reference clone)
  local config_root source_root repo_name repo_url
  config_root="$(git rev-parse --show-toplevel)"
  if [[ "$BS_CONTEXT" == "clone" ]]; then
    repo_name="$BS_REPO"
    source_root="$BS_SOURCE"
    if [[ -z "$source_root" || ! -d "$source_root" ]]; then
      echo "Error: cannot find source repo for project '$repo_name'"
      return 1
    fi
    repo_url="$(git -C "$source_root" remote get-url origin 2>/dev/null)"
  else
    source_root="$config_root"
    repo_name="$(_bs_get_repo_name)"
    repo_url="$(git remote get-url origin 2>/dev/null)"
  fi

  if [[ -z "$repo_url" ]]; then
    echo "Error: remote 'origin' not found"
    return 1
  fi

  # Ensure project is registered
  _bs_ensure_dirs
  _bs_set_project_meta "$repo_name" "$source_root"

  # Check if branch space already exists
  if _bs_branch_exists "$repo_name" "$branch"; then
    echo "Error: branch space '$branch' already exists for $repo_name"
    local existing_path; existing_path="$(_bs_clone_path "$repo_name" "$branch")"
    echo "  Path: $existing_path"
    return 1
  fi

  # Fetch latest from origin
  gum spin --spinner dot --title "Fetching from origin..." -- git -C "$source_root" fetch --quiet --prune origin

  # Check if branch already exists on origin
  local branch_exists_on_origin=false
  if git -C "$source_root" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    branch_exists_on_origin=true
    echo "Branch '$branch' exists on origin"
  fi

  # Get current branch as default for base selection
  local current_branch; current_branch="$(_bs_current_branch)"

  # Select base branch if needed and not provided
  if [[ "$branch_exists_on_origin" == false && -z "$base_branch" ]]; then
    local branches
    branches="$(git -C "$source_root" branch -r --format='%(refname:short)' | sed 's|^origin/||' | grep -v '^HEAD$')"
    # Put main/master first
    branches="$(echo "$branches" | awk '/^(main|master)$/ {print; next} {other[NR]=$0} END {for(i in other) print other[i]}')"

    base_branch="$(echo "$branches" | gum filter --height=15 --placeholder="Type to filter..." --header="Select base branch:")"

    if [[ -z "$base_branch" ]]; then
      echo "Aborted"
      return 1
    fi
  fi

  # If base branch exists as a local branch space, use its config
  if [[ -n "$base_branch" ]] && _bs_branch_exists "$repo_name" "$base_branch"; then
    config_root="$(_bs_clone_path "$repo_name" "$base_branch")"
  fi

  # Prompt for description
  local desc=""
  desc="$(gum input --placeholder "Description (optional, enter to skip)")" || true

  # Create clone path
  local clone_path; clone_path="$(_bs_clone_path "$repo_name" "$branch")"
  mkdir -p "$(dirname "$clone_path")"

  # Clone using reference for speed
  if ! gum spin --spinner dot --title "Creating branch space at $clone_path..." -- git clone --quiet --reference "$source_root" "$repo_url" "$clone_path"; then
    echo "Error: clone failed"
    return 1
  fi

  cd "$clone_path" || return 1

  # Check out the branch
  if [[ "$branch_exists_on_origin" == true ]]; then
    git checkout -B "$branch" "origin/$branch" --quiet
  else
    # Ensure base branch exists
    if ! git show-ref --verify --quiet "refs/remotes/origin/$base_branch"; then
      echo "Error: base branch '$base_branch' not found on origin"
      cd - >/dev/null
      rm -rf "$clone_path"
      return 1
    fi
    git checkout -B "$base_branch" "origin/$base_branch" --quiet
    git checkout -b "$branch" --quiet
  fi

  # Save metadata
  _bs_set_branch_meta "$repo_name" "$branch" "$desc" "${base_branch:-$branch}"

  # Process .bsconfig (prefer base branch space, fall back to main project)
  local config_file="$config_root/.bsconfig"
  if [[ ! -f "$config_file" && "$config_root" != "$source_root" ]]; then
    config_file="$source_root/.bsconfig"
    config_root="$source_root"
  fi

  if [[ -f "$config_file" ]]; then
    echo "Loading .bsconfig from $config_root..."

    # Copy specified files/dirs (use grep/cut to avoid IFS issues in zsh)
    grep -E '^copy\s*=' "$config_file" 2>/dev/null | while read -r line; do
      local value="${line#*=}"
      # Trim whitespace
      value="${value#"${value%%[![:space:]]*}"}"
      value="${value%"${value##*[![:space:]]}"}"

      if [[ -n "$value" ]]; then
        local src="$config_root/$value"
        if [[ -e "$src" ]]; then
          local dest_dir; dest_dir="$(dirname "$value")"
          [[ "$dest_dir" != "." ]] && mkdir -p "$dest_dir"
          cp -R "$src" "$value"
          echo "  Copied $value"
        else
          echo "  Warning: $value not found in $config_root, skipping"
        fi
      fi
    done

    # Run post command (supports backslash line continuations)
    local postcmd=""
    local in_postcmd=false
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$in_postcmd" == false && "$line" =~ ^postcmd[[:space:]]*= ]]; then
        postcmd="${line#*=}"
        in_postcmd=true
      elif [[ "$in_postcmd" == true ]]; then
        postcmd+="$line"
      fi
      if [[ "$in_postcmd" == true ]]; then
        if [[ "$postcmd" =~ \\$ ]]; then
          # Strip trailing backslash (line continuation)
          postcmd="${postcmd%\\}"
        else
          break
        fi
      fi
    done < "$config_file"
    postcmd="${postcmd#"${postcmd%%[![:space:]]*}"}"
    if [[ -n "$postcmd" ]]; then
      gum spin --spinner dot --title "Running postcmd..." -- bash -c "$postcmd"
    fi
  fi

  echo ""
  if [[ "$branch_exists_on_origin" == true ]]; then
    echo "Created branch space '$branch' (from origin)"
  else
    echo "Created branch space '$branch' (based on '$base_branch')"
  fi
  echo "  Path: $clone_path"
  [[ -n "$desc" ]] && echo "  Description: $desc"
}
