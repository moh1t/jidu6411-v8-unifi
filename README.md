# Jio JIDU6111 / JIDU6411 OpenWrt snapshot builds

Build a standard OpenWrt router image for **JIDU6111** with
**`kmod-batman-adv` and `kmod-nft-bridge` built into the image**. The optional
`unifi` variant includes the existing openUF access-point integration.
Installing batman-adv does not configure a mesh: set up batman interfaces and
bridges after flashing, for your own network.

## Build locally

Build as an ordinary user inside Linux. Ubuntu 24.04 amd64 is the reference CI
host. The dependency installer also handles Ubuntu arm64, including Ubuntu
26.04 in Parallels on Apple Silicon. The full firmware build has not yet been
validated on that host. Python **3.11 or newer** is required by the artifact
verifier. Allow at least 60 GB of free disk space and 8 GB of RAM for a full build.

Install Git first, clone the repository, then install the dependencies selected
for your host architecture (only package installation needs sudo). Ubuntu's
`main` and `universe` repositories must be enabled:

```sh
sudo apt-get update
sudo apt-get install -y git ca-certificates
git clone --branch firmware/jidu6111-snapshot https://github.com/moh1t/jidu6411-v8-unifi.git
cd jidu6411-v8-unifi
bash scripts/install-build-deps.sh
python3 -m unittest discover -s tests -v
DEVICE=6111 VARIANT=stock JOBS=2 bash ./build.sh
```

Use `bash scripts/install-build-deps.sh --print` to inspect the package list
without installing anything. On **arm64**, `gcc-multilib` and `g++-multilib` are
omitted: Ubuntu does not publish those native packages for arm64, and they are
not needed to build this router's cross-toolchain. `build-essential` supplies the
native host compiler; OpenWrt builds the target compiler itself.

For a 16 GB Apple Silicon Mac, start with **8 GB RAM and 4 vCPUs** assigned to
the Ubuntu VM and keep **`JOBS=2`**. Build on the VM's Linux filesystem, such as
`~/src/`, not a Parallels shared macOS folder: OpenWrt requires case-sensitive
filenames and Unix filesystem semantics. Allow additional disk space for the
VM's operating system beyond the build's free-space requirement.

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

If an existing build stops on a checksum mismatch for
`ath11k-firmware-ipq9574-board-2026-03-24~2044a5b7.tar.zst`, apply patch 0007
once to that build tree. The generic board file is redundant: the required
`jidu6j11-board-data` package already installs the JIDU-specific board file.
From this repository directory, after obtaining the fix:

```sh
(
  set -e
  tree="$PWD/work-6111-stock/openwrt"
  fix="$PWD/patches/0007-ath11k-firmware-use-bundled-jidu-board-data.patch"
  git -C "$tree" apply --check "$fix"
  git -C "$tree" apply "$fix"
  sha256sum "$fix" >> work-6111-stock/build-provenance.txt
  make -C "$tree" package/firmware/ath11k-firmware/download -j1 V=s
  make -C "$tree" download -j2 || make -C "$tree" download -j1 V=s
  make -C "$tree" -j2 BUILD_LOG=1 || make -C "$tree" -j1 V=s BUILD_LOG=1
  python3 scripts/verify-images.py "$tree/bin/targets/qualcommbe/ipq95xx" 6111
)
```

This keeps existing downloads and build output; it does not regenerate `out/`.
Fresh builds apply patch 0007 automatically. Keep checksum verification enabled.

If image generation stops with `ERROR (duplicate_label)` for `q6_region`,
apply patch 0008 once to the existing build. The newer IPQ9574 SoC definition
already reserves Q6 memory; the inherited JIDU definition added a second node
at the same address. The fix reuses the SoC node and preserves JIDU's 45 MiB
reservation, `no-map` property and remoteproc memory reference.
From this repository directory, after obtaining the fix:

```sh
(
  set -e
  tree="$PWD/work-6111-stock/openwrt"
  fix="$PWD/patches/0008-qualcommbe-reuse-jidu-q6-memory-region.patch"
  git -C "$tree" apply --check "$fix"
  git -C "$tree" apply "$fix"
  sha256sum "$fix" >> work-6111-stock/build-provenance.txt
  bash scripts/check-device-trees.sh "$tree"
  make -C "$tree" -j2 BUILD_LOG=1 || make -C "$tree" -j1 V=s BUILD_LOG=1
  python3 scripts/verify-images.py "$tree/bin/targets/qualcommbe/ipq95xx" 6111
)
```

This checks both JIDU device trees using the kernel's existing device-tree
compiler, then resumes the build. Keep the work directory: no clean or fresh
toolchain build is needed. Images remain in the target's `bin` directory; these
commands do not regenerate `out/`. Fresh builds apply patch 0008 automatically.
Do not force device-tree output with `dtc -f` or disable the duplicate-label check.

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

The hardware patches here have been rebased onto the pinned upstream revision.
Patch 0006 fixes a redundant boolean kernel dependency that otherwise causes
a false dnsmasq-full Kconfig cycle on this snapshot. Patch 0007 removes the
redundant generic IPQ9574 board-data download; both device-specific board files
come from the bundled `jidu6j11-board-data` package, which is required in the
configuration and checked in each image's package manifest.
Patch 0008 merges the inherited JIDU Q6 memory reservation into the SoC node
introduced by the newer kernel patches, fixing device-tree compilation.
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

Install the host dependencies with `bash scripts/install-build-deps.sh`, then
use a separate work directory so the later full build can use its default path:

```sh
WORK="$PWD/work-check-6111-stock" DEVICE=6111 VARIANT=stock CHECK_ONLY=1 bash ./build.sh
```

This uses `openwrt.pin`. Set `OPENWRT_REF=main` to check current upstream instead.
`WORK` must name a new directory; the script refuses to delete existing work.
`JOBS` defaults to 2. A full build omits `CHECK_ONLY=1` and writes artifacts to
`out/6111/stock/`. Keep or move an earlier output directory before rebuilding.

Configuration checks are not firmware compilation. Hardware operation still
requires testing on an unlocked JIDU6111 with a known recovery method.

After the kernel has been prepared and its `scripts/dtc/dtc` built, check both
board definitions without rebuilding firmware:

```sh
bash scripts/check-device-trees.sh work-6111-stock/openwrt
```

An optional second argument selects a prepared kernel directory explicitly.
This check catches device-tree errors that `CHECK_ONLY=1` does not cover.

## Validation status

The patch series, wireless backports patches, JIDU6111 configuration, host
prerequisites and artifact-verifier tests have been checked. The firmware
installation recipes were exercised with the pinned runtime firmware and the
bundled board-data overlay. Removing the generic board archive produces the
same 30 installed firmware files/symlinks, including both JIDU board files.
The remaining shared CodeLinaro source could not be fetched in the restricted
review environment; its pinned revision and checksum checks remain in place.

The duplicate Q6-label failure was reproduced against Linux 6.18.55 with the
generic and qualcommbe kernel patches applied. With patch 0008, both JIDU6111
and JIDU6411 device trees compile using that kernel's own `dtc`. The compiled
trees were checked for a single 45 MiB Q6 reservation, `no-map`, the correct
remoteproc reference and the SKU-specific Wi-Fi calibration variants. The
full eight-patch series applies cleanly, and all nine image-verifier tests pass.

**A complete firmware build and on-device validation are still required before
calling this production-ready.** The cancelled GitHub run is not a successful
build. After compiling, validate the 6111 image and test boot, both radios,
Ethernet port mapping, DHCP/DNS, WAN routing, firewall behavior, batman-adv and
nft bridge operation, reboot persistence and recovery on the actual router.
