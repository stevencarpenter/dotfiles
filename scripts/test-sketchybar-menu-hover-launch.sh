#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
export XDG_CACHE_HOME="$tmp/cache" TEST_PARENT="$$" TEST_DIR="$tmp"
mkdir -p "$tmp/bin" "$XDG_CACHE_HOME/sketchybar"
pids=()
cleanup() {
  for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
  wait 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

cat > "$tmp/process.c" <<'EOF'
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>

static char active[4096];
static void stop(int sig) {
    (void)sig;
    if (active[0]) rmdir(active);
    _exit(0);
}
int main(int argc, char **argv) {
    signal(SIGTERM, stop);
    if (argc > 1) {
        if (argc != 4 || strcmp(argv[2], getenv("DAEMON_PID"))) return 2;
        snprintf(active, sizeof active, "%s/active", getenv("TEST_DIR"));
        if (mkdir(active, 0700)) return 3;
        usleep(200000);
        if (unlink(argv[3])) return 4;
        char log[4096];
        snprintf(log, sizeof log, "%s/launches", getenv("TEST_DIR"));
        FILE *f = fopen(log, "a");
        if (!f) return 5;
        fprintf(f, "%d\n", getpid());
        fclose(f);
    }
    for (;;) pause();
}
EOF
/usr/bin/xcrun clang -Wall -Wextra -Werror "$tmp/process.c" -o "$tmp/bin/sketchybar"
cp "$tmp/bin/sketchybar" "$XDG_CACHE_HOME/sketchybar/sketchybar-menu-hover"
cat > "$tmp/bin/pgrep" <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/pgrep -P "$TEST_PARENT" "$@"
EOF
cat > "$tmp/bin/pkill" <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/pkill -P "$TEST_PARENT" "$@"
EOF
chmod +x "$tmp/bin/pgrep" "$tmp/bin/pkill"
export PATH="$tmp/bin:$PATH"
sketchybar &
DAEMON_PID=$!
pids+=("$DAEMON_PID")
export DAEMON_PID
sleep 0.1
sketchybar &
pids+=("$!")
sleep 0.1
[[ "$(pgrep -x sketchybar | wc -l | tr -d ' ')" == 2 ]]
[[ "$(pgrep -o -u "$UID" -x sketchybar)" == "$DAEMON_PID" ]]

lock="$XDG_CACHE_HOME/sketchybar/menu-hover.lock"
/usr/bin/shlock -f "$lock" -p "$$"
for _ in {1..4}; do
  bash "$root/home/.config/sketchybar/plugins/menu_bar_hover.sh" &
  pids+=("$!")
done
sleep 0.3
[[ ! -e "$tmp/launches" ]]
rm "$lock"
for _ in {1..100}; do
  if [[ -f "$tmp/launches" ]] && [[ "$(wc -l < "$tmp/launches" | tr -d ' ')" == 4 ]]; then
    break
  fi
  sleep 0.05
done
[[ "$(wc -l < "$tmp/launches" | tr -d ' ')" == 4 ]]
[[ "$(pgrep -x sketchybar-menu-hover | wc -l | tr -d ' ')" == 1 ]]
[[ ! -e "$lock" ]]
printf 'Overlapping reloads and multiple daemon-name matches passed\n'
