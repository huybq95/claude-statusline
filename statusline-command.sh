#!/bin/sh
input=$(cat)
echo "$input" > /tmp/statusline-debug.json

# === Data extraction ===
model=$(echo "$input" | jq -r '.model.display_name // "Claude"')
model_id=$(echo "$input" | jq -r '.model.id // ""')
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
BG_DIFF=238     # dark gray — diff stat segment, distinct from branch
# BG_MODEL is chosen dynamically based on model name (see below)
BG_PATH=24      # steel teal
BG_CTX=235      # near-black
BG_TOK=234      # very dark
BG_TOTAL=238    # dark gray
BG_COST=136     # dark amber/gold

# Dynamic model segment color based on model name
model_id_lower=$(echo "$model_id" | tr '[:upper:]' '[:lower:]')
case "$model_id_lower" in
  *opus*)   BG_MODEL=99  ;;  # violet / purple
  *sonnet*) BG_MODEL=172 ;;  # warm amber / orange
  *haiku*)  BG_MODEL=74  ;;  # sky blue
  *)        BG_MODEL=240 ;;  # neutral grey
esac

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
dir_label=""
git_dirty_mark=""
if [ -n "$git_branch" ]; then
  git_dirty=$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)
  if [ -n "$git_dirty" ]; then
    git_dirty_mark=" \033[38;5;215m✗"
  fi
  diff_label=""
  git_diff_stat=$(git -C "$cwd" --no-optional-locks diff HEAD --shortstat 2>/dev/null)
  if [ -n "$git_diff_stat" ]; then
    diff_ins=$(echo "$git_diff_stat" | grep -o '[0-9]* insertion' | grep -o '[0-9]*')
    diff_del=$(echo "$git_diff_stat" | grep -o '[0-9]* deletion' | grep -o '[0-9]*')
    [ -n "$diff_ins" ] && diff_label="${diff_label} \033[38;5;114m+${diff_ins}"
    [ -n "$diff_del" ] && diff_label="${diff_label} \033[38;5;203m-${diff_del}"
  fi
  dir_label="\033[1m${git_branch}\033[22m${git_dirty_mark}"
else
  dir_label="\033[1m${basename_cwd}\033[22m"
fi
dir_content="${ICO_DIR} ${dir_label}"

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
# Format a token count: show raw integer if < 100, else show Xk
fmt_tok() {
  awk "BEGIN {n=$1; if(n<100) printf \"%d\", n; else printf \"%.1fk\", n/1000}"
}
tok_content=""
if [ "$used_tokens" -gt 0 ]; then
  in_fmt=$(fmt_tok "$cur_input")
  cr_fmt=$(fmt_tok "$cur_cache_read")
  cw_fmt=$(fmt_tok "$cur_cache_create")
  out_fmt=$(fmt_tok "$cur_output")
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
  CACHE_TTL=300  # 5 minutes
  RATE_LIMIT=60  # 60 seconds between API calls

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
      # Return stale cache or fail if rate limited
      if [ -f "$CACHE_FILE" ]; then cat "$CACHE_FILE"; return 0; fi
      return 1
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
    # Check for API error in response body
    if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
      # API returned an error — do not cache, return stale cache or fail
      [ -f "$CACHE_FILE" ] && cat "$CACHE_FILE" && return 0
      return 1
    fi
    # Cache successful response
    mkdir -p "$(dirname "$CACHE_FILE")"
    echo "$response" > "$CACHE_FILE"
    echo "$response"
    return 0
  else
    # curl failed — return stale cache or fail
    [ -f "$CACHE_FILE" ] && cat "$CACHE_FILE" && return 0
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

# === Line 1 ===
set --
set -- "$@" "$BG_MODEL" "$model_content"
set -- "$@" "$BG_PATH"  "$path_content"
set -- "$@" "$BG_DIR"   "$dir_content"
[ -n "$diff_label" ] && set -- "$@" "$BG_DIFF" "${diff_label# }"
set -- "$@" "$BG_CTX"   "$ctx_content"
render_pl_line "$@"

# === Line 2: token detail + total + cost ===
line2=""
[ -n "$tok_content"   ] && line2="${line2} ${tok_content}\033[0m"
[ -n "$total_content" ] && line2="${line2}  \033[38;5;80m${total_content}\033[0m"
[ -n "$cost_content"  ] && line2="${line2}   \033[38;5;136m${cost_content}\033[0m"
[ -n "$line2" ] && printf '%b\n' "$line2"

