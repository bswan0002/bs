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
  local source_root repo_name repo_url
  if [[ "$BS_CONTEXT" == "clone" ]]; then
    repo_name="$BS_REPO"
    source_root="$BS_SOURCE"
    if [[ -z "$source_root" || ! -d "$source_root" ]]; then
      echo "Error: cannot find source repo for project '$repo_name'"
      return 1
    fi
    repo_url="$(git -C "$source_root" remote get-url origin 2>/dev/null)"
  else
    source_root="$(git rev-parse --show-toplevel)"
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
    local existing_path
    existing_path="$(_bs_clone_path "$repo_name" "$branch")"
    echo "  Path: $existing_path"
    return 1
  fi

  # Fetch latest from origin
  echo "Fetching from origin..."
  git -C "$source_root" fetch --quiet origin

  # Check if branch already exists on origin
  local branch_exists_on_origin=false
  if git -C "$source_root" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    branch_exists_on_origin=true
    echo "Branch '$branch' exists on origin"
  fi

  # Get current branch as default for base selection
  local current_branch
  current_branch="$(_bs_current_branch)"

  # Select base branch if needed and not provided
  if [[ "$branch_exists_on_origin" == false && -z "$base_branch" ]]; then
    base_branch="$(
      git -C "$source_root" branch -r --format='%(refname:short)' |
        sed 's|^origin/||' |
        fzf \
          --height=20 \
          --prompt='Select base branch: ' \
          --query="$current_branch"
    )"

    if [[ -z "$base_branch" ]]; then
      echo "Aborted"
      return 1
    fi
  fi

  # Prompt for description
  local desc=""
  if command -v gum >/dev/null 2>&1; then
    desc="$(gum input --placeholder "Description (optional, enter to skip)")" || true
  else
    printf "Description (optional): "
    read -r desc
  fi

  # Create clone path
  local clone_path
  clone_path="$(_bs_clone_path "$repo_name" "$branch")"
  mkdir -p "$(dirname "$clone_path")"

  echo "Creating branch space at $clone_path..."

  # Clone using reference for speed
  if ! git clone --quiet --reference "$source_root" "$repo_url" "$clone_path"; then
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

  # Process .bsconfig from source repo
  local config_file="$source_root/.bsconfig"

  if [[ -f "$config_file" ]]; then
    echo "Loading .bsconfig..."

    # Copy specified files/dirs
    while IFS='= ' read -r key value; do
      # Skip empty lines and comments
      [[ -z "$key" || "$key" == \#* ]] && continue
      # Trim whitespace
      value="${value#"${value%%[![:space:]]*}"}"
      value="${value%"${value##*[![:space:]]}"}"

      if [[ "$key" == "copy" && -n "$value" ]]; then
        local src="$source_root/$value"
        if [[ -e "$src" ]]; then
          local dest_dir
          dest_dir="$(dirname "$value")"
          [[ "$dest_dir" != "." ]] && mkdir -p "$dest_dir"
          cp -R "$src" "$value"
          echo "  Copied $value"
        else
          echo "  Warning: $value not found, skipping"
        fi
      fi
    done < "$config_file"

    # Run post command
    local postcmd
    postcmd="$(grep -E '^postcmd[[:space:]]*=' "$config_file" | head -1 | cut -d'=' -f2-)"
    postcmd="${postcmd#"${postcmd%%[![:space:]]*}"}"
    if [[ -n "$postcmd" ]]; then
      echo "Running postcmd: $postcmd"
      eval "$postcmd"
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
