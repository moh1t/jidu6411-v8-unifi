#!/usr/bin/env python3
"""Reject missing/wrong-device firmware or images missing either requested kmod."""
import hashlib
import json
from pathlib import Path
import sys


def verify(root, devices):
    profiles = json.loads((root / 'profiles.json').read_text())['profiles']
    for device in devices:
        profile_id = f'jiorouter_ax6000-jidu6j11-{device}'
        profile = profiles[profile_id]
        supported = f'jiorouter,ax6000-jidu6j11-{device}'
        if supported not in profile['supported_devices']:
            raise ValueError(f'{profile_id}: missing supported device {supported}')
        manifests = list(root.glob(f'*{profile_id}*.manifest'))
        if len(manifests) != 1:
            raise ValueError(f'{profile_id}: expected exactly one per-device manifest')
        packages = {line.split()[0] for line in manifests[0].read_text().splitlines() if line.strip()}
        missing = {'kmod-batman-adv', 'kmod-nft-bridge', 'jidu6j11-board-data'} - packages
        if missing:
            raise ValueError(f'{profile_id}: missing packages: {sorted(missing)}')
        images = [item for item in profile['images'] if item['type'] == 'sysupgrade']
        if not images:
            raise ValueError(f'{profile_id}: no sysupgrade image')
        for item in images:
            image = root / item['name']
            if image.name != item['name'] or profile_id not in image.name:
                raise ValueError(f'{profile_id}: unexpected image filename')
            with image.open('rb') as src:
                digest = hashlib.file_digest(src, 'sha256').hexdigest()
            if image.stat().st_size == 0 or digest != item['sha256']:
                raise ValueError(f'{image.name}: empty image or checksum mismatch')
        print(f'{profile_id}: sysupgrade checksum, supported device and required packages OK')


if __name__ == '__main__':
    if len(sys.argv) < 3 or any(d not in {'6111', '6411'} for d in sys.argv[2:]):
        sys.exit('Usage: verify-images.py TARGET_DIRECTORY 6111 [6411]')
    verify(Path(sys.argv[1]), sys.argv[2:])
