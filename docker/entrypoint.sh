#!/usr/bin/env bash
#
# Container entrypoint. Subcommands are thin wrappers so the same verbs work
# whether you are on the bench host or a remote node.
#
set -euo pipefail

L4T_DIR=${L4T_DIR:-/opt/l4t}
TREE="${L4T_DIR}/Linux_for_Tegra"

usage() {
  cat <<'USAGE'
jetson-flash-node

  recovery        put the module into USB recovery (RCM) via the relay boards
  power <cmd>     cycle | off | on   -- back-feed-aware Jetson power control
  relay <args>    raw relay control (see: relay --help)
  flash [args]    run L4T flash.sh  (--board, --dtb; defaults suit a matched
                  FAB 300+ module on a B01 carrier)
  prepare         unpack an L4T BSP into a flashable tree
  preseed         create the user account before flashing, so oem-config
                  never runs (--user, --password, --hostname, --autologin)
  hdmi <cmd>      grab | status  -- read the target's HDMI output
  run <cmd>...    run shell commands on the target over its serial console
  probe           report what the container can see: USB, serial, L4T tree
  shell           interactive bash
  help            this text

The L4T tree is expected at ${L4T_DIR}/Linux_for_Tegra, bind-mounted from the
host. Run "prepare" once if it is not there.
USAGE
}

case "${1:-help}" in
  help|-h|--help) usage ;;
  shell)          shift; exec bash "$@" ;;
  probe)          exec /opt/jetson/scripts/probe.sh ;;
  recovery)       shift; exec python3 /opt/jetson/tools/enter-recovery.py "$@" ;;
  power)          shift; exec python3 /opt/jetson/tools/jetson-power.py "$@" ;;
  relay)          shift; exec python3 /opt/jetson/tools/relayctl.py "$@" ;;
  hdmi)           shift; exec python3 /opt/jetson/tools/hdmi.py "$@" ;;
  run)            shift; exec python3 /opt/jetson/tools/target-run.py "$@" ;;
  prepare)        shift; exec /opt/jetson/scripts/l4t-prepare.sh "$@" ;;
  preseed)        shift; exec /opt/jetson/scripts/l4t-preseed.sh "$@" ;;
  flash)          shift; exec /opt/jetson/scripts/l4t-flash.sh "$@" ;;
  *)              echo "unknown command: $1" >&2; echo >&2; usage >&2; exit 2 ;;
esac