# === Promotion x2 checker (March 13–27 2026, off-peak ET) ===
# ET = EDT (UTC-4) since clocks spring forward Mar 8 2026.
# Peak hours: Mon–Fri 8AM–2PM ET = 12:00–18:00 UTC.
promo_label=""
now_epoch=$(date +%s)
# Convert current epoch to ET (UTC-4)
et_epoch=$((now_epoch - 4*3600))
et_hour=$(date -u -r "$et_epoch" "+%H" 2>/dev/null || date -u -d "@$et_epoch" "+%H" 2>/dev/null)
et_dow=$(date  -u -r "$et_epoch" "+%u" 2>/dev/null || date -u -d "@$et_epoch" "+%u" 2>/dev/null)
# Date bounds: promo runs 2026-03-13 00:00 ET to 2026-03-27 23:59 ET
promo_start=$(date -u -j -f "%Y-%m-%d %H:%M:%S" "2026-03-13 00:00:00" "+%s" 2>/dev/null || date -u -d "2026-03-13T00:00:00-04:00" "+%s" 2>/dev/null)
promo_end=$(date   -u -j -f "%Y-%m-%d %H:%M:%S" "2026-03-27 23:59:59" "+%s" 2>/dev/null || date -u -d "2026-03-27T23:59:59-04:00" "+%s" 2>/dev/null)
promo_in_date=0
if [ -n "$promo_start" ] && [ -n "$promo_end" ]; then
  if [ "$now_epoch" -ge "$promo_start" ] && [ "$now_epoch" -le "$promo_end" ]; then
    promo_in_date=1
  fi
fi
if [ "$promo_in_date" -eq 1 ] && [ -n "$et_hour" ] && [ -n "$et_dow" ]; then
  # Weekday = 1..5, peak = 08:00..13:59 ET (hours 8–13 inclusive)
  is_weekday=0; is_peak=0
  [ "$et_dow" -ge 1 ] && [ "$et_dow" -le 5 ] && is_weekday=1
  [ "$et_hour" -ge 8 ] && [ "$et_hour" -lt 14 ] && is_peak=1

  # Helper: given a UTC epoch, convert to local HH:MM
  # Uses `date` without -u so it applies the local timezone.
  utc_to_local_hhmm() {
    epoch="$1"
    date -r "$epoch" "+%H:%M" 2>/dev/null || date -d "@$epoch" "+%H:%M" 2>/dev/null
  }

  if [ "$is_weekday" -eq 1 ] && [ "$is_peak" -eq 1 ]; then
    # Currently peak — x2 is OFF.
    # x2 resumes when peak ends: 2PM ET = 18:00 UTC today.
    # Compute epoch for 18:00 UTC today.
    today_utc_date=$(date -u -r "$now_epoch" "+%Y-%m-%d" 2>/dev/null || date -u -d "@$now_epoch" "+%Y-%m-%d" 2>/dev/null)
    resume_utc_epoch=$(date -u -j -f "%Y-%m-%d %H:%M:%S" "${today_utc_date} 18:00:00" "+%s" 2>/dev/null || date -u -d "${today_utc_date}T18:00:00Z" "+%s" 2>/dev/null)
    resume_local=$(utc_to_local_hhmm "$resume_utc_epoch")
    if [ -n "$resume_local" ]; then
      promo_label=" \033[38;5;214mx2 resumes at ${resume_local}\033[0m"
    else
      promo_label=" \033[38;5;214mx2 promo: OFF (peak hrs)\033[0m"
    fi
  else
    # Currently off-peak — x2 is ACTIVE.
    # x2 ends when peak starts: 8AM ET = 12:00 UTC.
    # If it's already past 18:00 UTC today (i.e., after peak) → next peak is tomorrow at 12:00 UTC.
    # If it's before 12:00 UTC today → peak starts at 12:00 UTC today.
    # Weekend: next peak is the coming Monday 12:00 UTC.
    today_utc_date=$(date -u -r "$now_epoch" "+%Y-%m-%d" 2>/dev/null || date -u -d "@$now_epoch" "+%Y-%m-%d" 2>/dev/null)
    today_peak_start_epoch=$(date -u -j -f "%Y-%m-%d %H:%M:%S" "${today_utc_date} 12:00:00" "+%s" 2>/dev/null || date -u -d "${today_utc_date}T12:00:00Z" "+%s" 2>/dev/null)
    # Determine next peak start UTC epoch
    next_peak_epoch=""
    if [ "$is_weekday" -eq 1 ]; then
      # Weekday but off-peak: either before 12:00 UTC (pre-peak) or after 18:00 UTC (post-peak)
      if [ "$now_epoch" -lt "$today_peak_start_epoch" ]; then
        # Before peak today → peak starts today at 12:00 UTC
        next_peak_epoch="$today_peak_start_epoch"
      else
        # After peak today → next peak is tomorrow (or Monday if Friday)
        # et_dow: 1=Mon … 5=Fri. If Friday (5), next peak is Monday (+3 days).
        days_ahead=1
        [ "$et_dow" -eq 5 ] && days_ahead=3
        next_peak_epoch=$((today_peak_start_epoch + days_ahead * 86400))
      fi
    else
      # Weekend: find next Monday 12:00 UTC
      # et_dow: 6=Sat → 2 days, 7=Sun → 1 day
      if [ "$et_dow" -eq 6 ]; then days_ahead=2; else days_ahead=1; fi
      next_peak_epoch=$((today_peak_start_epoch + days_ahead * 86400))
    fi
    until_local=$(utc_to_local_hhmm "$next_peak_epoch")
    if [ -n "$until_local" ]; then
      promo_label=" \033[38;5;82m x2 ACTIVE until ${until_local}\033[0m"
    else
      promo_label=" \033[38;5;82m x2 ACTIVE now!\033[38;5;242m (off-peak)\033[0m"
    fi
  fi
