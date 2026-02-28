#!/bin/sh

# Check if the notifier process is still running
if [ -f /tmp/notifier.pid ]; then
  PID=$(cat /tmp/notifier.pid)
  if kill -0 "$PID" 2>/dev/null; then
    exit 0  # Process is alive
  fi
fi

exit 1  # Process is dead
