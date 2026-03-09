#!/bin/sh
input=$(cat)
echo "$input" > /tmp/statusline-debug.json

# === Data extraction ===
model=$(echo "$input" | jq -r '.model.display_name // "Claude"')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
session_name=$(echo "$input" | jq -r '.session_name // empty')

ctx_size=$(echo "$input" | jq -r '.context_window.context_window_size // 0')
cur_input=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
cur_cache_create=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
cur_cache_read=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
cur_output=$(echo "$input" | jq -r '.context_window.current_usage.output_tokens // 0')
total_input=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
total_output=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')

# usage_limits is not provided by Claude Code's statusLine API; these will always be empty.
sess_used=$(echo "$input" | jq -r '.usage_limits.session.used // empty')
sess_limit=$(echo "$input" | jq -r '.usage_limits.session.limit // empty')
sess_reset_at=$(echo "$input" | jq -r '.usage_limits.session.reset_at // empty')
week_used=$(echo "$input" | jq -r '.usage_limits.weekly.used // empty')
week_limit=$(echo "$input" | jq -r '.usage_limits.weekly.limit // empty')
week_reset_at=$(echo "$input" | jq -r '.usage_limits.weekly.reset_at // empty')

# === Icons (Nerd Font) ===
ICO_DIR=""
ICO_MODEL=""
ICO_PATH=""
ICO_CTX=""
ICO_IN=""
ICO_CR=""
ICO_CW=""
ICO_OUT=""
ICO_TOTAL="∑"
ICO_COST=""
ICO_SESSION=""
ICO_WEEKLY=""
ICO_GIT=""

# === Segment background colors (256-color) ===
BG_DIR=167      # salmon-red
BG_MODEL=61     # slate blue / purple
BG_PATH=24      # steel teal
BG_CTX=235      # near-black
BG_TOK=234      # very dark
BG_TOTAL=238    # dark gray
BG_COST=136     # dark amber/gold

SEP=""  # U+E0B0 powerline arrow

# === Powerline renderer ===
# Args: alternating  bg_num "content"  pairs.
# Content must use ONLY \033[38;5;Xm fg changes — no \033[0m resets (they kill the bg).
render_pl_line() {
  prev_bg=""
  out=""
  while [ $# -ge 2 ]; do
    bg="$1"; content="$2"; shift 2
    [ -n "$prev_bg" ] && out="${out}\033[48;5;${bg}m\033[38;5;${prev_bg}m${SEP}"
    out="${out}\033[48;5;${bg}m\033[38;5;255m ${content} "
    prev_bg="$bg"
  done
  [ -n "$prev_bg" ] && out="${out}\033[0m\033[38;5;${prev_bg}m${SEP}\033[0m"
  printf '%b\n' "$out"
}

# === Segment content builders ===
# Note: use \033[38;5;Xm for color changes; \033[1m/\033[22m for bold are safe (don't reset bg)

# -- Dir --
short_cwd=$(echo "$cwd" | sed "s|^$HOME|~|")
basename_cwd=$(basename "$cwd")
git_branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
git_part=""
if [ -n "$git_branch" ]; then
  git_dirty=$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)
  if [ -n "$git_dirty" ]; then
    git_part=" \033[38;5;250m${ICO_GIT}(\033[38;5;117m${git_branch}\033[38;5;250m)\033[38;5;215m ✗"
  else
    git_part=" \033[38;5;250m${ICO_GIT}(\033[38;5;117m${git_branch}\033[38;5;250m)"
  fi
fi
dir_content="${ICO_DIR} \033[1m${basename_cwd}\033[22m${git_part}"

# -- Model --
sess_part=""
[ -n "$session_name" ] && sess_part=" \033[38;5;250m[${session_name}]"
model_content="${ICO_MODEL} ${model}${sess_part}"

# -- Path --
path_content="${ICO_PATH} ${short_cwd}"

