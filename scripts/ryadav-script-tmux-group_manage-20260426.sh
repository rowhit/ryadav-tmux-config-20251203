#!/usr/bin/env bash
# * file: ~/.tmux/scripts/ryadav-script-tmux-group_manage-20260426.sh
# ##############################################################################
# ** notes
# ******************************************************************************
# Manage tmux session groups stored as JSONL at ~/.tmux/db/groups.jsonl.
# Each line is one of:
#   {"group":"<name>"}                            -> empty-group marker
#   {"group":"<name>","session":"<session>"}     -> session belongs to group
#
# Subcommands:
#   add-group <group>              create an empty group
#   rm-group  <group>              delete a group and all its session entries
#   add       <group> <session>    add a session to a group (creates if new)
#   rm        <group> <session>    remove a session from a group
#   list-groups                    print all groups
#   list-sessions <group>          print sessions in a group
#   list                           print every group with its sessions
#   switch                         two-stage fzf popup: pick group, then session

# ******************************************************************************
# ** main
# ******************************************************************************
set -euo pipefail

DB_DIR="${HOME}/.tmux/db"
DB_FILE="${DB_DIR}/groups.jsonl"
SELF="$0"

# *** ensure db file exists
ensure_db() {
  mkdir -p "$DB_DIR"
  [[ -f "$DB_FILE" ]] || : > "$DB_FILE"
}

# *** restrict names to chars that are JSON- and regex-safe
valid_name() {
  [[ "$1" =~ ^[A-Za-z0-9_.-]+$ ]]
}

require_name() {
  local kind="$1" name="$2"
  if ! valid_name "$name"; then
    echo "invalid $kind name: '$name' (allowed: A-Z a-z 0-9 _ . -)" >&2
    exit 1
  fi
}

usage() {
  cat <<EOF
Usage:
  $SELF add-group <group>
  $SELF rm-group  <group>
  $SELF add       <group> <session>
  $SELF rm        <group> <session>
  $SELF list-groups
  $SELF list-sessions <group>
  $SELF list
  $SELF switch

Database: $DB_FILE
EOF
}

# *** group exists if any line references it (marker or pair)
group_exists() {
  local group="$1"
  grep -qE "\"group\":\"$group\"[,}]" "$DB_FILE" 2>/dev/null
}

cmd_add_group() {
  local group="$1"
  require_name group "$group"
  if group_exists "$group"; then
    echo "group already exists: $group" >&2
    return 0
  fi
  printf '{"group":"%s"}\n' "$group" >> "$DB_FILE"
}

cmd_rm_group() {
  local group="$1"
  require_name group "$group"
  local tmp
  tmp="$(mktemp)"
  grep -vE "\"group\":\"$group\"[,}]" "$DB_FILE" > "$tmp" || true
  mv "$tmp" "$DB_FILE"
}

cmd_add() {
  local group="$1" session="$2"
  require_name group "$group"
  require_name session "$session"
  local line="{\"group\":\"$group\",\"session\":\"$session\"}"
  if grep -Fxq "$line" "$DB_FILE" 2>/dev/null; then
    echo "already exists: $group / $session" >&2
    return 0
  fi
  printf '%s\n' "$line" >> "$DB_FILE"
}

cmd_rm() {
  local group="$1" session="$2"
  require_name group "$group"
  require_name session "$session"
  local line="{\"group\":\"$group\",\"session\":\"$session\"}"
  local tmp
  tmp="$(mktemp)"
  grep -Fxv "$line" "$DB_FILE" > "$tmp" || true
  mv "$tmp" "$DB_FILE"
}

cmd_list_groups() {
  sed -n 's/.*"group":"\([^"]*\)".*/\1/p' "$DB_FILE" | sort -u
}

cmd_list_sessions() {
  local group="$1"
  require_name group "$group"
  grep -E "\"group\":\"$group\"," "$DB_FILE" 2>/dev/null \
    | sed -n 's/.*"session":"\([^"]*\)".*/\1/p'
}

