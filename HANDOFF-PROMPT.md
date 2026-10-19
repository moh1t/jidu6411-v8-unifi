# Current project handoff

The owner of `moh1t/jidu6411-v8-unifi` is building a **standard OpenWrt router
image for JIDU6111**, with `kmod-batman-adv` and `kmod-nft-bridge`. The working
branch is `firmware/jidu6111-snapshot`. Country **PA** was explicitly retained.
The UniFi variant is optional and is not the requested firmware.

The owner cancelled the GitHub build and will compile on another machine.
GitHub Actions is manual-only; do not dispatch a workflow unless requested.
Read README.md for local build commands, source pins and validation limits.

The first failed workflow exposed unresolved conflict markers in the ath11k
firmware patch. The repository now checks applied patches before feed setup,
uses a checksum-verified official archive for legacy firmware, keeps per-package
build logs and validates required driver/firmware packages in each image.
The inherited shared root-password hash has been removed.

Configuration and package checks are not a complete firmware compile or a
hardware test. Do not describe the firmware as production-ready until the
full build and JIDU6111 acceptance checks in README.md have passed. Preserve
checksum verification and the selected hardware-support stack when fixing
subsequent build issues.
