# Jio JIDU6111 / JIDU6411 OpenWrt snapshot builds

Build a standard OpenWrt router image for **JIDU6111** with
**`kmod-batman-adv` and `kmod-nft-bridge` built into the image**. The optional
`unifi` variant includes the existing openUF access-point integration.
Installing batman-adv does not configure a mesh: set up batman interfaces and
bridges after flashing, for your own network.

## Build locally

Use an ordinary user on an x86-64 Linux machine. Ubuntu 24.04 is the reference
host; Python **3.11 or newer** is required by the artifact verifier. Allow at
least 60 GB of free disk space and 8 GB of RAM for a full build. Install the
dependencies first (only this step needs sudo):

```sh
sudo apt-get update
sudo apt-get install -y build-essential clang flex bison g++ gawk gcc-multilib \
  g++-multilib gettext git libncurses-dev libssl-dev libelf-dev pkgconf \
  python3-setuptools python3-dev rsync swig unzip zlib1g-dev file wget zstd
git clone --branch firmware/jidu6111-snapshot https://github.com/moh1t/jidu6411-v8-unifi.git
cd jidu6411-v8-unifi
python3 -m unittest discover -s tests -v
DEVICE=6111 VARIANT=stock JOBS=2 bash ./build.sh
```

The default uses `openwrt.pin`, the latest snapshot checked with this patch set.
Set `OPENWRT_REF=main` to resolve upstream's latest commit instead; later changes
can require another patch rebase. Output is `out/6111/stock/`. Verify it with:

```sh
(cd out/6111/stock && sha256sum -c SHA256SUMS)
```

Keep the work directory if a build fails: downloaded sources and compiled tools
remain there. To retry compilation after resolving the reported error:

```sh
make -C work-6111-stock/openwrt -j2 BUILD_LOG=1
python3 scripts/verify-images.py work-6111-stock/openwrt/bin/targets/qualcommbe/ipq95xx 6111
```

Those retry commands leave images in `work-6111-stock/openwrt/bin/targets/qualcommbe/ipq95xx/`;
they do not regenerate the `out/` bundle. The full build script requires a fresh
`WORK` directory and refuses to delete earlier work. Build logs are in
`work-6111-stock/build.log` and `work-6111-stock/openwrt/logs/`.

## Build with GitHub Actions

1. Open **Actions → Build JIDU6J11 snapshot → Run workflow** in your copy of this repository.
2. Select the branch containing these changes.
3. Select **device `6111`**, **variant `stock`**, and **OpenWrt ref `main`**.
   Leave **check_only** unchecked to compile the firmware.
4. Wait for the build to succeed (a full cross-toolchain build can take hours).
5. Download the `jidu6111-snapshot-stock-<run number>` artifact and unzip it.
   Verify its contents with `sha256sum -c SHA256SUMS`.

The intended upgrade artifact has `jiorouter_ax6000-jidu6j11-6111` and
`sysupgrade.bin` in its name. Do not use the 6411 image for a 6111. This repository
also produces other image types; their presence is not an instruction to flash
them. Use the installation/recovery procedure appropriate to your router's
current firmware and unlock state. A successful compile does not validate
on-device Wi-Fi, flash layout, or sysupgrade from your currently installed image.

The workflow is **manual-only**. Pushing commits does not start a firmware build.

The workflow rejects a missing device profile, missing required packages,
missing sysupgrade image, or a checksum mismatch. Artifacts retain OpenWrt's
original names and include per-device package manifests, `profiles.json`, the
full build configuration, and `build-provenance.txt`. Diagnostics are uploaded
even on failure. Kernel modules must match the image's kernel ABI; build them
with the image rather than installing arbitrary snapshot kmods later.

## Source and hardware support

`main` resolves the newest upstream OpenWrt commit when the job starts. Exact
upstream and feed revisions are recorded in the artifact. To reproduce the
locally checked base, select **`pinned`** instead; `openwrt.pin` currently identifies
`5b8554a95eee055c5bee96f6f2dfd3beb241e0e7` (2026-10-19, kernel 6.18.55).
You can also enter a full OpenWrt commit SHA. Future upstream changes can break
the hardware patches; the build stops rather than skipping them. Applied patches
are checked for leftover merge markers before feed setup. Full builds check the
ath11k firmware download before compiling and retain per-package build logs in
the diagnostics artifact.

This kit derives from [Vijay's v8 build](https://github.com/kuduku1/jidu6411-v8-unifi)
and [Sandiep's JIDU6J11 support](https://github.com/Sandiep/openwrt/branches).
Sandiep's [build script](https://raw.githubusercontent.com/Sandiep/OpenWRT-JIDU6x11-Builds/refs/heads/main/build.sh)
builds his `JIDU6J11` branch; that is distinct from latest upstream `main`.
His [board firmware repository](https://github.com/Sandiep/firmware_qca-wireless/tree/JIDU6J11)
is another hardware-support reference.

The five hardware patches here have been rebased onto the pinned upstream revision.
A sixth patch fixes a redundant boolean kernel dependency that otherwise causes
a false dnsmasq-full Kconfig cycle on this snapshot.
They retain the v8 board data and **mac80211 backports 6.18.39** with its IPQ9574
AHB changes. This is latest OpenWrt with a deliberately pinned hardware-support
stack, not an assertion that the newest upstream wireless stack works on this
router. New upstream wireless patches overlapping that frozen stack are removed
by the compatibility patch. Artifact checksums and source hashes remain enabled.
The legacy Wi-Fi firmware is downloaded as the official archive at commit
`d1491a6b3b22bd6d755bb71ca06aec4246127726`, verified before extraction. It is
not repacked locally with a host-dependent compression tool.
Official GitHub feed mirrors are pinned in `feeds.conf`; only packages needed by
the selected variant and their dependencies are installed to avoid unrelated
feed Kconfig cycles.

The image keeps country **`PA`** as requested, Asia/Kolkata timezone, and
HTTP-to-HTTPS LuCI redirection. It does **not** install the inherited shared root
password. On a clean installation, set your own password through LuCI or `passwd`;
a settings-preserving sysupgrade retains your existing credentials. Stock uses OpenWrt's
router network defaults; it does not apply the UniFi/AP conversion overlay.

## Local configuration check

Install the host dependencies listed in `.github/workflows/build.yml`, then:

```sh
DEVICE=6111 VARIANT=stock CHECK_ONLY=1 bash ./build.sh
```

This uses `openwrt.pin`. Set `OPENWRT_REF=main` to check current upstream instead.
`WORK` must name a new directory; the script refuses to delete existing work.
`JOBS` defaults to 2. A full build omits `CHECK_ONLY=1` and writes artifacts to
`out/6111/stock/`. Keep or move an earlier output directory before rebuilding.

Configuration checks are not firmware compilation. Hardware operation still
requires testing on an unlocked JIDU6111 with a known recovery method.

## Validation status

The patch series, wireless backports patches, JIDU6111 configuration, host
prerequisites and artifact-verifier tests have been checked. The firmware
installation recipes were exercised with the pinned runtime firmware and the
bundled board-data overlay. The generic board-data download and other CodeLinaro
sources could not be fetched in the restricted review environment; their pinned
revisions and checksum checks remain in place.

**A complete firmware build and on-device validation are still required before
calling this production-ready.** The cancelled GitHub run is not a successful
build. After compiling, validate the 6111 image and test boot, both radios,
Ethernet port mapping, DHCP/DNS, WAN routing, firewall behavior, batman-adv and
nft bridge operation, reboot persistence and recovery on the actual router.
