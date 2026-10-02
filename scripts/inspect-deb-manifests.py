#!/usr/bin/env python3
"""
Read the VM bundle and Claude CLI manifests compiled into a Claude Desktop .deb,
and optionally emit the preseed checksum manifest for scripts/build-offline-deb.sh.

    python3 scripts/inspect-deb-manifests.py  <package.deb>
    python3 scripts/inspect-deb-manifests.py  <package.deb> --emit amd64 > manifests/<ver>.amd64.preseed.sha256
    python3 scripts/inspect-deb-manifests.py  <package.deb> --emit amd64 --with-ssh   # 2.x layout

Standard library only. Tolerates both quoting styles the app's minifier has produced
(backticks in 1.30xxx, double/single quotes in 2.x) - this broke once already when the
major version changed, so the parsing is deliberately not tied to one style.

NOTE: every checksum reported here is over the COMPRESSED .zst artifact, which is what
the app verifies. Hashing the decompressed file gives a false mismatch.
"""
import argparse
import io
import json
import lzma
import re
import sys
import tarfile

ASAR_PATH = './usr/lib/claude-desktop/resources/app.asar'
Q = '[`"\']'          # any JS string delimiter the minifier may use
NQ = '[^`"\']'        # anything that is not one


def read_asar(deb_path):
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
        return tf.extractfile(tf.getmember(ASAR_PATH)).read().decode('latin-1')
    except KeyError:
        sys.exit(f'{ASAR_PATH} not found - package layout changed?')


def match_brace(s, i, open_c, close_c):
    """Return the index just past the bracket that closes the one at s[i]."""
    depth = 0
    for j in range(i, len(s)):
        c = s[j]
        if c == open_c:
            depth += 1
        elif c == close_c:
            depth -= 1
            if depth == 0:
                return j + 1
    return -1


def build_info(asar):
    m = re.search(r'\{"commitHash":"([0-9a-f]{40})","isNestBuild":\w+,"commitTimestamp":"([^"]*)",'
                  r'"buildType":"(\w+)","appVersion":"([\d.]+)"\}', asar)
    if not m:
        return None
    return dict(commit=m.group(1), built=m.group(2), type=m.group(3), version=m.group(4))


def vm_bundle(asar):
    """Newest (versions[0]) VM bundle: sha, date, and per-OS/arch file lists."""
    m = re.search(r'versions:\[\{sha:' + Q + r'([0-9a-f]{40})' + Q +
                  r',publishedAt:' + Q + r'([\d-]+)' + Q + r',files:', asar)
    if not m:
        return None
    fstart = m.end()
    fend = match_brace(asar, fstart, '{', '}')
    files = asar[fstart:fend]
    out = {'sha': m.group(1), 'published': m.group(2), 'files': {}}
    for osname in ('unix', 'win32'):
        om = re.search(osname + r':\{', files)
        if not om:
            continue
        ostart = om.end() - 1
        oblock = files[ostart:match_brace(files, ostart, '{', '}')]
        for arch in ('x64', 'arm64'):
            am = re.search(arch + r':\[', oblock)
            if not am:
                continue
            astart = am.end() - 1
            ablock = oblock[astart:match_brace(oblock, astart, '[', ']')]
            entries, pos = [], 1
            while True:
                b = ablock.find('{', pos)
                if b < 0:
                    break
                e = match_brace(ablock, b, '{', '}')
                obj = ablock[b:e]
                nm = re.match(r'\{name:' + Q + '(' + NQ + r'+)' + Q +
                              r',checksum:' + Q + r'([0-9a-f]{64})' + Q, obj)
                if nm:
                    sz = re.search(r',size:(\d+)', obj)
                    entries.append(dict(name=nm.group(1), checksum=nm.group(2),
                                        size=int(sz.group(1)) if sz else None))
                pos = e
            out['files'].setdefault(osname, {})[arch] = entries
    return out


