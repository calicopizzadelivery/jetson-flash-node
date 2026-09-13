# NVIDIA Jetson Nano flashing and bench-management environment.
#
# Everything needed to drive a Jetson from a host: NVIDIA's L4T flash.sh and its
# dependencies, plus the relay/recovery tooling that puts the module into RCM in
# the first place.
#
# 22.04 rather than the 18.04 NVIDIA documents for R32.x: flash.sh itself is
# shell and python and does not care, and 18.04 is past end of life, so its apt
# repositories have moved to old-releases and builds break unpredictably.
# apply_binaries.sh needs qemu-aarch64-static, which is installed below.
#
# SPDX-License-Identifier: Apache-2.0
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

# Split into groups so a failure names the culprit rather than one opaque layer.
RUN apt-get update && apt-get install -y --no-install-recommends \
      bash coreutils findutils sed gawk grep tar bzip2 lbzip2 xz-utils zip unzip \
      ca-certificates curl wget \
 && rm -rf /var/lib/apt/lists/*

# flash.sh proper: loop devices, partitioning, filesystem and image tooling.
RUN apt-get update && apt-get install -y --no-install-recommends \
      util-linux mount parted e2fsprogs dosfstools cpio rsync kmod \
      binutils openssl sudo file bc \
 && rm -rf /var/lib/apt/lists/*

# Device tree compiler, XML tooling, and the aarch64 emulation apply_binaries.sh
# needs to run target-architecture maintainer scripts in the rootfs chroot.
RUN apt-get update && apt-get install -y --no-install-recommends \
      device-tree-compiler libxml2-utils qemu-user-static \
 && rm -rf /var/lib/apt/lists/*

# Bench management: relay control, recovery sequencing, USB inspection.
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-serial python3-pil usbutils \
 && rm -rf /var/lib/apt/lists/*

# HDMI capture, so the container can read the target's display as well as flash
# it. Kept to the plugin sets that actually carry v4l2src, jpegdec and pngenc.
RUN apt-get update && apt-get install -y --no-install-recommends \
      gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
 && rm -rf /var/lib/apt/lists/*

# The L4T tree is bind-mounted, never baked in: it is ~15 GB, it is NVIDIA's to
# redistribute rather than ours, and it changes independently of this image.
# flash.sh gates on the USER environment variable rather than the actual uid:
#   if [ "${no_root_check}" != "1" ] && [ "${USER}" != "root" ]
# Docker sets no USER by default, so a genuinely-root container fails that test
# and exits 21 with "flash.sh requires root privilege". Setting it is the fix;
# HOME is already /root.
ENV USER=root
ENV LOGNAME=root

ENV L4T_DIR=/opt/l4t
ENV PATH=/opt/jetson/tools:/opt/jetson/scripts:${PATH}
ENV PYTHONUNBUFFERED=1

COPY tools/   /opt/jetson/tools/
COPY scripts/ /opt/jetson/scripts/
COPY docker/entrypoint.sh /usr/local/bin/entrypoint
RUN chmod +x /usr/local/bin/entrypoint /opt/jetson/tools/* /opt/jetson/scripts/* 2>/dev/null || true

WORKDIR /opt/jetson
ENTRYPOINT ["/usr/local/bin/entrypoint"]
CMD ["help"]
