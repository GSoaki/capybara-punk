#!/usr/bin/env bash
# Uso: tests/run_smoke.sh /caminho/para/godot
set -u
GODOT="${1:-godot}"
cd "$(dirname "$0")/.."
LOGS="$(mktemp -d)"
PORT=$((25000 + RANDOM % 1000))

"$GODOT" --headless --path . --import > "$LOGS/import.log" 2>&1
"$GODOT" --headless --path . -- --smoke=host --port=$PORT > "$LOGS/host.log" 2>&1 &
HOST=$!
"$GODOT" --headless --path . -- --smoke=client --port=$PORT > "$LOGS/client.log" 2>&1 &
CLIENT=$!
wait $HOST; HOST_RC=$?
wait $CLIENT; CLIENT_RC=$?

grep -hE '^(PASS|FAIL|DONE)' "$LOGS/host.log" "$LOGS/client.log"
echo "--- erros e avisos do motor"
grep -hE '(ERROR|WARNING|SCRIPT ERROR)' "$LOGS/host.log" "$LOGS/client.log" | sort | uniq -c | sort -rn | head -30

A=$(grep -h '^LAYOUT=' "$LOGS/host.log"); B=$(grep -h '^LAYOUT=' "$LOGS/client.log")
if [ -n "$A" ] && [ "$A" = "$B" ]; then echo "PASS layout identico nos dois peers"; else echo "FAIL layout divergente"; HOST_RC=1; fi
echo "logs: $LOGS"
[ "$HOST_RC" -eq 0 ] && [ "$CLIENT_RC" -eq 0 ]
