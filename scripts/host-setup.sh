#!/usr/bin/env bash
#
# One-time root setup for a bench host: stable device names and permissions
# for the capture dongle and the Jetson's own USB gadget.
#
#   sudo ./scripts/host-setup.sh
#
# The relay boards and the FRDM debug probe have their own rules in their own
# repos (qtpy-relay-controller and frdm-k64f-hid); this covers what the flash
# node itself talks to.
#
set -euo pipefail

RULE=/etc/udev/rules.d/99-jetson-bench.rules

[[ ${EUID} -eq 0 ]] || { echo "error: run me with sudo" >&2; exit 1; }

cat > "${RULE}" <<'RULES'
# MacroSilicon MS2109 HDMI capture dongle.
#
# It exposes two video nodes: index 0 captures, index 1 is UVC metadata, which
# enumerates formats happily and never yields a frame. Only the capture node
# gets the stable name. The node number itself moves whenever USB renumbers,
# which any power cycle on the switched hub can cause, so tools should open
# /dev/hdmi-capture rather than /dev/videoN.
SUBSYSTEM=="video4linux", ATTRS{idVendor}=="534d", ATTRS{idProduct}=="2109", \
  ATTR{index}=="0", SYMLINK+="hdmi-capture", TAG+="uaccess"

# A Jetson running L4T presents a USB composite gadget: network, mass storage
# and a CDC serial port that carries oem-config and a login. ModemManager
# probes every new ACM port with AT commands and holds it for tens of seconds
# -- exactly when you want to read it -- so tell it to leave this one alone.
SUBSYSTEM=="tty", ATTRS{idVendor}=="0955", ATTRS{idProduct}=="7020", \
  SYMLINK+="jetson-gadget", ENV{ID_MM_DEVICE_IGNORE}="1", TAG+="uaccess"

# The same module in USB recovery (APX), for host-side tegrarcm use outside
# the container.
SUBSYSTEM=="usb", ATTR{idVendor}=="0955", ATTR{idProduct}=="7f21", TAG+="uaccess"
RULES

udevadm control --reload-rules
udevadm trigger --subsystem-match=video4linux --subsystem-match=tty --action=add

echo "installed ${RULE}"
echo
echo "check with:"
echo "  ls -l /dev/hdmi-capture /dev/jetson-gadget"
