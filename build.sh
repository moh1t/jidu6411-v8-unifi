#!/bin/bash
# Default: standard OpenWrt router for JIDU6111, at the validated snapshot pin.
# OPENWRT_REF=main resolves the latest upstream snapshot at build time.
set -euo pipefail
umask 022

VARIANT="${VARIANT:-stock}"
DEVICE="${DEVICE:-6111}"
JOBS="${JOBS:-2}"
CHECK_ONLY="${CHECK_ONLY:-0}"
case "$VARIANT" in unifi|stock) ;; *) echo 'VARIANT must be unifi or stock' >&2; exit 1 ;; esac
case "$DEVICE" in 6111|6411|both) ;; *) echo 'DEVICE must be 6111, 6411 or both' >&2; exit 1 ;; esac
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || { echo 'JOBS must be a positive integer' >&2; exit 1; }
case "$CHECK_ONLY" in 0|1) ;; *) echo 'CHECK_ONLY must be 0 or 1' >&2; exit 1 ;; esac

HERE="$(cd "$(dirname "$0")" && pwd)"
REF="${OPENWRT_REF:-$(cat "$HERE/openwrt.pin")}"
[[ "$REF" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] || { echo 'Invalid OPENWRT_REF' >&2; exit 1; }
WORK="${WORK:-$HERE/work-$DEVICE-$VARIANT}"
OUT="$HERE/out/$DEVICE/$VARIANT"
# Never delete a caller's work directory. Use a fresh path for every build.
if [ -e "$WORK" ]; then
	echo "WORK already exists: $WORK; choose a new WORK directory" >&2
	exit 1
fi
mkdir -p "$WORK"
WORK="$(cd "$WORK" && pwd)"
exec > >(tee "$WORK/build.log") 2>&1

echo "==> OpenWrt $REF, JIDU$DEVICE, variant $VARIANT"
git init -q "$WORK/openwrt"
cd "$WORK/openwrt"
git fetch --depth=1 https://github.com/openwrt/openwrt.git "$REF"
git checkout -q FETCH_HEAD
BASE_COMMIT=$(git rev-parse HEAD)
printf '%s\n' "$BASE_COMMIT" > "$WORK/openwrt-base.commit"
# Fail on incompatible upstream changes; never silently skip a hardware patch.
git -c user.name=v8-build -c user.email=v8@build am -q "$HERE"/patches/*.patch
# Patch application can succeed even if a patch contains unresolved merges.
git diff --check "$BASE_COMMIT" HEAD
cp "$HERE/feeds.conf" feeds.conf
./scripts/feeds update -a
# Install the selected firmware's dependency closure. Unrelated feed packages
# can introduce Kconfig cycles even when they are not selected for an image.
./scripts/feeds install luci luci-ssl kmod-batman-adv
if [ "$VARIANT" = unifi ]; then
	./scripts/feeds install lua-cjson luasocket lua-openssl luabitop usteer
fi

cat "$HERE/configs/common.config" "$HERE/configs/$VARIANT.config" > .config
DEVICES="$DEVICE"
[ "$DEVICE" != both ] || DEVICES='6111 6411'
for sku in $DEVICES; do
	printf 'CONFIG_TARGET_DEVICE_qualcommbe_ipq95xx_DEVICE_jiorouter_ax6000-jidu6j11-%s=y\n' "$sku" >> .config
	printf 'CONFIG_TARGET_DEVICE_PACKAGES_qualcommbe_ipq95xx_DEVICE_jiorouter_ax6000-jidu6j11-%s="-wpad-basic-mbedtls"\n' "$sku" >> .config
done
make -j"$JOBS" defconfig 2>&1 | tee "$WORK/defconfig.log"
if grep -Eiq 'error:|recursive dependency detected' "$WORK/defconfig.log"; then
	echo 'Kconfig reported errors despite completing defconfig' >&2
	exit 1
fi
need() { grep -qxF "$1" .config || { echo "MISSING after defconfig: $1" >&2; exit 1; }; }
for sku in $DEVICES; do
	need "CONFIG_TARGET_DEVICE_qualcommbe_ipq95xx_DEVICE_jiorouter_ax6000-jidu6j11-$sku=y"
done
for pkg in kmod-batman-adv kmod-nft-bridge kmod-sched-act-police luci-ssl wpad-mbedtls jidu6j11-board-data ath11k-firmware-ipq9574 ath11k-firmware-qcn9074; do
	need "CONFIG_PACKAGE_$pkg=y"
done
if [ "$VARIANT" = unifi ]; then
	for pkg in lua lua-cjson luasocket lua-openssl luabitop libuci-lua tc-tiny; do need "CONFIG_PACKAGE_$pkg=y"; done
fi
make -j"$JOBS" prereq
{
	printf 'upstream=%s\nrequested_ref=%s\nvariant=%s\ndevice=%s\n' "$BASE_COMMIT" "$REF" "$VARIANT" "$DEVICE"
	printf 'buildkit=%s\n' "$(git -C "$HERE" rev-parse HEAD)"
	git -C "$HERE" diff --quiet || printf 'buildkit_dirty=true\n'
	./scripts/feeds list -s
	sha256sum "$HERE"/patches/*.patch "$HERE"/configs/*.config
} > "$WORK/build-provenance.txt"
if [ "$CHECK_ONLY" = 1 ]; then
	echo '==> CHECK_ONLY: defconfig and prerequisites OK (no firmware compiled)'
	exit 0
fi

mkdir -p files
cp -a "$HERE/files/common/." files/
cp -a "$HERE/files/$VARIANT/." files/
find files -name .keep -delete
# Validate and download the hardware firmware before the expensive toolchain build.
make package/firmware/ath11k-firmware/download -j1 V=s
make download -j"$JOBS" || make download -j1 V=s
make -j"$JOBS" BUILD_LOG=1 || make -j1 V=s BUILD_LOG=1

T=bin/targets/qualcommbe/ipq95xx
python3 "$HERE/scripts/verify-images.py" "$T" $DEVICES
# A fresh output prevents stale images from being mistaken for this build.
[ ! -e "$OUT" ] || { echo "Output already exists: $OUT; preserve or move it before retrying" >&2; exit 1; }
mkdir -p "$OUT"
for sku in $DEVICES; do cp -a "$T"/*jidu6j11-"$sku"* "$OUT"/; done
cp "$T/profiles.json" "$WORK/build-provenance.txt" "$OUT"/
cp .config "$OUT/build.config"
for f in "$T"/*.buildinfo; do [ ! -f "$f" ] || cp "$f" "$OUT"/; done
if [ -d "$T/packages" ]; then tar -C "$T" -czf "$OUT/packages-$VARIANT.tar.gz" packages; fi
# Keep original filenames so profiles.json and image hashes remain valid.
python3 - "$OUT" <<'PY'
import hashlib
from pathlib import Path
import sys
root = Path(sys.argv[1])
with (root / 'SHA256SUMS').open('w') as out:
    for path in sorted(root.iterdir()):
        if path.is_file() and path.name != 'SHA256SUMS':
            with path.open('rb') as src:
                digest = hashlib.file_digest(src, 'sha256').hexdigest()
            out.write(f'{digest}  {path.name}\n')
PY
ls -lh "$OUT"
