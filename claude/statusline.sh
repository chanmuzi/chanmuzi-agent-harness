#!/bin/bash
# Custom Claude Code Statusline - ■□ Square Style
# Based on: https://amagrammer91.tistory.com/275

input=$(cat)

# Safe jq extraction
jv() { echo "$input" | jq -r "$1" 2>/dev/null; }

# Parse fields
model=$(jv '.model.display_name // "?"')
cwd=$(jv '.workspace.current_dir // .cwd // empty')
used=$(jv '.context_window.used_percentage // empty')
cost=$(jv '.cost.total_cost_usd // empty')
version=$(jv '.version // "?"')
duration_ms=$(jv '.cost.total_duration_ms // empty')

# Defaults for null/empty
: "${cwd:=$HOME}"
: "${used:=0}"
: "${cost:=0}"
: "${duration_ms:=0}"

# Ensure numeric
used=${used%.*}
[[ "$used" =~ ^[0-9]+$ ]] || used=0
[[ "$duration_ms" =~ ^[0-9]+$ ]] || duration_ms=0

# Shorten cwd (keep last 2 dirs)
short_cwd="${cwd/#$HOME/~}"
IFS='/' read -ra parts <<< "$short_cwd"
n=${#parts[@]}
if (( n > 3 )); then
  short_cwd="…/${parts[$((n-2))]}/${parts[$((n-1))]}"
fi

# Git info
git_str=""
if cd "$cwd" 2>/dev/null && git rev-parse --is-inside-work-tree &>/dev/null; then
  branch=$(git branch --show-current 2>/dev/null)
  [[ -z "$branch" ]] && branch="(detached)"
  staged=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
  unstaged=$(git diff --name-only 2>/dev/null | wc -l | tr -d ' ')
  untracked=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
  git_str=" 🌿 ${branch} +${staged} ~${unstaged} ?${untracked}"
fi

# ■□ Square progress bar (filled = used)
circle_bar() {
  local pct=${1:-0} width=${2:-10}
  local filled=$(( pct * width / 100 ))
  (( filled > width )) && filled=$width
  (( filled < 0 )) && filled=0
  local empty=$(( width - filled ))
  local bar=""
  for ((i=0; i<filled; i++)); do bar+="■"; done
  for ((i=0; i<empty; i++)); do bar+="□"; done
  echo "$bar"
}

# Format cost
cost_str=$(awk "BEGIN{printf \"\$%.2f\", $cost + 0}")

# Format duration (ms → Xd Xh Xm Xs)
fmt_dur() {
  local ms=${1:-0}
  local total_sec=$(( ms / 1000 ))
  local d=$(( total_sec / 86400 ))
  local h=$(( total_sec % 86400 / 3600 ))
  local m=$(( total_sec % 3600 / 60 ))
  local s=$(( total_sec % 60 ))
  if (( d > 0 )); then
    echo "${d}d ${h}h ${m}m"
  elif (( h > 0 )); then
    echo "${h}h ${m}m ${s}s"
  elif (( m > 0 )); then
    echo "${m}m ${s}s"
  else
    echo "${s}s"
  fi
}

bar=$(circle_bar "$used" 10)
dur_str=$(fmt_dur "$duration_ms")

# === Output (3 lines, no color — clean terminal style) ===
echo "📁 ${short_cwd}${git_str} 🤖 ${model} 📟 v${version}"
echo "🧠 ${used}% ${bar} ⏱ ${dur_str} 💰 ${cost_str}"