# -- Ctx bar --
BAR_WIDTH=20
used_tokens=$((cur_input + cur_cache_create + cur_cache_read))
if [ "$ctx_size" -gt 0 ] && [ "$used_tokens" -gt 0 ]; then
  used_pct=$(awk "BEGIN {printf \"%.1f\", $used_tokens * 100 / $ctx_size}")
  used_int=$(awk "BEGIN {printf \"%d\",  $used_tokens * 100 / $ctx_size}")
  if [ "$used_int" -ge 80 ]; then bar_n=203; pct_n=203
  elif [ "$used_int" -ge 50 ]; then bar_n=215; pct_n=215
  else bar_n=114; pct_n=157; fi
  filled=$(awk "BEGIN {n=int($used_int*$BAR_WIDTH/100); if(n>$BAR_WIDTH) n=$BAR_WIDTH; print n}")
  empty=$((BAR_WIDTH - filled))
  bar=""; i=0
  while [ "$i" -lt "$filled" ]; do bar="${bar}█"; i=$((i+1)); done
  j=0
  while [ "$j" -lt "$empty" ]; do bar="${bar}░"; j=$((j+1)); done
  used_k=$(awk "BEGIN {printf \"%.1f\", $used_tokens/1000}")
  ctx_max_k=$(awk "BEGIN {printf \"%.0f\", $ctx_size/1000}")
  ctx_content="${ICO_CTX} \033[38;5;245m[\033[38;5;${bar_n}m${bar}\033[38;5;245m] \033[38;5;${pct_n}m${used_pct}%\033[38;5;242m ${used_k}k/${ctx_max_k}k"
else
  bar=""; i=0
  while [ "$i" -lt "$BAR_WIDTH" ]; do bar="${bar}░"; i=$((i+1)); done
  ctx_content="${ICO_CTX} \033[38;5;245m[${bar}]\033[38;5;242m --%"
fi

# -- Token detail --
tok_content=""
if [ "$used_tokens" -gt 0 ]; then
  # Format helper: show full number if < 100, otherwise show in k
  if [ "$cur_input" -lt 100 ]; then in_fmt="${cur_input}"; else in_fmt="$(awk "BEGIN {printf \"%.1f\", $cur_input/1000}")k"; fi
  if [ "$cur_cache_read" -lt 100 ]; then cr_fmt="${cur_cache_read}"; else cr_fmt="$(awk "BEGIN {printf \"%.1f\", $cur_cache_read/1000}")k"; fi
  if [ "$cur_cache_create" -lt 100 ]; then cw_fmt="${cur_cache_create}"; else cw_fmt="$(awk "BEGIN {printf \"%.1f\", $cur_cache_create/1000}")k"; fi
  if [ "$cur_output" -lt 100 ]; then out_fmt="${cur_output}"; else out_fmt="$(awk "BEGIN {printf \"%.1f\", $cur_output/1000}")k"; fi
  tok_content="\033[38;5;242m${ICO_IN} in:\033[38;5;111m${in_fmt} \033[38;5;242m${ICO_CR} cr:\033[38;5;114m${cr_fmt} \033[38;5;242m${ICO_CW} cw:\033[38;5;221m${cw_fmt} \033[38;5;242m${ICO_OUT} out:\033[38;5;218m${out_fmt}"
fi

# -- Session total --
total_tokens=$((total_input + total_output))
total_content=""
if [ "$total_tokens" -gt 0 ]; then
  total_k=$(awk "BEGIN {printf \"%.1f\", $total_tokens/1000}")
  total_content="${ICO_TOTAL} ${total_k}k"
fi

# -- Cost --
cost_content=""
if [ -n "$cost" ] && [ "$cost" != "0" ]; then
  cost_fmt=$(awk "BEGIN {printf \"%.4f\", $cost}")
  cost_content="${ICO_COST} \$${cost_fmt}"
fi

# === Line 1 ===
set --
set -- "$@" "$BG_DIR"   "$dir_content"
set -- "$@" "$BG_MODEL" "$model_content"
set -- "$@" "$BG_PATH"  "$path_content"
set -- "$@" "$BG_CTX"   "$ctx_content"
render_pl_line "$@"

# === Line 2: token detail + total + cost ===
line2=""
[ -n "$tok_content"   ] && line2="${line2} ${tok_content}\033[0m"
[ -n "$total_content" ] && line2="${line2}  \033[38;5;80m${total_content}\033[0m"
[ -n "$cost_content"  ] && line2="${line2}   \033[38;5;136m${cost_content}\033[0m"
[ -n "$line2" ] && printf '%b\n' "$line2"

