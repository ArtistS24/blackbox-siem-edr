#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."

source "$ROOT_DIR/config/config.conf"

mkdir -p "$ROOT_DIR/$LOG_DIR"

if [ ! -f "$ROOT_DIR/$EVENT_LOG" ]; then
    touch "$ROOT_DIR/$EVENT_LOG"
fi

echo "[SIEM] Listening for agents on port $LISTEN_PORT..."

while true; do
    if command -v socat >/dev/null 2>&1; then
        socat TCP-LISTEN:$LISTEN_PORT,reuseaddr,fork SYSTEM:"cat >> '$ROOT_DIR/$EVENT_LOG'"
    elif command -v ncat >/dev/null 2>&1; then
        ncat -l -k -p "$LISTEN_PORT" >> "$ROOT_DIR/$EVENT_LOG"
    else
        python3 -c "import socketserver; s=socketserver.ThreadingTCPServer(('0.0.0.0',$LISTEN_PORT),type('H',(socketserver.StreamRequestHandler,),{'handle':lambda self:open('$ROOT_DIR/$EVENT_LOG','ab').write(self.rfile.read())})); s.allow_reuse_address=True; s.serve_forever()"
    fi
    echo "[!] socat crashed, restarting..."
    sleep 5
done