# canvas-send: send a pre-built canvas request without exec'ing anything.
#
# Every non-Apple binary pays an endpoint-security check at exec (~30-40 ms on
# a managed Mac); /bin/zsh doesn't. So build the request once with --emit and
# send it from zsh with the socket builtins:
#
#   canvas toggle keys.tsx --id cheatsheet --data keys.json --emit > ~/.config/canvas/cheatsheet.json
#   /bin/zsh -fc 'source /path/to/canvas/cli/canvas-send.zsh; canvas-send ~/.config/canvas/cheatsheet.json'
#
# canvas-send [FILE | -] returns the canvas CLI's exit codes: 0 done (a result
# or move frame is printed raw on stdout), 1 error (message on stderr), 2 closed
# or replaced, 3 timed out waiting for a --wait result. CANVAS_SEND_TIMEOUT
# (seconds) bounds each wait for a line: 10 by default, unbounded for --wait
# requests. It honors CANVAS_HOME and never starts the server.

zmodload zsh/net/socket zsh/zselect || return 1

# Print the raw text of a member ("value" or "frame") of an event line. Events
# carrying one are two-member objects, in either order.
.canvas-send-member() {
  local v=${1#*\"$2\":}
  v=${${v## #}%\}}
  print -r -- ${v%, #\"event\": #\"*\"}
}

.canvas-send-error() {
  local msg='server error'
  [[ $1 =~ '"message": ?"(([^"\\]|\\.)*)"' ]] && msg=${match[1]//\\\"/\"}
  print -u2 -- "canvas: $msg"   # print decodes \\ \n \t and \uXXXX
}

canvas-send() {
  emulate -L zsh
  setopt extendedglob
  local src=${1:--} req line fd code=1
  [[ $src == - ]] && src=/dev/stdin
  IFS= read -r req < $src || [[ -n $req ]] || { print -u2 "canvas-send: no request in $src"; return 1 }
  local wait=0
  [[ $req == *'"wait":true'* ]] && wait=1
  local -i limit=$(( ${CANVAS_SEND_TIMEOUT:-$(( wait ? 0 : 10 ))} * 100 ))

  zsocket "${CANVAS_HOME:-$HOME/Library/Application Support/Canvas}/canvas.sock" 2>/dev/null ||
    { print -u2 "canvas-send: the canvas server is not running"; return 1 }
  fd=$REPLY
  print -r -u $fd -- $req

  while true; do
    if (( limit )) && ! zselect -t $limit -r $fd; then
      print -u2 "canvas-send: timed out waiting for the server"
      (( code = wait ? 3 : 1 ))
      break
    fi
    if ! IFS= read -r -u $fd line && [[ -z $line ]]; then
      # list ends when the server closes; anything else lost its answer.
      if [[ $req == '{"cmd":"list"'* ]]; then code=0; else print -u2 "canvas-send: lost the connection"; fi
      break
    fi
    # The event is the first or last member, so a value can't shadow it.
    if [[ ! $line =~ '^\{"event": ?"([a-z]+)"' && ! $line =~ '"event": ?"([a-z]+)"\}$' ]]; then
      print -r -- $line   # a list entry
      continue
    fi
    case $match[1] in
      (rendered) (( wait )) && continue; code=0 ;;
      (result) .canvas-send-member $line value; code=0 ;;
      (moved) .canvas-send-member $line frame; code=0 ;;
      (hidden|updated|ok|pong) code=0 ;;
      (error) .canvas-send-error $line; code=1 ;;
      (closed|replaced) code=2 ;;
      (*) continue ;;
    esac
    break
  done
  exec {fd}>&-
  return code
}
