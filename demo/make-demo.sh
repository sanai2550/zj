#!/usr/bin/env zsh
# Records demo/demo.mp4 and demo/demo.gif.
#
# Everything shown is fabricated: a throwaway git repo and a made-up history
# file under /tmp/jev-demo. Your real ~/.zsh_history is never read.
#
# Needs: vhs, ffmpeg, and TYPESAFE_API_KEY in the environment (inherited by the
# recorded shell; it never appears on screen).
set -euo pipefail

root=${0:A:h:h}
demo=/tmp/jev-demo

[[ -n ${TYPESAFE_API_KEY:-} ]] || { print -u2 "TYPESAFE_API_KEY is not set"; exit 2 }

# --- fabricated environment -------------------------------------------------
rm -rf $demo && mkdir -p $demo/project/src
(
  cd $demo/project
  git init -q
  printf '# demo\n\nA tiny demo project.\n' > README.md
  printf 'export function add(a, b) {\n  // TODO: validate inputs\n  return a + b;\n}\n' > src/index.js
  git add .
  git -c user.name=demo -c user.email=demo@example.com commit -qm "initial commit"
)

local -a fake_history=(
  'brew upgrade'
  'ssh staging-web-01'
  'vim README.md'
  'docker compose up -d'
  'docker compose logs -f api'
  'kubectl get pods -n staging'
  'git stash list'
  'python3 -m http.server 8080'
  'curl -s localhost:3000/health | jq .'
  'make lint'
  'npm run build'
  'cargo test --workspace'
  'tail -f /var/log/nginx/error.log'
  'git log --oneline -5'
  'rg TODO src/'
  'npm test'
  'ls -la'
  'git status'
)
: > $demo/history
local i=0
for cmd in $fake_history; do
  i=$(( i + 1 ))
  printf ': %d:0;%s\n' $(( 1700000000 + i * 60 )) "$cmd" >> $demo/history
done

cat > $demo/setup.zsh <<EOF
cd $demo/project
HISTFILE=$demo/history
PROMPT='%F{blue}demo%f %F{magenta}❯%f '
bindkey -e
bindkey '^E' end-of-line
JEV_SHOW_SCORE=1
source $root/zsh/jev-shell-history.plugin.zsh
EOF

# --- record -------------------------------------------------------------------
cd $root
rm -rf demo/frames
vhs demo/demo.tape

# --- assemble (vhs 0.12.0 does not render its outputs, see vhs#787) ------------
# vhs captures 50 fps as separate text and cursor layers. Padding is added here
# The terminal canvas is centred on a fixed 16:9 1280x720 background (Catppuccin
# Mocha base, matching the tape's theme), an aspect ratio X/Twitter is happy with.
local pad='pad=1280:720:(ow-iw)/2:(oh-ih)/2:color=0x1e1e2e'
local -a inputs=(-y -r 50 -start_number 1 -i demo/frames/frame-text-%05d.png
                 -r 50 -start_number 1 -i demo/frames/frame-cursor-%05d.png)
ffmpeg -loglevel error $inputs \
  -filter_complex "[0][1]overlay,$pad,scale=trunc(iw/2)*2:trunc(ih/2)*2" \
  -vcodec libx264 -pix_fmt yuv420p -crf 20 -an demo/demo.mp4
ffmpeg -loglevel error $inputs \
  -filter_complex "[0][1]overlay,$pad,fps=20,scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer" \
  demo/demo.gif

rm -rf demo/frames
ls -la demo/demo.mp4 demo/demo.gif
