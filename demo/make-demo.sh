#!/usr/bin/env zsh
# Record the real plugin using only fabricated workspace/history data.
set -euo pipefail
root=${0:A:h:h}
[[ -n ${TYPESAFE_API_KEY:-} ]] || { print -u2 'TYPESAFE_API_KEY is required'; exit 2 }
for tool in vhs ffmpeg node zsh; do
  command -v "$tool" >/dev/null || { print -u2 "Missing tool: $tool"; exit 2 }
done

export ZJ_DEMO_DIR=$(mktemp -d "${TMPDIR:-/tmp}/zj-demo.XXXXXX")
trap 'rm -rf -- "$ZJ_DEMO_DIR"' EXIT
mkdir -p "$ZJ_DEMO_DIR/workspace/payments/java-payments" "$ZJ_DEMO_DIR/workspace/storefront/react-storefront"
export ZJ_PLUGIN_ROOT="$root"
export ZDOTDIR="$ZJ_DEMO_DIR"
export JEV_DEBUG_LOG=''
# An isolated zoxide database prevents real directory names entering the demo.
export _ZO_DATA_DIR="$ZJ_DEMO_DIR/zoxide"
mkdir -p "$_ZO_DATA_DIR"
cat > "$ZJ_DEMO_DIR/history" <<'EOF'
: 1700000001:0;echo "frontend tests passed"
: 1700000002:0;echo "backend tests passed"
: 1700000003:0;echo "all demo tests passed"
EOF
cat > "$ZJ_DEMO_DIR/setup.zsh" <<'EOF'
cd "$ZJ_DEMO_DIR/workspace"
HISTFILE="$ZJ_DEMO_DIR/history"
HISTSIZE=100
SAVEHIST=0
PROMPT='%F{cyan}demo%f %F{magenta}❯%f '
bindkey -e
JEV_SHOW_SCORE=1
source "$ZJ_PLUGIN_ROOT/zsh/jev-shell-history.plugin.zsh"
clear
print -P '%F{cyan}zj — describe it, review it, press Enter%f'
print 'Demo workspace: payments/java-payments + storefront/react-storefront'
print
EOF
cd "$root"
vhs demo/demo.tape
