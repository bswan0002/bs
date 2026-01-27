# core.sh — shared utilities for bs

# XDG-compliant paths with defaults
BS_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/bs"
BS_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/bs"
BS_CONFIG_FILE="$BS_CONFIG_HOME/config"
BS_META="$BS_DATA_HOME/meta"

# BS_CLONES is loaded from config (will be set by _bs_load_config or _bs_ensure_dirs)
BS_CLONES=""

# Read a value from config file
_bs_config_get() {
  local key="$1"
  [[ -f "$BS_CONFIG_FILE" ]] || return 1
  grep "^${key}[[:space:]]*=" "$BS_CONFIG_FILE" 2>/dev/null | head -1 | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Write a value to config file
_bs_config_set() {
  local key="$1" value="$2"
  mkdir -p "$BS_CONFIG_HOME"
  if [[ -f "$BS_CONFIG_FILE" ]] && grep -q "^${key}[[:space:]]*=" "$BS_CONFIG_FILE" 2>/dev/null; then
    local tmp; tmp=$(mktemp)
    sed "s|^${key}[[:space:]]*=.*|${key} = ${value}|" "$BS_CONFIG_FILE" > "$tmp"
    mv "$tmp" "$BS_CONFIG_FILE"
  else
    echo "${key} = ${value}" >> "$BS_CONFIG_FILE"
  fi
}

# Load config at source time if it exists
_bs_load_config() {
  if [[ -f "$BS_CONFIG_FILE" ]]; then
    BS_CLONES="$(_bs_config_get clones_dir)"
  fi
}

# First-run setup: prompt for clones directory
_bs_first_run_setup() {
  # Compute smart default based on context
  local default_path
  if git rev-parse --git-dir &>/dev/null; then
    # Inside a git repo - suggest ../clones (sibling directory)
    default_path="$(cd .. && pwd)/clones"
  else
    # Not in a git repo - suggest ./clones (subdirectory)
    default_path="$(pwd)/clones"
  fi

  gum style --bold "Welcome to bs (Branch Space Manager)"
  echo "bs needs a directory to store branch space clones."
  echo "This should NOT be a hidden (dot) directory for best compatibility."
  echo

  local clones_dir
  clones_dir=$(gum input --placeholder "Path for clones" --value "$default_path")

  # Handle empty input (user cancelled)
  if [[ -z "$clones_dir" ]]; then
    echo "Setup cancelled."
    return 1
  fi

  # Expand ~ and make absolute
  clones_dir="${clones_dir/#\~/$HOME}"
  [[ "$clones_dir" != /* ]] && clones_dir="$(pwd)/$clones_dir"

  _bs_config_set "clones_dir" "$clones_dir"
  BS_CLONES="$clones_dir"
  echo "Saved clones directory: $clones_dir"
  echo
  echo "Use 'bs new <branch>' from within a git repository to create your first branch space."
}

# Ensure storage directories exist
_bs_ensure_dirs() {
  # Ensure config exists (run first-time setup if needed)
  if [[ ! -f "$BS_CONFIG_FILE" ]]; then
    _bs_first_run_setup || return 1
  fi

  # Load clones directory from config if not already set
  if [[ -z "$BS_CLONES" ]]; then
    BS_CLONES="$(_bs_config_get clones_dir)"
  fi

  if [[ -z "$BS_CLONES" ]]; then
    echo "Error: clones_dir not set in config. Delete $BS_CONFIG_FILE and run 'bs' to reconfigure." >&2
    return 1
  fi

  mkdir -p "$BS_CLONES" "$BS_META"
}

# Ensure config exists, running first-time setup if needed
# Returns: 0 = config existed, 1 = error, 2 = first-run setup completed
_bs_ensure_config() {
  local first_run=0
  if [[ ! -f "$BS_CONFIG_FILE" ]]; then
    _bs_first_run_setup || return 1
    first_run=1
  fi
  if [[ -z "$BS_CLONES" ]]; then
    BS_CLONES="$(_bs_config_get clones_dir)"
  fi
  [[ -z "$BS_CLONES" ]] && return 1
  ((first_run)) && return 2
  return 0
}

# Load config on source
_bs_load_config

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
    # Parse: ~/.bs/clones/<repo>/<repo>-<branch>/...
    local rel="${cwd#$BS_CLONES/}"
    BS_REPO="${rel%%/*}"
    rel="${rel#*/}"
    local dir_name="${rel%%/*}"
    # Strip repo prefix from directory name to get branch
    BS_BRANCH="${dir_name#$BS_REPO-}"
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
    local name="$(basename "$f" .json)"
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
