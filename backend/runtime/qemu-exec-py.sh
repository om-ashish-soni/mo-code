#!/system/bin/sh
# qemu-exec-py.sh — run one shell command inside a fresh Alpine+python3 VM.
#
# Strategy:
#   1) Boot qemu-system-aarch64 in background, reading stdin from a named pipe,
#      writing serial output to a tempfile.
#   2) Poll the tempfile for the guest shell prompt '/ #'. This replaces the
#      previous fixed `sleep 8` — boot time varies 8-18 s phone-to-phone under
#      untrusted_app cgroup limits, and short sleeps silently dropped input.
#   3) Once the prompt is up, push a marker-framed script into the fifo.
#   4) Wait for qemu to poweroff, then awk-parse the log between markers.
#
# Knobs (env):
#   QEMU_EXEC_TIMEOUT  overall wall-clock limit in seconds (default 90)
#   QEMU_BOOT_TIMEOUT  max seconds to wait for guest shell prompt (default 40)
#   QEMU_INITRD        initramfs path override (default $HERE/boot/initramfs-rootfs-py.cpio.gz)
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
CMD="${1:-}"
if [ -z "$CMD" ]; then
  echo "usage: $0 '<shell command>'" >&2
  exit 2
fi

MARKER_START="__MO_QEMU_START__"
MARKER_END="__MO_QEMU_END_RC="
TIMEOUT="${QEMU_EXEC_TIMEOUT:-90}"
BOOT_TIMEOUT="${QEMU_BOOT_TIMEOUT:-40}"
INITRD="${QEMU_INITRD:-$HERE/boot/initramfs-rootfs-py.cpio.gz}"
# LINE_PAUSE controls the host→guest drip rate. The emulated pl011 UART on
# -machine virt has a 16-byte FIFO; bursting the full script causes mid-command
# byte loss (e.g. `echo ok` arriving as `echo` with 'ok ' dropped). Splitting
# into short lines + 0.15s pause between lines empirically eliminates the loss
# on OnePlus CPH2467 / Android 15.
LINE_PAUSE="${QEMU_LINE_PAUSE:-0.15}"

export LD_LIBRARY_PATH="$HERE/lib:/system/lib64"

# Write the per-command guest script to a tempfile, one statement per line.
# Splitting the previous `; ; ;` single-line form into discrete lines is what
# lets us pace them through the narrow UART without UART-FIFO overrun.
GUEST_SCRIPT="$HERE/qemu-guest.$$"
rm -f "$GUEST_SCRIPT"
{
  printf 'stty -echo -icanon -onlcr 2>/dev/null\n'
  printf "printf '\\n%%s\\n' %s\n" "$MARKER_START"
  printf '( %s ) 2>&1\n' "$CMD"
  printf "printf '\\n%%s%%d\\n' %s \$?\n" "$MARKER_END"
  printf 'poweroff -f\n'
} > "$GUEST_SCRIPT"

SERIAL_LOG="$(mktemp "$HERE/qemu-serial.XXXXXX" 2>/dev/null || echo "$HERE/qemu-serial.$$")"
FIFO="$HERE/qemu-in.$$.fifo"
rm -f "$FIFO"
mkfifo "$FIFO" 2>/dev/null || { echo "qemu-exec: mkfifo $FIFO failed" >&2; rm -f "$SERIAL_LOG"; exit 3; }

# Start qemu in background reading from fifo.
"$HERE/bin/qemu-system-aarch64" \
  -L "$HERE/roms/qemu" \
  -machine virt -cpu max -smp 1 -m 256 \
  -kernel "$HERE/boot/vmlinuz-virt" \
  -initrd "$INITRD" \
  -append "console=ttyAMA0 quiet rdinit=/init TERM=dumb" \
  -nographic -display none \
  -serial stdio -monitor none \
  -no-reboot -net none \
  < "$FIFO" > "$SERIAL_LOG" 2>&1 &
QPID=$!

