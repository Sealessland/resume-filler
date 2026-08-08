#!/usr/bin/env bash
# 一键把 webbridge-form-filling skill 分发到本机所有支持的 agent
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
NAME="webbridge-form-filling"

declare -a TARGETS=(
  "claude-code|$HOME/.claude/skills"
  "codex|$HOME/.codex/skills"
  "omp|$HOME/.omp/agent/skills"
  "opencode|$HOME/.opencode/skills"
  "kimi-code|$HOME/.kimi-code/skills"
)

installed=0
for entry in "${TARGETS[@]}"; do
  variant="${entry%%|*}"
  dir="${entry#*|}"
  if [ ! -d "$dir" ]; then
    echo "skip $variant: $dir not found"
    continue
  fi
  if [ ! -f "$SRC/dist/$variant/SKILL.md" ]; then
    echo "skip $variant: $SRC/dist/$variant/SKILL.md not found"
    continue
  fi
  mkdir -p "$dir/$NAME"
  cp "$SRC/dist/$variant/SKILL.md" "$dir/$NAME/SKILL.md"
  echo "installed $variant -> $dir/$NAME/SKILL.md"
  installed=$((installed + 1))
done

echo "done: $installed/5 agent(s) updated"
