# core.sh — shared utilities for bs

BS_ROOT="${HOME}/.bs"
BS_CLONES="${BS_ROOT}/clones"
BS_META="${BS_ROOT}/meta"

# Ensure storage directories exist
_bs_ensure_dirs() {
  mkdir -p "$BS_CLONES" "$BS_META"
}

# Sanitize branch name for filesystem (/ -> --)
_bs_sanitize_branch() {
  echo "${1//\//--}"
}

# Unsanitize branch name for git operations (-- -> /)
_bs_unsanitize_branch() {
  printf '%s\n' "${1//--//}"
}

# Get repo name from current git repo
_bs_get_repo_name() {
  local root; root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
  basename "$root"
}

# Detect project context from cwd
# Sets: BS_CONTEXT (main|clone|none), BS_REPO, BS_BRANCH (if clone), BS_SOURCE (if known)
_bs_detect_context() {
  BS_CONTEXT="none"
  BS_REPO=""
  BS_BRANCH=""
  BS_SOURCE=""

  local cwd; cwd="$(pwd)"

  # Check if we're inside a branch space clone
  if [[ "$cwd" == "$BS_CLONES"/* ]]; then
    # Parse: ~/.bs/clones/<repo>/<branch>/...
    local rel="${cwd#$BS_CLONES/}"
    BS_REPO="${rel%%/*}"
    rel="${rel#*/}"
    BS_BRANCH="${rel%%/*}"
    BS_CONTEXT="clone"

    # Load source from project meta
    local project_meta="$BS_META/$BS_REPO/_project.json"
    if [[ -f "$project_meta" ]]; then
      BS_SOURCE="$(grep -o '"source"[[:space:]]*:[[:space:]]*"[^"]*"' "$project_meta" | cut -d'"' -f4)"
    fi
    return 0
  fi

  # Check if we're in a git repo
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 0
  fi

  local repo_name; repo_name="$(_bs_get_repo_name)"

  # Check if this repo is bs-managed (has project meta)
  local project_meta="$BS_META/$repo_name/_project.json"
  if [[ -f "$project_meta" ]]; then
    BS_REPO="$repo_name"
    BS_CONTEXT="main"
    BS_SOURCE="$(grep -o '"source"[[:space:]]*:[[:space:]]*"[^"]*"' "$project_meta" | cut -d'"' -f4)"
    return 0
  fi

  # Not yet bs-managed, but we're in a git repo — could become managed
  BS_REPO="$repo_name"
  BS_CONTEXT="unmanaged"
  BS_SOURCE="$(git rev-parse --show-toplevel)"
}

# Get current git branch
_bs_current_branch() {
  git rev-parse --abbrev-ref HEAD 2>/dev/null
}

# Read project metadata
_bs_get_project_meta() {
  local repo="$1"
  local meta_file="$BS_META/$repo/_project.json"
  [[ -f "$meta_file" ]] && cat "$meta_file"
}

# Write project metadata (creates on first use)
_bs_set_project_meta() {
  local repo="$1"
  local source="$2"
  local meta_dir="$BS_META/$repo"
  local meta_file="$meta_dir/_project.json"

  mkdir -p "$meta_dir"

  if [[ ! -f "$meta_file" ]]; then
    cat > "$meta_file" <<EOF
{
  "source": "$source",
  "registered": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
  fi
}

# Read branch space metadata
_bs_get_branch_meta() {
  local repo="$1"
  local branch="$2"
  local sanitized; sanitized="$(_bs_sanitize_branch "$branch")"
  local meta_file="$BS_META/$repo/${sanitized}.json"
  [[ -f "$meta_file" ]] && cat "$meta_file"
}

# Write branch space metadata
_bs_set_branch_meta() {
  local repo="$1"
  local branch="$2"
  local desc="$3"
  local base="$4"
  local sanitized; sanitized="$(_bs_sanitize_branch "$branch")"
  local meta_file="$BS_META/$repo/${sanitized}.json"

  mkdir -p "$BS_META/$repo"
  cat > "$meta_file" <<EOF
{
  "desc": "$desc",
  "base": "$base",
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
}

# Delete branch space metadata
_bs_delete_branch_meta() {
  local repo="$1"
  local branch="$2"
  local sanitized; sanitized="$(_bs_sanitize_branch "$branch")"
  rm -f "$BS_META/$repo/${sanitized}.json"
}

# List all bs-managed projects
_bs_list_projects() {
  [[ -d "$BS_META" ]] || return
  for dir in "$BS_META"/*/; do
    [[ -d "$dir" ]] && basename "$dir"
  done
}

# List branch spaces for a project
_bs_list_branches() {
  local repo="$1"
  local meta_dir="$BS_META/$repo"
  [[ -d "$meta_dir" ]] || return

  for f in "$meta_dir"/*.json; do
    [[ -f "$f" ]] || continue
    local name; name="$(basename "$f" .json)"
    [[ "$name" == "_project" ]] && continue
    echo "$name"
  done
}

# Get clone path for a branch space
_bs_clone_path() {
  local repo="$1"
  local branch="$2"
  local sanitized; sanitized="$(_bs_sanitize_branch "$branch")"
  echo "$BS_CLONES/$repo/$repo-$sanitized"
}

# Check if a branch space exists
_bs_branch_exists() {
  local repo="$1"
  local branch="$2"
  local clone_path; clone_path="$(_bs_clone_path "$repo" "$branch")"
  [[ -d "$clone_path" ]]
}

# Format age from ISO date
_bs_format_age() {
  local created="$1"
  local now; now="$(date +%s)"
  local then

  # Strip trailing Z for proper UTC parsing
  local stripped="${created%Z}"

  # macOS date vs GNU date
  if date -j >/dev/null 2>&1; then
    # macOS: parse with TZ=UTC to treat time as UTC
    then="$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null)" || then="$now"
  else
    then="$(date -d "$created" +%s 2>/dev/null)" || then="$now"
  fi

  local diff=$((now - then))

  # Handle edge cases: negative or very small values
  if ((diff < 0)) || ((diff < 60)); then
    echo "now"
  elif ((diff < 3600)); then
    echo "$((diff / 60))m"
  elif ((diff < 86400)); then
    echo "$((diff / 3600))h"
  elif ((diff < 604800)); then
    echo "$((diff / 86400))d"
  else
    echo "$((diff / 604800))w"
  fi
}

# Get status indicators for a branch space
_bs_get_status() {
  local clone_path="$1"

  [[ -d "$clone_path" ]] || return

  local git_status=""

  # Check for dirty working tree
  if [[ -n "$(git -C "$clone_path" status --porcelain 2>/dev/null)" ]]; then
    git_status+="dirty"
  fi

  # Check for unpushed commits
  local ahead; ahead="$(git -C "$clone_path" rev-list --count @{upstream}..HEAD 2>/dev/null)"
  if [[ -n "$ahead" && "$ahead" -gt 0 ]]; then
    [[ -n "$git_status" ]] && git_status+=" "
    git_status+="ahead:$ahead"
  fi

  echo "$git_status"
}