fi

# === Terminal width detection ===
# Script runs with stdin/stdout as pipes (not a tty), so tput cols and $COLUMNS
# may return stale values after a SIGWINCH resize event.
# Fix: query the live terminal size via /dev/tty using `stty size`, which issues
# a TIOCGWINSZ ioctl directly against the controlling terminal regardless of
# whether this process's stdio is a tty.
term_width=$(stty size </dev/tty 2>/dev/null | awk '{print $2}')
# Fallback chain: tput against /dev/tty, then plain tput, then $COLUMNS, then 0
if [ -z "$term_width" ] || [ "$term_width" -eq 0 ] 2>/dev/null; then
  term_width=$(TERM="${TERM:-xterm-256color}" tput cols </dev/tty 2>/dev/null \
               || tput cols 2>/dev/null \
               || echo "${COLUMNS:-0}")
fi
# Threshold below which compact mode is used for line 3.
COMPACT_WIDTH=100

# === Line 3: session/weekly usage from Anthropic API ===
api_usage=$(get_api_usage); api_exit=$?
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
  line3=""

  if [ "$term_width" -gt 0 ] && [ "$term_width" -lt "$COMPACT_WIDTH" ]; then
    # --- Compact mode: no progress bars, abbreviated labels ---
    if [ -n "$api_sess_pct" ]; then
      sess_int=$(printf '%.0f' "$api_sess_pct")
      if [ "$sess_int" -ge 80 ]; then sess_c=203; elif [ "$sess_int" -ge 50 ]; then sess_c=215; else sess_c=114; fi
      sess_reset_str=$(format_reset_in "$api_sess_reset")
      line3="${line3} \033[38;5;250m${ICO_SESSION}5h:\033[38;5;${sess_c}m${api_sess_pct}%"
      [ -n "$sess_reset_str" ] && line3="${line3}\033[38;5;242m↻${sess_reset_str}"
      line3="${line3}\033[0m"
    fi

    if [ -n "$api_week_pct" ]; then
      week_int=$(printf '%.0f' "$api_week_pct")
      if [ "$week_int" -ge 80 ]; then week_c=203; elif [ "$week_int" -ge 50 ]; then week_c=215; else week_c=114; fi
      week_reset_str=$(format_reset_in "$api_week_reset")
      line3="${line3}  \033[38;5;250m${ICO_WEEKLY}7d:\033[38;5;${week_c}m${api_week_pct}%"
      [ -n "$week_reset_str" ] && line3="${line3}\033[38;5;242m↻${week_reset_str}"
      line3="${line3}\033[0m"
    fi

    [ -n "$promo_label" ] && line3="${line3}  ${promo_label}"
  else
    # --- Full mode: progress bars + labels ---
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

    [ -n "$promo_label" ] && line3="${line3}  ${promo_label}"
  fi

  [ -n "$line3" ] && printf '%b\n' "$line3"
elif [ "$api_exit" -ne 0 ]; then
  # API call failed — show error indicator
  line3_err=" \033[38;5;203m[!] usage data unavailable\033[0m"
  [ -n "$promo_label" ] && line3_err="${line3_err}  ${promo_label}"
  printf '%b\n' "$line3_err"
fi

# Show promo label even if no API usage data at all
if [ -z "$api_sess_pct" ] && [ -z "$api_week_pct" ] && [ "$api_exit" -eq 0 ] && [ -n "$promo_label" ]; then
  printf '%b\n' "${promo_label}"
fi
