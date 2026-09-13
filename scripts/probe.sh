#!/usr/bin/env bash
#
# Report what this container can actually reach. Run it first on a new node:
# every failure mode so far has been something not passed through from the host,
# and that is far cheaper to see here than part way into a flash.
#
set -uo pipefail

L4T_DIR=${L4T_DIR:-/opt/l4t}
ok=0; bad=0
chk() { if eval "$2" >/dev/null 2>&1; then printf '  [ ok ] %s\n' "$1"; ok=$((ok+1));
        else printf '  [FAIL] %s\n' "$1"; bad=$((bad+1)); fi; }

echo "=== privileges ==="
chk "running as root inside the container"     '[ "$(id -u)" = 0 ]'
chk "/dev/loop-control present (flash.sh builds images on loop devices)" '[ -e /dev/loop-control ]'
chk "can create a loop device"                 'losetup -f'

echo "=== host passthrough ==="
chk "/dev/bus/usb mounted"                     '[ -d /dev/bus/usb ]'
chk "lsusb works"                              'lsusb'
chk "L4T tree at ${L4T_DIR}/Linux_for_Tegra"   "[ -x ${L4T_DIR}/Linux_for_Tegra/flash.sh ]"

echo "=== devices ==="
printf '  NVIDIA (recovery=7f21, booted=7020): %s\n' "$(lsusb -d 0955: 2>/dev/null | sed 's/^/\n    /' || echo 'none')"
printf '  relay boards: %s\n' "$(ls /dev/serial/by-id/ 2>/dev/null | grep -ci qt_py || echo 0)"
printf '  serial ports: %s\n' "$(ls /dev/ttyACM* /dev/ttyUSB* 2>/dev/null | tr '\n' ' ' || echo none)"
printf '  video nodes : %s\n' "$(ls /dev/video* 2>/dev/null | tr '\n' ' ' || echo none)"

echo "=== toolchain ==="
for t in flash.sh dtc python3 lbzip2 qemu-aarch64-static gst-launch-1.0; do
  if [ "$t" = flash.sh ]; then chk "$t" "[ -x ${L4T_DIR}/Linux_for_Tegra/flash.sh ]"
  else chk "$t" "command -v $t"; fi
done
python3 -c "import serial" 2>/dev/null && echo "  [ ok ] python3 pyserial" || { echo "  [FAIL] python3 pyserial"; bad=$((bad+1)); }
python3 -c "import PIL"    2>/dev/null && echo "  [ ok ] python3 pillow"  || { echo "  [FAIL] python3 pillow";  bad=$((bad+1)); }

echo
echo "${ok} ok, ${bad} failed"
[ "${bad}" -eq 0 ] || echo "note: a FAIL on usb/loop/serial usually means the run is missing --privileged or a bind mount"
exit 0
