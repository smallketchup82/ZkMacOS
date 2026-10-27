"""Exercise real Sparkle signatures and GitHub feed metadata with disposable keys."""
from pathlib import Path
import base64
import importlib.util
import plistlib
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PrivateFormat, PublicFormat, NoEncryption

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('appcast', root / 'scripts/generate-appcast.py')
appcast = importlib.util.module_from_spec(spec)
spec.loader.exec_module(appcast)


class AppcastChecks(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.key = Ed25519PrivateKey.generate()
        self.secret = base64.b64encode(self.key.private_bytes(Encoding.Raw, PrivateFormat.Raw, NoEncryption())).decode()
        self.info = {
            'CFBundleVersion': '123', 'CFBundleShortVersionString': '202610.28.0',
            'LSMinimumSystemVersion': '26.0',
            'SUPublicEDKey': base64.b64encode(self.key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)).decode(),
        }
        self.plist = self.directory / 'Zero-K.app/Contents/Info.plist'
        self.plist.parent.mkdir(parents=True)
        self.plist.write_bytes(plistlib.dumps(self.info))
        (self.directory / appcast.ASSET).write_bytes(b'Disposable update fixture')
        self.tool = root / '.cache/sparkle-2.10.1/bin/sign_update'

    def generate(self):
        return appcast.generate_appcast(self.directory, self.tool, self.secret, 'smallketchup82/ZkMacOS')

    def test_signed_feed_and_exact_release_asset(self):
        feed = self.generate()
        item = ET.parse(feed).find('channel/item')
        self.assertEqual(item.find('{' + appcast.SPARKLE + '}version').text, '123')
        self.assertEqual(item.find('{' + appcast.SPARKLE + '}minimumSystemVersion').text, '26.0')
        enclosure = item.find('enclosure')
        self.assertEqual(enclosure.get('url'), 'https://github.com/smallketchup82/ZkMacOS/releases/download/202610.28.0/' + appcast.ASSET)
        dmg = (self.directory / appcast.ASSET).read_bytes()
        self.assertEqual(int(enclosure.get('length')), len(dmg))
        signature = base64.b64decode(enclosure.get('{' + appcast.SPARKLE + '}edSignature'))
        self.key.public_key().verify(signature, dmg)
        with self.assertRaises(InvalidSignature):
            self.key.public_key().verify(signature, dmg + b'tampered')
        feed.write_bytes(feed.read_bytes().replace(b'ZkMacOS Updates', b'Tampered Updates'))
        result = subprocess.run([str(self.tool), '--ed-key-file', '-', '--verify', str(feed)],
                                input=self.secret, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0, 'Tampering with a signed feed must fail verification')

    def test_wrong_signing_key_does_not_publish_a_feed(self):
        self.info['SUPublicEDKey'] = base64.b64encode(bytes(32)).decode()
        self.plist.write_bytes(plistlib.dumps(self.info))
        with self.assertRaisesRegex(ValueError, 'does not match'):
            self.generate()
        self.assertFalse((self.directory / 'appcast.xml').exists())

    def test_invalid_key_and_development_version_are_rejected(self):
        for key in ('invalid', base64.b64encode(bytes(31)).decode(),
                    base64.b64encode(bytes(64)).decode()):
            self.secret = key
            with self.assertRaises(ValueError):
                self.generate()
        self.info['CFBundleShortVersionString'] = '0.1.0'
        self.plist.write_bytes(plistlib.dumps(self.info))
        with self.assertRaisesRegex(ValueError, 'CalVer'):
            self.generate()


if __name__ == '__main__':
    unittest.main()
