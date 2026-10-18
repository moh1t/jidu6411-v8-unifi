# Jio JIDU6111 / JIDU6411 OpenWrt snapshot builds

Build a standard OpenWrt router image for **JIDU6111** with
**`kmod-batman-adv` and `kmod-nft-bridge` built into the image**. The optional
`unifi` variant includes the existing openUF access-point integration.
Installing batman-adv does not configure a mesh: set up batman interfaces and
bridges after flashing, for your own network.

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

Pushing a branch named `firmware/**` also starts a full JIDU6111 stock build
from latest upstream `main`; other branch pushes do not start firmware builds.

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
`71194c985d8a97ea49fe42d9cebf6f739d729154` (2026-10-18, kernel 6.18.55).
You can also enter a full OpenWrt commit SHA. Future upstream changes can break
the hardware patches; the build stops rather than skipping them.

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
Official GitHub feed mirrors are pinned in `feeds.conf`; only packages needed by
the selected variant and their dependencies are installed to avoid unrelated
feed Kconfig cycles.

The inherited image defaults include country `PA`, Asia/Kolkata timezone,
HTTP-to-HTTPS LuCI redirection, and the v8 root-password default on first boot.
Set the wireless country to your actual location and change the root password
before putting a newly installed router into service. Stock uses OpenWrt's
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