# === Reset timer helper ===
format_reset_in() {
  reset_at="$1"; [ -z "$reset_at" ] && return

  # Parse ISO 8601 timestamp with timezone offset (e.g., 2026-03-09T09:00:00.664207+00:00)
  # Strip fractional seconds and convert +00:00 to Z
  clean_date=$(echo "$reset_at" | sed 's/\.[0-9]*+00:00$/Z/' | sed 's/+00:00$/Z/')

  # Try macOS date first (with -u flag to interpret as UTC)
  reset_epoch=$(date -ju -f "%Y-%m-%dT%H:%M:%SZ" "$clean_date" "+%s" 2>/dev/null)

  # Fallback to Python for reliable parsing
  if [ -z "$reset_epoch" ]; then
    reset_epoch=$(python3 -c "from datetime import datetime; import sys; print(int(datetime.fromisoformat('$reset_at').timestamp()))" 2>/dev/null)
  fi

  [ -z "$reset_epoch" ] && { echo "soon"; return; }

  now_epoch=$(date "+%s")
  diff=$((reset_epoch - now_epoch))

  if [ "$diff" -le 0 ]; then
    echo "now"
  else
    h=$((diff / 3600))
    m=$(( (diff % 3600) / 60 ))
    d=$((h / 24))
    h_rem=$((h % 24))

    if [ "$d" -gt 0 ]; then
      echo "${d}d ${h_rem}h"
    elif [ "$h" -gt 0 ]; then
      echo "${h}h ${m}m"
    else
      echo "${m}m"
    fi
  fi
}

# === API Usage Helper ===
get_api_usage() {
  CACHE_FILE="$HOME/.cache/ccstatusline-api-usage.json"
  LOCK_FILE="$HOME/.cache/ccstatusline-api-usage.lock"
  CACHE_TTL=180  # 3 minutes
  RATE_LIMIT=30  # 30 seconds between API calls

  # Check if cache file exists and is fresh
  if [ -f "$CACHE_FILE" ]; then
    cache_age=$(($(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0)))
    if [ "$cache_age" -lt "$CACHE_TTL" ]; then
      cat "$CACHE_FILE"
      return 0
    fi
  fi

  # Rate limiting: check lock file
  if [ -f "$LOCK_FILE" ]; then
    lock_age=$(($(date +%s) - $(stat -f %m "$LOCK_FILE" 2>/dev/null || echo 0)))
    if [ "$lock_age" -lt "$RATE_LIMIT" ]; then
      # Return stale cache or empty if rate limited
      [ -f "$CACHE_FILE" ] && cat "$CACHE_FILE"
      return 0
    fi
  fi

  # Extract OAuth token
  TOKEN=""
  if [ "$(uname)" = "Darwin" ]; then
    # macOS: try Keychain first
    TOKEN=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null | grep -o '"claudeAiOauth":{"accessToken":"[^"]*"' | sed 's/.*"accessToken":"\([^"]*\)".*/\1/' || echo "")
  fi
  if [ -z "$TOKEN" ] && [ -f "$HOME/.claude/.credentials.json" ]; then
    # Fallback: read from credentials file
    TOKEN=$(jq -r '.claudeAiOauth.accessToken // empty' "$HOME/.claude/.credentials.json" 2>/dev/null)
  fi

  if [ -z "$TOKEN" ]; then
    # No token available
    return 1
  fi

  # Create lock file
  mkdir -p "$(dirname "$LOCK_FILE")"
  touch "$LOCK_FILE"

  # Call API
  response=$(curl -s -m 5 \
    -H "Authorization: Bearer $TOKEN" \
    -H "anthropic-beta: oauth-2025-04-20" \
    "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)

  if [ $? -eq 0 ] && [ -n "$response" ]; then
    # Cache successful response
    mkdir -p "$(dirname "$CACHE_FILE")"
    echo "$response" > "$CACHE_FILE"
    echo "$response"
    return 0
  else
    # Return stale cache on API failure
    [ -f "$CACHE_FILE" ] && cat "$CACHE_FILE"
    return 1
  fi
}

