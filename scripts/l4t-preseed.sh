#!/usr/bin/env bash
#
# Pre-seed the user account so oem-config never runs.
#
#   l4t-preseed.sh --user flippy --password flippy --hostname jetson-nano
#
# Driving oem-config's whiptail UI over the serial gadget is possible but
# miserable: arrow keys arrive unreliably, the dialogs only repaint on input,
# and a mis-sent key silently selects the wrong locale. NVIDIA ships
# tools/l4t_create_default_user.sh for exactly this -- it writes the account
# into the rootfs before flashing, so the target boots straight to a login.
#
# Run this BEFORE flashing. It edits the rootfs, so the flash after it carries
# the account.
#
set -euo pipefail

L4T_DIR=${L4T_DIR:-/opt/l4t}
TREE="${L4T_DIR}/Linux_for_Tegra"
USERNAME=""; PASSWORD=""; HOSTNAME_="jetson-nano"; AUTOLOGIN=0
NOBLANK=1; NVPMODEL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--user|--username) USERNAME="${2:-}"; shift 2 ;;
    -p|--password)        PASSWORD="${2:-}"; shift 2 ;;
    -n|--hostname)        HOSTNAME_="${2:-}"; shift 2 ;;
    -a|--autologin)       AUTOLOGIN=1; shift ;;
    --blank)              NOBLANK=0; shift ;;
    --nvpmodel)           NVPMODEL="${2:-}"; shift 2 ;;
    *) echo "usage: $0 --user U --password P [--hostname H] [--autologin]" >&2
       echo "          [--blank] [--nvpmodel N]" >&2; exit 2 ;;
  esac
done

[[ ${EUID} -eq 0 ]] || { echo "error: must run as root" >&2; exit 1; }
[[ -n ${USERNAME} ]] || { echo "error: --user is required" >&2; exit 2; }
[[ -n ${PASSWORD} ]] || { echo "error: --password is required" >&2; exit 2; }

TOOL="${TREE}/tools/l4t_create_default_user.sh"
[[ -x ${TOOL} ]] || { echo "error: ${TOOL} not found; run prepare first" >&2; exit 1; }

# The tool runs target-architecture maintainer scripts in the rootfs chroot.
command -v qemu-aarch64-static >/dev/null || {
  echo "error: qemu-aarch64-static missing" >&2; exit 1; }

echo "pre-seeding ${TREE}/rootfs"
echo "  user     : ${USERNAME}"
echo "  hostname : ${HOSTNAME_}"
echo "  autologin: $([ ${AUTOLOGIN} -eq 1 ] && echo yes || echo no)"

cd "${TREE}"
args=(-u "${USERNAME}" -p "${PASSWORD}" -n "${HOSTNAME_}" --accept-license)
[[ ${AUTOLOGIN} -eq 1 ]] && args+=(-a)

# Re-running is normal: the settings below are tuned independently of the
# account, and the account only needs creating once. useradd returns non-zero
# when the user already exists, which set -e would otherwise treat as fatal and
# silently skip everything after it.
if ! "${TOOL}" "${args[@]}"; then
  echo "note: user creation reported an error (already exists?); continuing" >&2
fi

RFS="${TREE}/rootfs"

