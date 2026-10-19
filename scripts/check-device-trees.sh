#!/bin/bash
# Compile both JIDU board definitions against a prepared OpenWrt kernel.
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
	echo "Usage: bash $0 OPENWRT_TREE [KERNEL_TREE]" >&2
	exit 1
fi
tree=$(cd "$1" && pwd)
if [ "$#" = 2 ]; then
	kernel=$(cd "$2" && pwd)
else
	shopt -s nullglob
	compilers=("$tree"/build_dir/target-*/linux-qualcommbe_ipq95xx/linux-*/scripts/dtc/dtc)
	if [ "${#compilers[@]}" != 1 ]; then
		echo 'Expected one prepared kernel with dtc; supply KERNEL_TREE explicitly.' >&2
		exit 1
	fi
	kernel=${compilers[0]%/scripts/dtc/dtc}
fi
dtc=${DTC:-$kernel/scripts/dtc/dtc}
if [ ! -x "$dtc" ]; then
	echo "Device-tree compiler is missing: $dtc" >&2
	exit 1
fi
dts="$tree/target/linux/qualcommbe/dts"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

for sku in 6111 6411; do
	# Use the same include paths and warning options as OpenWrt's image build.
	# Native cpp suffices: device-tree preprocessing has no target C code.
	"${CPP:-cpp}" -nostdinc -x assembler-with-cpp -undef -D__DTS__ \
		-I"$kernel/arch/arm64/boot/dts/qcom" \
		-I"$kernel/arch/arm64/boot/dts/qcom/include" \
		-I"$kernel/include" -I"$kernel/scripts/dtc/include-prefixes" \
		"$dts/ipq9554-jiorouter-ax6000-jidu6j11-$sku.dts" \
		-o "$tmp/$sku.dts"
	"$dtc" -O dtb -i "$dts" \
		-Wno-interrupt_provider -Wno-unique_unit_address \
		-Wno-unit_address_vs_reg -Wno-avoid_unnecessary_addr_size \
		-Wno-alias_paths -Wno-graph_child_address -Wno-simple_bus_reg \
		-o "$tmp/$sku.dtb" "$tmp/$sku.dts"
	echo "JIDU$sku: device-tree compilation passed"
done
