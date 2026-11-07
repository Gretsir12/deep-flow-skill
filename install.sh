#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${DEEPFLOW_SKILL_REPO:-https://github.com/Gretsir12/deep-flow-skill.git}"
SKILL_ID="deepflow"

TMP_DIR=""
CUSTOM_DIR=""
PROJECT_INSTALL=0
TARGETS=()

cleanup() {
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
DeepFlow Skill installer

Usage:
  install.sh [options]

Options:
  --project        Install into ./.opencode/skills/deepflow
  --opencode       Install into ~/.config/opencode/skills/deepflow
  --claude         Install into ~/.claude/skills/deepflow
  --agents         Install into ~/.agents/skills/deepflow
  --all            Install into all supported global locations
  --dir <path>     Install into <path>/deepflow
  -h, --help       Show this help

Without options, the installer adds the Skill to the global OpenCode
directory and also to ~/.claude/skills or ~/.agents/skills when those
directories already exist.

Examples:
  curl -fsSL https://raw.githubusercontent.com/Gretsir12/deep-flow-skill/main/install.sh | bash
  curl -fsSL https://raw.githubusercontent.com/Gretsir12/deep-flow-skill/main/install.sh | bash -s -- --project
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      PROJECT_INSTALL=1
      shift
      ;;
    --opencode)
      TARGETS+=("opencode")
      shift
      ;;
    --claude)
      TARGETS+=("claude")
      shift
      ;;
    --agents)
      TARGETS+=("agents")
      shift
      ;;
    --all)
      TARGETS+=("opencode" "claude" "agents")
      shift
      ;;
    --dir)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "Missing value for --dir" >&2
        exit 1
      fi
      CUSTOM_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

SOURCE_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -f "$SCRIPT_DIR/SKILL.md" ]]; then
    SOURCE_DIR="$SCRIPT_DIR"
  fi
fi

if [[ -z "$SOURCE_DIR" ]]; then
  if ! command -v git >/dev/null 2>&1; then
    echo "git is required to download the Skill. Install git and try again." >&2
    exit 1
  fi

  TMP_DIR="$(mktemp -d)"
  echo "Downloading the DeepFlow Skill..."
  git clone --depth 1 "$REPO_URL" "$TMP_DIR/skill" >/dev/null 2>&1
  SOURCE_DIR="$TMP_DIR/skill"
fi

if [[ ! -f "$SOURCE_DIR/SKILL.md" ]]; then
  echo "SKILL.md was not found in $SOURCE_DIR" >&2
  exit 1
fi

install_skill() {
  local root="$1"
  local dest="$root/$SKILL_ID"

  mkdir -p "$root"
  rm -rf "$dest"
  mkdir -p "$dest"
  cp "$SOURCE_DIR/SKILL.md" "$dest/SKILL.md"

  if [[ -d "$SOURCE_DIR/references" ]]; then
    cp -R "$SOURCE_DIR/references" "$dest/references"
  fi

  printf 'Installed %s -> %s\n' "$SKILL_ID" "$dest"
}

expand_tilde() {
  case "$1" in
    "~")
      printf '%s\n' "$HOME"
      ;;
    "~/"*)
      printf '%s\n' "$HOME/${1#\~/}"
      ;;
    *)
      printf '%s\n' "$1"
      ;;
  esac
}

if [[ -n "$CUSTOM_DIR" ]]; then
  install_skill "$(expand_tilde "$CUSTOM_DIR")"
  exit 0
fi

if [[ "$PROJECT_INSTALL" -eq 1 ]]; then
  install_skill "$PWD/.opencode/skills"
  exit 0
fi

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  TARGETS=("opencode")
  if [[ -d "$HOME/.claude" ]]; then
    TARGETS+=("claude")
  fi
  if [[ -d "$HOME/.agents" ]]; then
    TARGETS+=("agents")
  fi
fi

for target in "${TARGETS[@]}"; do
  case "$target" in
    opencode)
      install_skill "$HOME/.config/opencode/skills"
      ;;
    claude)
      install_skill "$HOME/.claude/skills"
      ;;
    agents)
      install_skill "$HOME/.agents/skills"
      ;;
    *)
      echo "Unknown install target: $target" >&2
      exit 1
      ;;
  esac
done

echo
echo "Done. The skill ID is \"$SKILL_ID\"."
echo "Reload your agent or start a new session to pick it up."