cmd_list() {
  local g
  while IFS= read -r g; do
    [[ -n "$g" ]] || continue
    printf '[%s]\n' "$g"
    cmd_list_sessions "$g" | sed 's/^/  /'
  done < <(cmd_list_groups)
}

# *** two-stage fzf popup: group -> session -> switch-client
cmd_switch() {
  if ! command -v fzf >/dev/null 2>&1; then
    tmux display-message 'group switcher: install fzf to enable fuzzy search'
    exit 1
  fi

  local groups
  groups="$(cmd_list_groups)"
  if [[ -z "$groups" ]]; then
    tmux display-message "no groups defined; use: $SELF add-group <name>"
    exit 0
  fi

  # **** stage 1: build "<group> [sessions: N]" lines, pick a group
  local group_lines=()
  local g count
  while IFS= read -r g; do
    [[ -n "$g" ]] || continue
    count=$(cmd_list_sessions "$g" | grep -c . || true)
    group_lines+=("$g [sessions: $count]")
  done <<< "$groups"

  local group_selection group_name
  group_selection=$(
    printf '%s\n' "${group_lines[@]}" \
      | fzf --layout=reverse \
            --prompt='group> ' \
            --header='Select a tmux group' \
            --preview-window=right,40% \
            --preview "$SELF list-sessions {1}"
  ) || exit 0
  [[ -n "$group_selection" ]] || exit 0
  group_name="${group_selection%% *}"

  # **** stage 2: list sessions in group, annotate with live tmux state
  local sessions
  sessions=$(cmd_list_sessions "$group_name")
  if [[ -z "$sessions" ]]; then
    tmux display-message "group '$group_name' has no sessions"
    exit 0
  fi

  local session_lines=() s windows attached state
  while IFS= read -r s; do
    [[ -n "$s" ]] || continue
    if tmux has-session -t="$s" 2>/dev/null; then
      windows=$(tmux display-message -p -t "$s" '#{session_windows}')
      if [[ "$(tmux display-message -p -t "$s" '#{session_attached}')" != "0" ]]; then
        state="attached"
      else
        state="detached"
      fi
      session_lines+=("$s [windows: $windows] [$state]")
    else
      session_lines+=("$s [not running]")
    fi
  done <<< "$sessions"

  local session_selection session_name
  session_selection=$(
    printf '%s\n' "${session_lines[@]}" \
      | fzf --layout=reverse \
            --prompt="$group_name > " \
            --header="Select session in group '$group_name'" \
            --preview-window=right,40% \
            --preview 'tmux list-windows -t {1} -F "#{window_index}: #{window_name} (#{window_panes} panes)" 2>/dev/null || echo "(session not running)"'
  ) || exit 0
  [[ -n "$session_selection" ]] || exit 0
  session_name="${session_selection%% *}"

  if ! tmux has-session -t="$session_name" 2>/dev/null; then
    tmux display-message "session '$session_name' is not running"
    exit 0
  fi

  tmux switch-client -t "$session_name"
}

main() {
  ensure_db
  [[ $# -ge 1 ]] || { usage; exit 1; }
  local cmd="$1"; shift
  case "$cmd" in
    add-group)     [[ $# -eq 1 ]] || { usage; exit 1; }; cmd_add_group "$@" ;;
    rm-group)      [[ $# -eq 1 ]] || { usage; exit 1; }; cmd_rm_group "$@" ;;
    add)           [[ $# -eq 2 ]] || { usage; exit 1; }; cmd_add "$@" ;;
    rm)            [[ $# -eq 2 ]] || { usage; exit 1; }; cmd_rm "$@" ;;
    list-groups)   cmd_list_groups ;;
    list-sessions) [[ $# -eq 1 ]] || { usage; exit 1; }; cmd_list_sessions "$@" ;;
    list)          cmd_list ;;
    switch)        cmd_switch ;;
    -h|--help|help) usage ;;
    *)             usage; exit 1 ;;
  esac
}

main "$@"
