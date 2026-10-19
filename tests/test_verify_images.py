import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('verify_images', Path(__file__).resolve().parents[1] / 'scripts/verify-images.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class FirmwareValidationTests(unittest.TestCase):
    packages = [
        'kmod-batman-adv', 'kmod-nft-bridge', 'jidu6j11-board-data',
        'kmod-ath11k', 'kmod-ath11k-ahb', 'kmod-ath11k-pci',
        'ath11k-firmware-ipq9574', 'ath11k-firmware-qcn9074',
    ]

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.profile_id = 'jiorouter_ax6000-jidu6j11-6111'
        self.name = f'openwrt-qualcommbe-ipq95xx-{self.profile_id}-squashfs-sysupgrade.bin'
        self.image = self.root / self.name
        self.image.write_bytes(b'test firmware artifact')
        self.profile = {
            'supported_devices': ['jiorouter,ax6000-jidu6j11-6111'],
            'images': [{'type': 'sysupgrade', 'name': self.name,
                        'sha256': hashlib.sha256(self.image.read_bytes()).hexdigest()}],
        }
        self.manifest = self.root / f'openwrt-{self.profile_id}.manifest'
        self.manifest.write_text(''.join(f'{p} - 1\n' for p in self.packages))
        self.save_profiles()

    def save_profiles(self):
        (self.root / 'profiles.json').write_text(json.dumps({'profiles': {self.profile_id: self.profile}}))

    def verify(self):
        with contextlib.redirect_stdout(io.StringIO()):
            module.verify(self.root, ['6111'])

    def test_valid_image(self):
        self.verify()

    def test_wrong_device_rejected(self):
        self.profile['supported_devices'] = ['jiorouter,ax6000-jidu6j11-6411']
        self.save_profiles()
        with self.assertRaisesRegex(ValueError, 'missing supported device'):
            self.verify()

    def test_each_required_package_must_be_in_image(self):
        for package in self.packages:
            with self.subTest(package=package):
                self.manifest.write_text('\n'.join(f'{p} - 1' for p in self.packages if p != package))
                with self.assertRaisesRegex(ValueError, 'missing packages'):
                    self.verify()

    def test_corrupt_image_rejected(self):
        self.image.write_bytes(b'corrupted')
        with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
            self.verify()

    def test_absent_sysupgrade_rejected(self):
        self.profile['images'] = []
        self.save_profiles()
        with self.assertRaisesRegex(ValueError, 'no sysupgrade image'):
            self.verify()

    def test_missing_image_rejected(self):
        self.image.unlink()
        with self.assertRaises(FileNotFoundError):
            self.verify()

    def test_empty_image_rejected_even_with_matching_checksum(self):
        self.image.write_bytes(b'')
        self.profile['images'][0]['sha256'] = hashlib.sha256(b'').hexdigest()
        self.save_profiles()
        with self.assertRaisesRegex(ValueError, 'empty image'):
            self.verify()

    def test_duplicate_manifest_rejected(self):
        (self.root / f'duplicate-{self.profile_id}.manifest').write_text(self.manifest.read_text())
        with self.assertRaisesRegex(ValueError, 'exactly one per-device manifest'):
            self.verify()

    def test_wrong_sku_image_filename_rejected(self):
        self.profile['images'][0]['name'] = self.name.replace('6111', '6411')
        self.save_profiles()
        with self.assertRaisesRegex(ValueError, 'unexpected image filename'):
            self.verify()


if __name__ == '__main__':
    unittest.main()
