#!/bin/sh
# Claude Lights — Claude Code hook.
#
# Claude Code runs this script for session events and passes the event as JSON
# on stdin. It writes the session's current state to
#   ~/.claude/claude-lights/sessions/<session_id>.json
# and the Claude Lights menu bar app picks it up from there.
#
# States:
#   working  — the agent is running              (orange)
#   done     — the agent finished and replied    (green)
#   waiting  — the agent needs you (question or permission prompt)  (red)
#
# This script must stay silent on stdout (for some events stdout becomes part of
# the model's context) and must always exit 0 so it never blocks Claude.
#
# Uses only tools that ship with macOS (/bin/sh, /usr/bin/plutil, ps, sed).

DIR="$HOME/.claude/claude-lights/sessions"

input=$(cat)

# Read a top-level value from the event JSON ("" when missing).
# plutil prints errors on stdout, so the exit status decides.
get() {
    _v=$(printf '%s' "$input" | /usr/bin/plutil -extract "$1" raw -o - - 2>/dev/null) || _v=""
    printf '%s' "$_v"
}

# Read a value from the existing session file ("" when missing).
get_file() {
    _v=$(/usr/bin/plutil -extract "$1" raw -o - "$file" 2>/dev/null) || _v=""
    printf '%s' "$_v"
}

# JSON-escape a string value (backslashes, quotes; drop control characters).
esc() {
    printf '%s' "$1" | /usr/bin/sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | /usr/bin/tr -d '\000-\037'
}

# Find the PID of the `claude` process that runs this hook, so the app can
# remove the light when that process exits.
find_claude_pid() {
    p=$PPID
    i=0
    while [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null && [ "$i" -lt 10 ]; do
        comm=$(/bin/ps -o comm= -p "$p" 2>/dev/null)
        case "${comm##*/}" in
            claude|claude-code|node) echo "$p"; return ;;
        esac
        p=$(/bin/ps -o ppid= -p "$p" 2>/dev/null | /usr/bin/tr -d ' ')
        i=$((i + 1))
    done
    echo 0
}

event=$(get hook_event_name)
sid=$(get session_id)

# Session ids are UUIDs; refuse anything that could escape the directory.
case "$sid" in
    ''|*[!A-Za-z0-9_-]*) exit 0 ;;
esac

file="$DIR/$sid.json"
state=""

case "$event" in
    SessionStart)
        # A compaction keeps whatever state the session was in.
        if [ "$(get source)" != "compact" ] || [ ! -f "$file" ]; then
            state=done
        fi
        ;;
    UserPromptSubmit|PostToolUse|PostToolUseFailure|PreCompact)
        state=working
        ;;
    PreToolUse)
        if [ "$(get tool_name)" = "AskUserQuestion" ]; then
            state=waiting
        else
            state=working
        fi
        ;;
    PermissionRequest)
        state=waiting
        ;;
    Notification)
        case "$(get notification_type)" in
            permission_prompt|elicitation_dialog)
                state=waiting
                ;;
            '')
                # Older Claude Code versions don't send notification_type.
                case "$(get message)" in
                    *ermission*) state=waiting ;;
                esac
                ;;
        esac
        ;;
    Stop)
        state=done
        ;;
    SessionEnd)
        rm -f "$file"
        exit 0
        ;;
esac

[ -z "$state" ] && exit 0

mkdir -p "$DIR" 2>/dev/null || exit 0

now=$(/bin/date +%s)
pid=0
started=$now
cwd=$(get cwd)
transcript=$(get transcript_path)
if [ -f "$file" ]; then
    [ -z "$cwd" ] && cwd=$(get_file cwd)
    [ -z "$transcript" ] && transcript=$(get_file transcript_path)
    old_pid=$(get_file pid)
    old_started=$(get_file started)
    case "$old_pid" in ''|*[!0-9]*) old_pid=0 ;; esac
    case "$old_started" in ''|*[!0-9]*) ;; *) started=$old_started ;; esac
    if [ "$old_pid" -gt 0 ] && kill -0 "$old_pid" 2>/dev/null; then
        pid=$old_pid
    fi
fi
[ "$pid" -eq 0 ] && pid=$(find_claude_pid)

cwd=$(esc "$cwd")
transcript=$(esc "$transcript")

tmp="$file.$$.tmp"
printf '{"session_id":"%s","state":"%s","event":"%s","cwd":"%s","transcript_path":"%s","pid":%s,"started":%s,"updated":%s}\n' \
    "$sid" "$state" "$event" "$cwd" "$transcript" "$pid" "$started" "$now" > "$tmp" \
    && mv -f "$tmp" "$file"

exit 0
