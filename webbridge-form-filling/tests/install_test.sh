#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/../.." && pwd)"
fixture_home="$(mktemp -d)"
trap 'rm -rf "$fixture_home"' EXIT

mkdir -p "$fixture_home/.codex/skills" "$fixture_home/.opencode/skills"

HOME="$fixture_home" bash "$repo_dir/webbridge-form-filling/install.sh" --dry-run \
  | grep -q "would install 2 agent(s), skipped 3"

HOME="$fixture_home" bash "$repo_dir/webbridge-form-filling/install.sh" --agent codex
cmp \
  "$repo_dir/webbridge-form-filling/dist/codex/SKILL.md" \
  "$fixture_home/.codex/skills/webbridge-form-filling/SKILL.md"
cmp \
  "$repo_dir/webbridge-form-filling/dist/codex/agents/openai.yaml" \
  "$fixture_home/.codex/skills/webbridge-form-filling/agents/openai.yaml"

if HOME="$fixture_home" bash "$repo_dir/webbridge-form-filling/install.sh" --agent unknown >/dev/null 2>&1; then
  echo "expected an unsupported agent to fail" >&2
  exit 1
fi

echo "ok: installer smoke test"
