# 01 — Quickstart

The shortest path from this repo to a working Claude Desktop on Bedrock, on a network
that blocks Anthropic.

---

## Step 0: pick your package

Anthropic publishes offline installers — the builds with the VM workspace bundle and
Claude CLI baked in — for **Windows and macOS only**. Linux has no official one, but the
Linux app supports the same mechanism, so this repo builds one.

| If your target is | Use |
|---|---|
| Windows | `Claude-1.30096.5-x64-offline.msix`. Official, supported, zero Anthropic egress. **Best option.** |
| Linux, and `downloads.claude.ai` **can** be allowlisted | The stock `.deb`. Supported, no maintenance burden. |
| Linux, and `downloads.claude.ai` **cannot** be allowlisted | `claude-desktop_1.30096.5+offline1_amd64.deb`, built by this repo. Works, but unsupported — read [doc 11](11-BUILD-OFFLINE-DEB.md) first. |
| Headless or SSH-only | [Claude Code CLI](10-CLAUDE-CODE-CLI-BEDROCK.md). |

Do not stage the **standard** Windows MSIX (267 MB) for an offline network — it fetches
its VM bundle at session start just like the stock `.deb`.

---

## Step 1: get the files

Release page:
**https://github.com/TravisDev/claudeOfflineHelper/releases/tag/v1.30096.5**

The repository is **private**, so downloads need authentication:

```bash
gh auth login --hostname github.com --git-protocol https --web
gh release download v1.30096.5 --repo TravisDev/claudeOfflineHelper --pattern "*.zip"
```

That pulls all four assets (3.69 GB). Grab just the one you need instead:

```bash
# Linux amd64, air-gapped (1.57 GB)
gh release download v1.30096.5 --repo TravisDev/claudeOfflineHelper   --pattern "claude-desktop_1.30096.5+offline1_amd64.deb.zip"

# Windows x64 (1.80 GB)
gh release download v1.30096.5 --repo TravisDev/claudeOfflineHelper   --pattern "Claude-1.30096.5-x64-offline.msix.zip"
```

No `gh` on the target? Download from the release page in a browser while signed in to
GitHub. Plain `curl`/`wget` on the asset URL returns 404 without a token — private-repo
assets are not publicly fetchable, and that 404 looks like a broken link when it is
actually an auth failure.

Then unzip:

```bash
unzip Claude-1.30096.5-x64-offline.msix.zip
```

```powershell
Expand-Archive .\Claude-1.30096.5-x64-offline.msix.zip -DestinationPath .
```

Verify the checksum against [CHECKSUMS.md](../CHECKSUMS.md) before going further.

---

## Step 2: put the configuration in place *before* the app

Deploy configuration first, then install. If the app launches once with no config, it
shows the claude.ai sign-in screen — which is exactly the screen your network blocks.

### Windows

Edit `windows/config/bedrock-sso.reg` (or `bedrock-profile.reg`) to your region and
account, then apply it as Administrator:

```powershell
reg import .\windows\config\bedrock-sso.reg
```

That writes `HKLM\SOFTWARE\Policies\Claude`. In a fleet, push the same values through
Group Policy or Intune instead.

### Linux

```bash
sudo mkdir -p /etc/claude-desktop
sudo cp linux/config/managed-settings.json /etc/claude-desktop/managed-settings.json
sudo chmod 644 /etc/claude-desktop/managed-settings.json
```

Edit the region, profile, and model list first. Full key reference:
[03 — Bedrock configuration](03-BEDROCK-CONFIG.md).

---

## Step 3: install

### Windows

```powershell
.\windows\Install-Claude.ps1 -MsixPath .\Claude-1.30096.5-x64-offline.msix
```

Or directly:

```powershell
Add-AppxPackage -Path .\Claude-1.30096.5-x64-offline.msix
```

Requirements: Windows 10 build 19041+ or Windows 11, x64 or Arm64, hardware
virtualization enabled, S Mode off, and a current certificate store (the package is
signed by `Anthropic, PBC` through DigiCert).

### Linux

```bash
cd linux && chmod +x install.sh && ./install.sh
```

Or `sudo apt install ./claude-desktop_1.30096.5_amd64.deb`. Note that apt resolves this
package's dependencies from **your distro's** archives, not Anthropic's — see
[07 — Air-gapped Linux deps](07-AIRGAP-LINUX-DEPS.md) if the machine has no archive
access either.

---

## Step 4: verify

Launch Claude. You should land in the third-party deployment, **not** the claude.ai
sign-in screen.

Then confirm the config was actually read:

> **Help → Troubleshooting → Copy Managed Configuration Report**

It shows which keys were detected, where they came from (managed profile vs. user
store), and whether the Bedrock credentials validated. Secrets are redacted.

Also open **Developer → Configure Third-Party Inference…** — on a properly managed
device it opens **read-only**. If it is editable on Linux/macOS, no recognized key
reached the app.

If you see the claude.ai sign-in screen instead, jump to
[08 — Troubleshooting](08-TROUBLESHOOTING.md).

---

## Step 5: hand the firewall team the allowlist

For a locked-down Windows deployment using the offline installer, the entire required
allowlist is:

```
bedrock-runtime.<your-region>.amazonaws.com
bedrock.<your-region>.amazonaws.com
```

Plus AWS SSO hosts if you use SSO auth. That is the whole list — no Anthropic hosts.
The full table, including what each optional feature adds back:
[02 — Network and egress](02-NETWORK-EGRESS.md).
