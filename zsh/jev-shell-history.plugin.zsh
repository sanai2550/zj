# jev-shell-history: Fish-style autosuggestions for zsh, ranked by Jev (TypeSafe).
#
# As you type, the last JEV_HISTORY_LIMIT distinct history entries are sent to
# Jev, which picks the one you are most likely typing. The suggestion is shown
# after the cursor in grey. Press → (or End / ^E) at the end of the line to
# accept it.
#
#   source /path/to/jev-shell-history/zsh/jev-shell-history.plugin.zsh
#
# Requires zsh 5.9+, node 22+, and TYPESAFE_API_KEY in the environment.

0="${${ZERO:-${0:#$ZSH_ARGZERO}}:-${(%):-%N}}"
typeset -g JEV_PLUGIN_DIR="${0:A:h:h}"

: ${JEV_HISTORY_LIMIT:=100}     # recent distinct commands to consider
: ${JEV_MIN_CHARS:=2}           # do nothing until this many characters are typed
: ${JEV_THRESHOLD:=0.5}         # fuzzy mode: min probability that *some* command completes the input
: ${JEV_MIN_SCORE:=0.3}         # fuzzy mode: min probability of the top candidate
: ${JEV_STRONG_SCORE:=0.9}      # fuzzy mode: a top score this high overrides JEV_THRESHOLD
: ${JEV_HIGHLIGHT:='fg=8'}      # zle highlight spec for the suggestion text
: ${JEV_SHOW_SCORE:=1}          # append the score, e.g. "git status  [0.87]"
: ${JEV_NODE:=node}
: ${JEV_MODEL:=}                # empty = SDK default (jev-latest)
: ${JEV_DEBUG_LOG:=}            # path; when set, each response is appended there

typeset -g _JEV_FD= _JEV_PID= _JEV_REQUEST_BUFFER=
typeset -g _JEV_SUGGESTION= _JEV_KIND= _JEV_SCORE= _JEV_LAST_BUFFER=

zmodload zsh/system
autoload -Uz add-zle-hook-widget

# ---------------------------------------------------------------- display --

_jev_clear() {
  _JEV_SUGGESTION= _JEV_KIND= _JEV_SCORE=
  POSTDISPLAY=
  region_highlight=("${(@)region_highlight:#*memo=jev-shell-history}")
}

_jev_show() {
  local text
  if [[ $_JEV_KIND == prefix ]]; then
    text="${_JEV_SUGGESTION#"$BUFFER"}"
  else
    text="  ⇢ ${_JEV_SUGGESTION}"
  fi
  (( JEV_SHOW_SCORE )) && text+="  [${_JEV_SCORE}]"
  POSTDISPLAY="$text"
  region_highlight=("${(@)region_highlight:#*memo=jev-shell-history}")
  region_highlight+=("$#BUFFER $(( $#BUFFER + $#POSTDISPLAY )) $JEV_HIGHLIGHT memo=jev-shell-history")
}

# ------------------------------------------------------------------ async --

_jev_cancel() {
  if [[ -n $_JEV_FD ]]; then
    zle -F $_JEV_FD 2>/dev/null
    exec {_JEV_FD}<&-
    _JEV_FD=
  fi
  if [[ -n $_JEV_PID ]]; then
    kill -TERM $_JEV_PID 2>/dev/null
    _JEV_PID=
  fi
  _JEV_REQUEST_BUFFER=
}

_jev_request() {
  _jev_cancel
  _JEV_REQUEST_BUFFER="$BUFFER"

  local -a args=(--history "${HISTFILE:-$HOME/.zsh_history}"
                 --limit "$JEV_HISTORY_LIMIT" --min-chars "$JEV_MIN_CHARS"
                 --threshold "$JEV_THRESHOLD" --min-score "$JEV_MIN_SCORE"
                 --strong-score "$JEV_STRONG_SCORE")
  [[ -n $JEV_MODEL ]] && args+=(--model "$JEV_MODEL")

  local errlog="${JEV_DEBUG_LOG:-/dev/null}"
  exec {_JEV_FD}< <(
    echo $sysparams[pid]
    exec $JEV_NODE "$JEV_PLUGIN_DIR/src/cli.ts" --buffer "$BUFFER" "${args[@]}" 2>>| "$errlog"
  )
  read -u $_JEV_FD _JEV_PID
  zle -F -w $_JEV_FD _jev_response
}

