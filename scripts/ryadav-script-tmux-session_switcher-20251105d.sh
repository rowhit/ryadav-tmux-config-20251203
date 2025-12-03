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
format='#{session_name}  [windows: #{session_windows}] [#{?session_attached,attached,detached}]'

# *** show the picker window
if ! command -v fzf >/dev/null 2>&1; then
  tmux display-message 'session switcher: install fzf to enable fuzzy search'
  exit 1
fi

# *** bring the picker for user to select the sessiion using fuzzy finder
picker=(fzf --layout=reverse
  --prompt='session> '
  --header='Select a tmux session'
  --preview-window=down,20%,border-top
  --preview 'tmux list-windows -t {1} -F "#{window_index}: #{window_name} (#{window_panes} panes)"')

# *** ask user to select the session
selection="$(tmux list-sessions -F "$format" | "${picker[@]}")" || exit 0
[ -n "$selection" ] || exit 0

# *** parse the return string which may have other elements in it
# we just need the session name
selection_string="${selection%%$'\t'*}"
# tmux display-message "Here is you selection string : ${selection_string}"

IFS=' ' read -r session_name _ <<<"$selection_string"

tmux display-message "Here is you session name : ${session_name}"

# *** once session is selected then switch to that session
tmux switch-client -t "${session_name}"
