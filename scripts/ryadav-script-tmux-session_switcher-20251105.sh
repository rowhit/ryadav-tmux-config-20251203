#!/usr/bin/env bash
# * file: ~/.tmux/scripts/ryadav-script-tmux-session_switcher-20251105.sh
# ##############################################################################
# ** notes
# ******************************************************************************
# This script is suppose to bring a pop up to switch between the session.
# We can now ignore the session-finder plugin and simply use this tmux script

# ******************************************************************************
# ** main
# ******************************************************************************
set -euo pipefail

# *** get the session names
# format='#{session_name}  [windows: #{session_windows}] [#{?session_attached,attached,detached}]'
format='#{session_last_attached} #{session_name} [windows: #{session_windows}] [#{?session_attached,attached,detached}]'

# *** show the picker window
if ! command -v fzf >/dev/null 2>&1; then
  tmux display-message 'session switcher: install fzf to enable fuzzy search'
  exit 1
fi

# *** bring the picker for user to select the sessiion using fuzzy finder
picker=(fzf --layout=reverse
  --prompt='session> '
  --header='Select a tmux session'
  --with-nth=2..
  --preview-window=right,30%
  --preview 'tmux list-windows -t {2} -F "#{window_index}: #{window_name} (#{window_panes} panes)"')

# *** ask user to select the session
selection="$(tmux list-sessions -F "$format" | sort -rn | "${picker[@]}")" || exit 0
[ -n "$selection" ] || exit 0

# *** parse the return string which may have other elements in it
# we just need the session name
# selection_string="${selection%%$'\t'*}"
session_part=${selection#*$' '}
_session_name=${session_part%%$' '*}
# tmux display-message "Here is you selection string : ${session_name}"

IFS=' ' read -r session_name _ <<<"$_session_name"

# tmux display-message "Here is you session name : ${session_name}"
# *** once session is selected then switch to that session
tmux switch-client -t "${session_name}"
