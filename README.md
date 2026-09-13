# jetson-flash-node

A container holding everything needed to flash and drive an NVIDIA Jetson Nano
from a host: NVIDIA's L4T `flash.sh` and its dependencies, plus the relay and
recovery tooling that puts the module into RCM in the first place.

Built so a bench can be deployed to a remote node and run unattended, rather
than depending on an interactive `sudo` on one particular machine.

```bash
./scripts/node build       # build the image
./scripts/node probe       # report what the container can actually reach
./scripts/node recovery    # put the module into USB recovery (RCM)
./scripts/node flash       # run the L4T flash
./scripts/node power cycle # back-feed-aware power cycle
./scripts/node preseed --user flippy --password flippy --hostname jetson-nano --autologin
./scripts/node hdmi grab -o /out/screen.png
./scripts/node shell
```

Run `probe` first on any new node. Every failure so far has been something not
passed through from the host, and that is far cheaper to see up front than part
way into a flash.

## What this does and does not buy you

It removes the **interactive password**, not the privilege.

The container needs `--privileged` for two concrete reasons: `flash.sh` builds
its images on loop devices, and the module re-enumerates with a new USB device
number every time it enters or leaves recovery, so neither a fixed `--device`
nor a narrow capability set survives a flash cycle. Membership of the `docker`
group is already root-equivalent on the host.

The real win is reproducibility and unattended operation on a remote node.

## Layout

```
docker/Dockerfile      Ubuntu 22.04 + L4T flash dependencies + bench tooling
docker/entrypoint.sh   subcommand dispatch
docker-compose.yml     privileges and bind mounts
scripts/node           host driver, wraps docker compose
scripts/probe.sh       reachability check, run this first
scripts/host-setup.sh  udev: stable /dev/hdmi-capture, keep ModemManager off the Jetson's serial gadget
scripts/host-tailscale.sh  install Tailscale for remote access
scripts/l4t-prepare.sh unpack an L4T BSP into a flashable tree
scripts/l4t-preseed.sh user, autologin, no blanking, power model
scripts/l4t-flash.sh   flash, with board config and device tree selection
tools/                 relay control, recovery sequencing, HDMI capture
```

The L4T tree is **bind-mounted, never baked into the image**: it is ~15 GB, it
is NVIDIA's to redistribute rather than ours, and it is versioned independently.
Point `L4T_HOST_DIR` at it (default `/srv/build/l4t`), or run `prepare` once to
build one.

## Things that cost time, written down

**Never `chown -R` over the L4T tree.** This one cost a day.

`chown` clears setuid and setgid bits whenever a file changes owner — a kernel
safeguard so a setuid binary cannot be handed to a new owner. A recursive chown
anywhere over `Linux_for_Tegra` therefore strips setuid from all 23 such
binaries in `rootfs/`: `sudo`, `su`, `passwd`, `pkexec`,
`dbus-daemon-launch-helper`.

Those get flashed to the target. There, `sudo` refuses to run
(`must be owned by uid 0 and have the setuid bit set`) and GDM's greeter never
starts, because it depends on exactly those helpers. The board shows the NVIDIA
splash, then a console, then **a blank screen** — which presents as an HDMI
fault and gets chased as one, on the wrong side of the cable entirely.

`l4t-flash.sh` now refuses to flash a rootfs with fewer than five setuid
binaries, and `probe` reports the count, so this cannot recur silently. Recover
by re-extracting the rootfs and re-running `prepare`; permissions come back from
the tarball.

**`flash.sh` gates on `$USER`, not the uid.** It tests
`[ "${USER}" != "root" ]`, and Docker sets no `USER` by default, so a genuinely
root container exits 21 with `flash.sh requires root privilege`. The Dockerfile
sets `USER=root`.

**Let device-tree detection do its job on matched hardware.** `flash.sh` derives
the carrier device tree from the module's FAB, because NVIDIA sells them as
matched pairs:

| Module FAB | Carrier |
|---|---|
| ≤ 299 | A02 |
| ≥ 300 | B01 |

A FAB 200 module on a B01 carrier has **no HDMI output at all**, whichever
device tree is flashed, and works immediately on an A02 carrier. Overriding the
detection to "correct" it does not help and hides the real problem — `--dtb`
defaults to `auto` for that reason, and overriding is for genuinely mismatched
parts only.

**Ubuntu 22.04, not the 18.04 NVIDIA documents.** `flash.sh` is shell and python
and does not care; 18.04 is past end of life, so its apt repositories have moved
and builds break unpredictably. `apply_binaries.sh` needs `qemu-aarch64-static`,
which is installed.

## Related

- [qtpy-relay-controller](https://github.com/calicopizzadelivery/qtpy-relay-controller)
  — firmware for the relay boards this drives
- [frdm-k64f-hid](https://github.com/calicopizzadelivery/frdm-k64f-hid)
  — USB keyboard/mouse injection into the target

## Licence

Apache-2.0. See [LICENSE](LICENSE).