def release_manifest(asar, marker):
    """Find the JSON.parse('{...}') literal whose baseUrl contains `marker`."""
    i = asar.find(marker)
    if i < 0:
        return None
    j = asar.rfind('JSON.parse(', 0, i)
    if j < 0:
        return None
    qpos = j + len('JSON.parse(')
    q = asar[qpos]
    start = qpos + 1
    end = asar.find(q + ')', i)
    if end < 0:
        return None
    try:
        return json.loads(asar[start:end])
    except Exception:
        return None


def emit(vm, cli, ssh, arch, with_ssh=False):
    """Print a preseed manifest for scripts/build-offline-deb.sh."""
    varch = 'x64' if arch == 'amd64' else 'arm64'
    cli_key = 'linux-x64' if arch == 'amd64' else 'linux-arm64'
    ssh_key = 'linux-amd64' if arch == 'amd64' else 'linux-arm64'
    for f in vm['files']['unix'][varch]:
        print(f'{f["checksum"]}  vm_bundle/{f["name"]}.zst')
    if cli:
        print(f'{cli["manifest"]["platforms"][cli_key]["checksum"]}  claude-code/{cli_key}.zst')
    if with_ssh and ssh and ssh_key in ssh['manifest']['platforms']:
        print(f'{ssh["manifest"]["platforms"][ssh_key]["checksum"]}  claude-ssh/{ssh_key}.zst')


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('deb')
    ap.add_argument('--emit', choices=['amd64', 'arm64'],
                    help='print a preseed checksum manifest for this architecture and exit')
    ap.add_argument('--with-ssh', action='store_true',
                    help='with --emit: also include claude-ssh (remote-SSH feature). The official '
                         '2.x offline installers ship it; the 1.30096.5 one did not.')
    a = ap.parse_args()

    # Windows Python would otherwise emit CRLF, which corrupts a redirected manifest:
    # sha256sum -c then reads the carriage return as part of every filename.
    sys.stdout.reconfigure(newline='\n')

    asar = read_asar(a.deb)
    bi = build_info(asar)
    vm = vm_bundle(asar)
    cli = release_manifest(asar, 'claude-code-releases')
    ssh = release_manifest(asar, 'claude-ssh-releases')

    if a.emit:
        if not vm:
            sys.exit('could not locate the VM bundle manifest - format changed again?')
        emit(vm, cli, ssh, a.emit, a.with_ssh)
        return

    print(f'app.asar: {len(asar):,} bytes\n')
    if bi:
        print('=== build ===')
        print(f'  appVersion  {bi["version"]}\n  commit      {bi["commit"]}\n'
              f'  built       {bi["built"]}\n  buildType   {bi["type"]}\n')

    print('=== VM bundle (versions[0] is what the app requires) ===')
    if not vm:
        print('  NOT FOUND - the manifest format changed; update this script.\n')
    else:
        print(f'  sha        {vm["sha"]}\n  published  {vm["published"]}')
        for osname, archs in vm['files'].items():
            for arch, files in archs.items():
                print(f'  {osname}/{arch}:')
                for f in files:
                    sz = f'{f["size"]:>14,}' if f['size'] else ' ' * 14
                    print(f'    {f["name"]:14s} {sz}  {f["checksum"]}')
        print('\n  URLs (browser User-Agent required or you get HTTP 403):')
        for arch in ('x64', 'arm64'):
            print(f'    https://downloads.claude.ai/vms/linux/{arch}/{vm["sha"]}/<name>.zst')
        print('  NOTE: checksums are over the COMPRESSED .zst artifacts.\n')

    for label, man in (('Claude CLI', cli), ('claude-ssh', ssh)):
        print(f'=== {label} ===')
        if not man:
            print('  not present in this build\n')
            continue
        print(f'  version  {man.get("version")}\n  baseUrl  {man.get("baseUrl")}')
        for k, p in sorted(man['manifest']['platforms'].items()):
            print(f'    {k:18s} {p.get("checksum")}  {p.get("size"):>12,}')
        print()


if __name__ == '__main__':
    main()
