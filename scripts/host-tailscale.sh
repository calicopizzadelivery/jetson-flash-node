#!/usr/bin/env bash
#
# Install Tailscale so a bench node can be reached remotely.
#
#   sudo ./scripts/host-tailscale.sh
#
# Uses Tailscale's apt repository rather than `curl | sh`: the package is then
# signed, upgradable with the rest of the system, and the script does not need
# to be trusted at run time.
#
# This installs and starts the daemon only. Joining a tailnet is deliberately
# left to you -- `tailscale up` authenticates against your account, and that is
# not something this script should do on your behalf.
#
set -euo pipefail

KEYRING=/usr/share/keyrings/tailscale-archive-keyring.gpg
LIST=/etc/apt/sources.list.d/tailscale.list

[[ ${EUID} -eq 0 ]] || { echo "error: run me with sudo" >&2; exit 1; }

. /etc/os-release
CODENAME=${VERSION_CODENAME:?cannot determine the Ubuntu codename}
BASE="https://pkgs.tailscale.com/stable/${ID}/${CODENAME}"

echo "distro: ${NAME} ${VERSION_ID} (${CODENAME})"

if ! curl -fsI --max-time 20 "${BASE}.noarmor.gpg" >/dev/null; then
  echo "error: Tailscale publishes no repository for ${ID}/${CODENAME}" >&2
  exit 1
fi

echo "installing the signing key"
tmp=$(mktemp); trap 'rm -f "${tmp}"' EXIT
curl -fsSL --max-time 60 "${BASE}.noarmor.gpg" -o "${tmp}"
# A truncated download would otherwise land as a broken keyring and fail later
# with a confusing apt error.
[[ -s ${tmp} ]] || { echo "error: downloaded keyring is empty" >&2; exit 1; }
install -o root -g root -m 0644 "${tmp}" "${KEYRING}"

echo "adding the apt source"
curl -fsSL --max-time 60 "${BASE}.tailscale-keyring.list" -o "${tmp}"
grep -q "pkgs.tailscale.com" "${tmp}" || {
  echo "error: source list does not look like Tailscale's" >&2; exit 1; }
install -o root -g root -m 0644 "${tmp}" "${LIST}"

echo "installing tailscale"
apt-get update -qq
apt-get install -y tailscale

systemctl enable --now tailscaled
echo

cat <<MSG
installed. tailscaled is: $(systemctl is-active tailscaled)

To join your tailnet (this authenticates against your account, so run it
yourself):

  sudo tailscale up --hostname=$(hostname)

Add --ssh if you want Tailscale SSH on this node, and --advertise-tags=... if
you use ACL tags. Then:

  tailscale status
  tailscale ip -4
MSG