# Hold the write-end open so mkfifo doesn't EOF prematurely.
exec 9>"$FIFO"

# Overall timeout watchdog — kill qemu if it runs past TIMEOUT.
(
  sleep "$TIMEOUT"
  if kill -0 "$QPID" 2>/dev/null; then
    kill -TERM "$QPID" 2>/dev/null
    sleep 1
    kill -KILL "$QPID" 2>/dev/null
  fi
) &
WATCHDOG=$!

# Poll the serial log for the guest shell prompt '/ #' — that's the signal
# the Alpine init finished and /bin/sh is ready to consume stdin.
BOOT_DEADLINE=$(( $(date +%s) + BOOT_TIMEOUT ))
PROMPT_SEEN=0
while [ "$(date +%s)" -lt "$BOOT_DEADLINE" ]; do
  if kill -0 "$QPID" 2>/dev/null; then :; else break; fi
  if [ -s "$SERIAL_LOG" ] && grep -q '/ #' "$SERIAL_LOG" 2>/dev/null; then
    PROMPT_SEEN=1
    break
  fi
  sleep 1
done

if [ "$PROMPT_SEEN" = 1 ]; then
  # Drip-feed the guest script one line at a time with $LINE_PAUSE between
  # lines. The emulated pl011 UART on `-machine virt` has only a 16-byte FIFO
  # and no flow control, so bursting the whole script loses bytes — symptom:
  # `echo ok` arriving as `echo` (the 'ok ' is silently dropped mid-FIFO).
  while IFS= read -r _line; do
    printf '%s\n' "$_line" >&9
    sleep "$LINE_PAUSE"
  done < "$GUEST_SCRIPT"
fi

# Close write end → guest sees EOF after script is consumed.
exec 9>&-

# Wait for qemu to exit, then stand down the watchdog.
wait "$QPID" 2>/dev/null
QEXIT=$?
kill "$WATCHDOG" 2>/dev/null
wait "$WATCHDOG" 2>/dev/null

rm -f "$FIFO"

if [ "$PROMPT_SEEN" = 0 ]; then
  echo "qemu-exec: guest shell prompt not seen within ${BOOT_TIMEOUT}s (boot stuck or rootfs panic)" >&2
  echo "--- last 1 KB of serial log ---" >&2
  tail -c 1024 "$SERIAL_LOG" >&2
  rm -f "$SERIAL_LOG" "$GUEST_SCRIPT"
  exit 4
fi

# Parse marker-framed output. Everything between START and END is guest stdout+stderr.
awk -v s="$MARKER_START" -v e="$MARKER_END" '
  BEGIN { in_out = 0; rc = -1 }
  {
    if (index($0, s) > 0) { in_out = 1; next }
    if (index($0, e) > 0) {
      pos = index($0, e); rest = substr($0, pos + length(e))
      gsub(/[\r[:space:]]+$/, "", rest); rc = rest + 0; in_out = 0; next
    }
    if (in_out == 1) print $0
  }
  END { exit (rc == -1 ? 1 : rc) }
' "$SERIAL_LOG"
AWK_RC=$?

# If markers weren't found (AWK_RC=1 with no content before END), dump the
# tail of the serial log to stderr so callers can see what the guest actually
# received. This surfaces byte-loss or unexpected boot panics to the LLM
# instead of silently returning exit=1 with empty output.
if [ "$AWK_RC" != 0 ] && ! grep -q "$MARKER_END" "$SERIAL_LOG" 2>/dev/null; then
  echo "qemu-exec: end marker missing — dumping last 1 KB of serial for diagnosis" >&2
  tail -c 1024 "$SERIAL_LOG" >&2
fi

if [ -n "${QEMU_KEEP_SERIAL_LOG:-}" ]; then
  echo "qemu-exec: kept serial log at $SERIAL_LOG" >&2
else
  rm -f "$SERIAL_LOG"
fi
rm -f "$GUEST_SCRIPT"
exit $AWK_RC
