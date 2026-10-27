# /// script
# requires-python = ">=3.11"
# dependencies = ["cryptography==46.0.3"]
# ///
"""Sign a release DMG and appcast, hosted together as GitHub release assets."""
from pathlib import Path
import base64
import os
import plistlib
import re
import subprocess
import xml.etree.ElementTree as ET

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

ROOT = Path(__file__).resolve().parents[1]
SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', SPARKLE)
ASSET = 'Zero-K-macOS-arm64.dmg'


def generate_appcast(directory, tool, private_key, repository):
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository):
        raise ValueError('Expected a GitHub owner/repository.')
    info = plistlib.loads((directory / 'Zero-K.app/Contents/Info.plist').read_bytes())
    version = info['CFBundleShortVersionString']
    if not re.fullmatch(r'[0-9]{6}\.[0-9]{2}\.[0-9]+', version):
        raise ValueError('Expected a release CalVer in the packaged application.')
    # Current generate_keys exports a base64-encoded Ed25519 seed.
    key = base64.b64decode(private_key.strip(), validate=True)
    if len(key) != 32:
        raise ValueError('Expected a 32-byte private seed exported by Sparkle generate_keys.')
    signing_key = Ed25519PrivateKey.from_private_bytes(key)
    public = signing_key.public_key()
    expected = base64.b64decode(info['SUPublicEDKey'], validate=True)
    if public.public_bytes(Encoding.Raw, PublicFormat.Raw) != expected:
        raise ValueError('Signing key does not match the public key in the packaged app.')
    dmg = directory / ASSET
    # Pass the secret through stdin, never command-line arguments or log output.
    signature = subprocess.check_output(
        [str(tool), '--ed-key-file', '-', '-p', str(dmg)],
        input=private_key.strip(), text=True).strip()
    public.verify(base64.b64decode(signature, validate=True), dmg.read_bytes())
    rss = ET.Element('rss', {'version': '2.0'})
    channel = ET.SubElement(rss, 'channel')
    ET.SubElement(channel, 'title').text = 'ZkMacOS Updates'
    ET.SubElement(channel, 'link').text = f'https://github.com/{repository}/releases'
    ET.SubElement(channel, 'description').text = 'Stable ZkMacOS releases for Apple Silicon.'
    item = ET.SubElement(channel, 'item')
    ET.SubElement(item, 'title').text = 'ZkMacOS ' + version
    ET.SubElement(item, 'link').text = f'https://github.com/{repository}/releases/tag/{version}'
    for name, value in (('version', info['CFBundleVersion']), ('shortVersionString', version),
                        ('minimumSystemVersion', info['LSMinimumSystemVersion'])):
        ET.SubElement(item, '{' + SPARKLE + '}' + name).text = str(value)
    ET.SubElement(item, 'enclosure', {
        'url': f'https://github.com/{repository}/releases/download/{version}/{ASSET}',
        'length': str(dmg.stat().st_size), 'type': 'application/octet-stream',
        '{' + SPARKLE + '}edSignature': signature,
    })
    feed = directory / 'appcast.xml'
    ET.indent(rss)
    ET.ElementTree(rss).write(feed, encoding='utf-8', xml_declaration=True)
    subprocess.run([str(tool), '--ed-key-file', '-', str(feed)],
                   input=private_key.strip(), text=True, check=True)
    subprocess.run([str(tool), '--ed-key-file', '-', '--verify', str(feed)],
                   input=private_key.strip(), text=True, check=True)
    print('Signed release DMG and appcast for ' + version)
    return feed


if __name__ == '__main__':
    generate_appcast(ROOT / 'dist', ROOT / '.cache/sparkle-2.10.1/bin/sign_update',
                     os.environ['SPARKLE_PRIVATE_ED_KEY'],
                     os.environ.get('GITHUB_REPOSITORY', 'smallketchup82/ZkMacOS'))