zle -N _jev_response
_jev_response() {
  local fd=$1 output header body
  IFS= read -r -d '' -u $fd output
  zle -F $fd 2>/dev/null
  exec {fd}<&-
  [[ $fd == $_JEV_FD ]] && _JEV_FD= _JEV_PID=

  [[ -n $JEV_DEBUG_LOG ]] && print -r -- "buffer=${(q)_JEV_REQUEST_BUFFER} output=${(q)output}" >>| "$JEV_DEBUG_LOG"

  # Only apply the answer if the line is still what we asked about.
  if [[ -n $output && $BUFFER == $_JEV_REQUEST_BUFFER ]]; then
    header="${output%%$'\n'*}"
    body="${output#*$'\n'}"
    local -a fields=(${=header})
    _JEV_SCORE="${fields[1]}"
    _JEV_KIND="${fields[3]}"
    _JEV_SUGGESTION="$body"
    _jev_show
  fi
  _JEV_REQUEST_BUFFER=
  zle -R
}

# ------------------------------------------------------------------ hooks --

_jev_pre_redraw() {
  [[ $BUFFER == $_JEV_LAST_BUFFER ]] && return 0
  _JEV_LAST_BUFFER="$BUFFER"

  # Typing along an existing prefix suggestion keeps it without a new request.
  if [[ $_JEV_KIND == prefix && -n $BUFFER && $_JEV_SUGGESTION == "$BUFFER"?* ]]; then
    _jev_show
    return 0
  fi

  _jev_clear
  local trimmed="${${BUFFER##[[:space:]]#}%%[[:space:]]#}"
  if [[ $#trimmed -ge $JEV_MIN_CHARS && $CURSOR -eq $#BUFFER ]]; then
    _jev_request
  else
    _jev_cancel
  fi
}

_jev_line_init() {
  _JEV_LAST_BUFFER=
  _jev_clear
}

_jev_line_finish() {
  _jev_cancel
  _jev_clear
}

add-zle-hook-widget line-pre-redraw _jev_pre_redraw
add-zle-hook-widget line-init _jev_line_init
add-zle-hook-widget line-finish _jev_line_finish

# ----------------------------------------------------------------- accept --

jev-accept-suggestion() {
  if [[ -n $_JEV_SUGGESTION ]]; then
    BUFFER="$_JEV_SUGGESTION"
    CURSOR=$#BUFFER
    _jev_clear
    _JEV_LAST_BUFFER="$BUFFER"
    return 0
  fi
  return 1
}
zle -N jev-accept-suggestion

# At the end of the line, movement-right / end-of-line widgets accept the
# suggestion; elsewhere they behave as normal.
_jev_wrap_accepting_widget() {
  local widget=$1
  eval "
    _jev_wrapped_$widget() {
      if [[ -n \$_JEV_SUGGESTION && \$CURSOR -eq \$#BUFFER ]]; then
        zle jev-accept-suggestion
      else
        zle .$widget -- \"\$@\"
      fi
    }
  "
  zle -N "$widget" "_jev_wrapped_$widget"
}
for _jev_w in forward-char vi-forward-char end-of-line vi-end-of-line; do
  _jev_wrap_accepting_widget $_jev_w
done
unset _jev_w

# zj is an intent trigger: Enter accepts the current suggestion and executes it.
# Preserve the existing accept-line widget for normal shell/plugin behavior.
if (( ! ${+widgets[_jev_original_accept_line]} )); then
  zle -A accept-line _jev_original_accept_line
fi
_jev_accept_line() {
  if [[ $BUFFER == zj || $BUFFER == zj[[:space:]]* ]]; then
    if [[ -n $_JEV_SUGGESTION && $BUFFER == $_JEV_LAST_BUFFER && -z $_JEV_REQUEST_BUFFER ]]; then
      zle jev-accept-suggestion
    else
      zle -M 'zj: wait for a suggestion before pressing Enter'
      return 0
    fi
  fi
  zle _jev_original_accept_line
}
zle -N accept-line _jev_accept_line
