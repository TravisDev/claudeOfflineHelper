#!/usr/bin/env python3
"""
Read the VM bundle and Claude CLI manifests compiled into a Claude Desktop .deb.

Use this when a new version ships, to learn which preseed components that build
expects before rebuilding an offline package.

    python3 scripts/inspect-deb-manifests.py linux/claude-desktop_1.30096.5_amd64.deb

Needs only the standard library. Prints the bundle sha, per-arch file checksums,
the download URLs, and the Claude CLI version and checksums.
"""
import io
import json
import lzma
import re
import sys
import tarfile

ASAR_PATH = './usr/lib/claude-desktop/resources/app.asar'


def read_asar(deb_path):
    """Pull resources/app.asar out of a .deb (ar archive -> data.tar.xz -> member)."""
    with open(deb_path, 'rb') as f:
        if f.read(8) != b'!<arch>\n':
            sys.exit(f'{deb_path}: not a Debian package')
        data = None
        while True:
            hdr = f.read(60)
            if len(hdr) < 60:
                break
            name = hdr[0:16].decode(errors='replace').strip()
            size = int(hdr[48:58].decode().strip())
            if name.startswith('data.tar'):
                if not name.endswith('.xz'):
                    sys.exit(f'unsupported compression: {name}')
                data = f.read(size)
                break
            f.seek(size + (size % 2), 1)
    if data is None:
        sys.exit('no data.tar.xz member found')

    tf = tarfile.open(fileobj=io.BytesIO(lzma.decompress(data)))
    try:
        member = tf.getmember(ASAR_PATH)
    except KeyError:
        sys.exit(f'{ASAR_PATH} not found - package layout changed?')
    return tf.extractfile(member).read()


def find_json_after(blob, marker, opener=b'{'):
    """Find a balanced JSON object appearing near `marker`."""
    i = blob.find(marker)
    if i < 0:
        return None
    start = blob.rfind(b'JSON.parse(`', max(0, i - 6000), i)
    if start < 0:
        return None
    start += len(b'JSON.parse(`')
    end = blob.find(b'`)', start)
    if end < 0:
        return None
    try:
        return json.loads(blob[start:end].decode())
    except Exception:
        return None


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    blob = read_asar(sys.argv[1])
    print(f'app.asar: {len(blob):,} bytes\n')

    # --- build identity ---
    build = find_json_after(blob, b'"appVersion"')
    if build:
        print('=== build ===')
        for k in ('appVersion', 'commitHash', 'commitTimestamp', 'buildType'):
            if k in build:
                print(f'  {k:18s} {build[k]}')
        print()

    # --- VM bundle: versions[0] is the active one ---
    print('=== VM bundle (versions[0] is what the app requires) ===')
    m = re.search(rb'versions:\[\{sha:`([0-9a-f]{40})`,publishedAt:`([\d-]+)`', blob)
    if not m:
        print('  could not locate vmBundleManifest - format changed?\n')
    else:
        sha, published = m.group(1).decode(), m.group(2).decode()
        print(f'  sha        {sha}')
        print(f'  published  {published}')

        # slice out just this version entry and read its file lists
        seg = blob[m.start():m.start() + 4000].decode('latin-1')
        for plat in ('unix', 'win32'):
            pm = re.search(plat + r':\{(.*?)\}\}', seg, re.S)
            if not pm:
                continue
            print(f'  {plat}:')
            for am in re.finditer(r'(arm64|x64):\[(.*?)\]', pm.group(1), re.S):
                arch, files = am.group(1), am.group(2)
                print(f'    {arch}:')
                for fm in re.finditer(r'name:`([^`]+)`,checksum:`([0-9a-f]{64})`', files):
                    print(f'      {fm.group(1):16s} {fm.group(2)}')
        print()
        print('  download URLs (add a browser User-Agent or you get HTTP 403):')
        for arch in ('x64', 'arm64'):
            print(f'    https://downloads.claude.ai/vms/linux/{arch}/{sha}/<file>.zst')
        print('  NOTE: checksums are over the COMPRESSED .zst artifacts.\n')

    # --- Claude CLI ---
    print('=== Claude CLI ===')
    cli = find_json_after(blob, b'claude-code-releases')
    if not cli:
        print('  could not locate the claude-code manifest')
    else:
        print(f'  version   {cli.get("version")}')
        print(f'  baseUrl   {cli.get("baseUrl")}')
        plats = cli.get('manifest', {}).get('platforms', {})
        for name in sorted(plats):
            p = plats[name]
            print(f'    {name:18s} {p.get("checksum")}  {p.get("size"):>12,}')
        print()
        print('  preseed file name is <platform>.zst, e.g. preseed/claude-code/linux-x64.zst')


if __name__ == '__main__':
    main()