# === Progress Bar Helper ===
make_progress_bar() {
  pct="$1"
  width="${2:-15}"
  filled=$(awk "BEGIN {n=int($pct*$width/100); if(n>$width) n=$width; if(n<0) n=0; print n}")
  empty=$((width - filled))
  bar=""; i=0
  while [ "$i" -lt "$filled" ]; do bar="${bar}█"; i=$((i+1)); done
  j=0
  while [ "$j" -lt "$empty" ]; do bar="${bar}░"; j=$((j+1)); done
  echo "$bar"
}

# === Line 3: session/weekly usage from Anthropic API ===
api_usage=$(get_api_usage)
api_sess_pct=""
api_sess_reset=""
api_week_pct=""
api_week_reset=""

if [ -n "$api_usage" ]; then
  api_sess_pct=$(echo "$api_usage" | jq -r '.five_hour.utilization // empty' 2>/dev/null)
  api_sess_reset=$(echo "$api_usage" | jq -r '.five_hour.resets_at // empty' 2>/dev/null)
  api_week_pct=$(echo "$api_usage" | jq -r '.seven_day.utilization // empty' 2>/dev/null)
  api_week_reset=$(echo "$api_usage" | jq -r '.seven_day.resets_at // empty' 2>/dev/null)
fi

if [ -n "$api_sess_pct" ] || [ -n "$api_week_pct" ]; then
  # Display session and weekly usage with progress bars
  line3=""

  if [ -n "$api_sess_pct" ]; then
    sess_int=$(printf '%.0f' "$api_sess_pct")
    if [ "$sess_int" -ge 80 ]; then sess_c=203; elif [ "$sess_int" -ge 50 ]; then sess_c=215; else sess_c=114; fi
    sess_bar=$(make_progress_bar "$api_sess_pct" 15)
    sess_reset_str=$(format_reset_in "$api_sess_reset")
    line3="${line3} \033[38;5;250m${ICO_SESSION} Session: \033[38;5;245m[\033[38;5;${sess_c}m${sess_bar}\033[38;5;245m] \033[38;5;${sess_c}m${api_sess_pct}%"
    [ -n "$sess_reset_str" ] && line3="${line3} \033[38;5;242m↻${sess_reset_str}"
    line3="${line3}\033[0m"
  fi

  if [ -n "$api_week_pct" ]; then
    week_int=$(printf '%.0f' "$api_week_pct")
    if [ "$week_int" -ge 80 ]; then week_c=203; elif [ "$week_int" -ge 50 ]; then week_c=215; else week_c=114; fi
    week_bar=$(make_progress_bar "$api_week_pct" 15)
    week_reset_str=$(format_reset_in "$api_week_reset")
    line3="${line3}  \033[38;5;250m${ICO_WEEKLY} Weekly: \033[38;5;245m[\033[38;5;${week_c}m${week_bar}\033[38;5;245m] \033[38;5;${week_c}m${api_week_pct}%"
    [ -n "$week_reset_str" ] && line3="${line3} \033[38;5;242m↻${week_reset_str}"
    line3="${line3}\033[0m"
  fi

  [ -n "$line3" ] && printf '%b\n' "$line3"
else
  # Fallback: API data not available — show session context % and cost instead
  used_pct_val=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
  remaining_pct_val=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')
  fallback_line3=""
  if [ -n "$used_pct_val" ] && [ -n "$remaining_pct_val" ]; then
    used_int3=$(printf '%.0f' "$used_pct_val")
    if [ "$used_int3" -ge 80 ]; then ctx3_c=203; elif [ "$used_int3" -ge 50 ]; then ctx3_c=215; else ctx3_c=114; fi
    fallback_line3="${fallback_line3} \033[38;5;245mctx: \033[38;5;${ctx3_c}m${used_pct_val}% used\033[38;5;245m / ${remaining_pct_val}% left\033[0m"
  fi
  if [ -n "$cost" ] && [ "$cost" != "0" ]; then
    cost_fmt3=$(awk "BEGIN {printf \"%.4f\", $cost}")
    fallback_line3="${fallback_line3}   \033[38;5;136m${ICO_COST} session cost: \$${cost_fmt3}\033[0m"
  fi
  [ -n "$fallback_line3" ] && printf '%b\n' "$fallback_line3"
fi