if [[ ${AUTOLOGIN} -eq 1 ]]; then
  echo
  echo "enabling automatic login for ${USERNAME}"
  # Set this directly rather than relying on l4t_create_default_user.sh -a:
  # that tool only configures autologin as part of creating the account, so on
  # a re-run where the user already exists the flag silently does nothing.
  GDM_CONF="${RFS}/etc/gdm3/custom.conf"
  if [[ -f ${GDM_CONF} ]]; then
    # Drop any existing directives, commented or not, then add ours under
    # [daemon] so repeated runs cannot accumulate duplicates.
    sed -i -E '/^[#[:space:]]*Automatic(Login|LoginEnable)[[:space:]]*=/d' "${GDM_CONF}"
    sed -i "0,/^\[daemon\]/s//[daemon]\nAutomaticLoginEnable = true\nAutomaticLogin = ${USERNAME}/" "${GDM_CONF}"
    echo "  gdm3/custom.conf: AutomaticLogin = ${USERNAME}"
  else
    echo "  warning: ${GDM_CONF} not found; autologin not set" >&2
  fi

  # The desktop user must own its session bus and seat; l4t's default groups
  # already cover this, but nopasswdlogin is what lets GDM skip the prompt on
  # some configurations.
  if ! grep -q '^nopasswdlogin:' "${RFS}/etc/group" 2>/dev/null; then
    echo "nopasswdlogin:x:501:${USERNAME}" >> "${RFS}/etc/group"
  else
    sed -i "s/^\(nopasswdlogin:x:[0-9]*:\)\(.*\)$/\1${USERNAME}/" "${RFS}/etc/group"
  fi
  echo "  added ${USERNAME} to nopasswdlogin"
fi

if [[ ${NOBLANK} -eq 1 ]]; then
  echo
  echo "disabling screen blanking"
  # X server level, so it covers the GDM greeter and every user session
  # regardless of desktop settings. A blanked output stops transmitting TMDS
  # entirely, so to a capture dongle it is indistinguishable from an unplugged
  # cable -- which cost a great deal of time on this bench.
  install -d "${RFS}/etc/X11/xorg.conf.d"
  cat > "${RFS}/etc/X11/xorg.conf.d/10-no-blanking.conf" <<'XCONF'
# Never blank or power-save the display. This is a bench target watched through
# a capture dongle, and DPMS off is indistinguishable from "no signal".
Section "ServerFlags"
    Option "BlankTime"   "0"
    Option "StandbyTime" "0"
    Option "SuspendTime" "0"
    Option "OffTime"     "0"
EndSection

Section "Extensions"
    Option "DPMS" "Disable"
EndSection
XCONF
  echo "  wrote /etc/X11/xorg.conf.d/10-no-blanking.conf"

  EXTLINUX="${RFS}/boot/extlinux/extlinux.conf"
  if [[ -f ${EXTLINUX} ]] && ! grep -q "consoleblank=0" "${EXTLINUX}"; then
    sed -i 's/^\([[:space:]]*APPEND .*\)$/\1 consoleblank=0/' "${EXTLINUX}"
    echo "  added consoleblank=0 to the extlinux APPEND line"
  fi

  install -d "${RFS}/etc/dconf/db/local.d" "${RFS}/etc/dconf/profile"
  cat > "${RFS}/etc/dconf/db/local.d/00-no-blanking" <<'DCONF'
[org/gnome/desktop/session]
idle-delay=uint32 0

[org/gnome/desktop/screensaver]
idle-activation-enabled=false
lock-enabled=false

[org/gnome/settings-daemon/plugins/power]
sleep-inactive-ac-type='nothing'
sleep-inactive-battery-type='nothing'
idle-dim=false
DCONF
  printf 'user-db:user\nsystem-db:local\n' > "${RFS}/etc/dconf/profile/user"
  echo "  wrote GNOME dconf defaults"
fi

if [[ -n ${NVPMODEL} ]]; then
  echo
  CONF="${RFS}/etc/nvpmodel/nvpmodel_t210_jetson-nano.conf"
  if [[ -f ${CONF} ]]; then
    name=$(grep -oE "POWER_MODEL ID=${NVPMODEL} NAME=[A-Za-z0-9_]+" "${CONF}" | head -1 | sed 's/.*NAME=//')
    sed -i "s/^< PM_CONFIG DEFAULT=.*>/< PM_CONFIG DEFAULT=${NVPMODEL} >/" "${CONF}"
    echo "power model: DEFAULT=${NVPMODEL}${name:+ (${name})}"
  fi
  # nvpmodel remembers the last selected mode and that overrides the configured
  # default, so clear any inherited runtime state.
  rm -f "${RFS}/var/lib/nvpmodel/status" 2>/dev/null || true
  echo "  cleared saved runtime power-model state"
fi

echo
echo "done. flash now, and the target will boot straight to a login prompt."
