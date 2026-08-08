#!/usr/bin/env bash
# Install generated webbridge-form-filling packages for supported agents.
set -euo pipefail

src_dir="$(cd "$(dirname "$0")" && pwd)"
skill_name="webbridge-form-filling"
dry_run=false
declare -a selected=()
declare -a targets=(
  "claude-code|${HOME}/.claude/skills"
  "codex|${HOME}/.codex/skills"
  "omp|${HOME}/.omp/agent/skills"
  "opencode|${HOME}/.opencode/skills"
  "kimi-code|${HOME}/.kimi-code/skills"
)

usage() {
  cat <<'EOF'
Usage: install.sh [--agent NAME]... [--dry-run]

Without --agent, install to every detected agent directory.
Supported names: claude-code, codex, omp, opencode, kimi-code
EOF
}

is_supported() {
  local candidate="$1" entry
  for entry in "${targets[@]}"; do
    if [[ "${entry%%|*}" == "$candidate" ]]; then
      return 0
    fi
  done
  return 1
}

is_selected() {
  local candidate="$1" item
  if ((${#selected[@]} == 0)); then
    return 0
  fi
  for item in "${selected[@]}"; do
    [[ "$item" == "$candidate" ]] && return 0
  done
  return 1
}

while (($#)); do
  case "$1" in
    --agent)
      [[ $# -ge 2 ]] || { echo "error: --agent requires a name" >&2; usage >&2; exit 2; }
      is_supported "$2" || { echo "error: unsupported agent: $2" >&2; usage >&2; exit 2; }
      selected+=("$2")
      shift 2
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

installed=0
skipped=0
for entry in "${targets[@]}"; do
  variant="${entry%%|*}"
  target_root="${entry#*|}"
  is_selected "$variant" || continue

  package_dir="$src_dir/dist/$variant"
  package="$package_dir/SKILL.md"
  if [[ ! -f "$package" ]]; then
    echo "error: generated package missing: $package" >&2
    echo "run: python3 $src_dir/scripts/sync_dist.py" >&2
    exit 1
  fi
  if [[ ! -d "$target_root" ]]; then
    echo "skip $variant: agent directory not found ($target_root)"
    skipped=$((skipped + 1))
    continue
  fi

  destination_dir="$target_root/$skill_name"
  destination="$destination_dir/SKILL.md"
  if $dry_run; then
    echo "would install $variant -> $destination"
  else
    mkdir -p "$destination_dir"
    temp_file="$destination.tmp.$$"
    cp "$package" "$temp_file"
    mv "$temp_file" "$destination"
    if [[ -f "$package_dir/agents/openai.yaml" ]]; then
      mkdir -p "$destination_dir/agents"
      metadata_temp="$destination_dir/agents/openai.yaml.tmp.$$"
      cp "$package_dir/agents/openai.yaml" "$metadata_temp"
      mv "$metadata_temp" "$destination_dir/agents/openai.yaml"
    fi
    echo "installed $variant -> $destination"
  fi
  installed=$((installed + 1))
done

if ((${#selected[@]} > 0 && installed == 0)); then
  echo "error: none of the selected agent directories exist" >&2
  exit 1
fi

verb="installed"
$dry_run && verb="would install"
echo "done: $verb $installed agent(s), skipped $skipped"
