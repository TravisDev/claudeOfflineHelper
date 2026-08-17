# Windows

**Windows is the recommended platform for this deployment.** It is the only one where
Claude Desktop runs with zero egress to Anthropic, because the offline installer variant
exists for Windows and does not exist for Linux.

Full detail: [../docs/05-WINDOWS-INSTALL.md](../docs/05-WINDOWS-INSTALL.md)

---

## Files here

| File | Purpose |
|---|---|
| `Install-Claude.ps1` | Installs the MSIX after verifying checksum, OS build, S Mode, virtualization, and managed config |
| `Make-Portable.ps1` | Extracts a portable tree — **read the limitations, Cowork will not work** |
| `config/bedrock-sso.reg` | Bedrock via AWS SSO / IAM Identity Center |
| `config/bedrock-profile.reg` | Bedrock via a named AWS profile |
| `config/bedrock-lockeddown.reg` | Zero-Anthropic-egress profile |

The MSIX itself is a release asset, not in git.

---

## Install, in order

**1. Configuration first.** Edit a `.reg` for your region and account, then as
Administrator:

```powershell
reg import .\config\bedrock-sso.reg
```

Configuring after installing means users hit the claude.ai sign-in screen — the exact
screen your network blocks.

**2. Then the app.**

```powershell
Expand-Archive .\Claude-1.30096.5-x64-offline.msix.zip -DestinationPath .
.\Install-Claude.ps1 -MsixPath .\Claude-1.30096.5-x64-offline.msix
```

**3. Verify.** Launch Claude → **Help → Troubleshooting → Copy Managed Configuration
Report**. It shows which keys were read and whether the Bedrock credentials validated.

---

## Get the *offline* package, not the standard one

| Package | Size | Behaviour |
|---|---|---|
| `Claude-1.30096.5-x64-offline.msix` | 1.80 GB | VM bundle + CLI built in. **No Anthropic egress.** |
| Standard MSIX | 267 MB | Downloads both from `downloads.claude.ai` at session start |
| `Claude Setup.exe` | 6.9 MB | A bootstrapper with no payload. Useless offline. |

Check which one you have:

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
$z = [IO.Compression.ZipFile]::OpenRead((Resolve-Path .\Claude-1.30096.5-x64-offline.msix))
$z.Entries | Where-Object FullName -like '*preseed/vm_bundle/rootfs.vhdx.zst' | Select-Object FullName
$z.Dispose()
```

A match means you have the offline build.

Arm64 offline is not staged here:
`https://claude.ai/api/desktop/win32/arm64/offline/latest/redirect`

---

## Requirements

Windows 10 build 19041+ or Windows 11 · x64 or Arm64 · hardware virtualization enabled ·
S Mode off · current root certificate store.

Test a machine before rolling out, without installing anything:

```
https://claude.ai/api/desktop/win32/x64/cowork-readiness-check/latest/redirect
```

---

## About "portable"

A portable extraction cannot run Cowork or Code. Those features run their sandbox through
`CoworkVMService`, a Windows service the MSIX manifest registers to run as `localSystem`,
triggered on the named pipe `\pipe\cowork-vm-service`. A copied folder cannot register a
service or hold the package's restricted capabilities.

What you probably want instead — **MSIX installs into the user profile and normally needs
no admin rights**:

```powershell
Add-AppxPackage -Path .\Claude-1.30096.5-x64-offline.msix
Get-AppxPackage -Name Claude | Remove-AppxPackage   # clean, complete removal
```

Nothing lands in `Program Files`, and it is fully reversible. Test whether it prompts for
elevation on one of your machines before planning a rollout around it — this package
registers a service and firewall rules, which ordinary MSIX packages do not.

The reasoning in full: [../docs/05-WINDOWS-INSTALL.md](../docs/05-WINDOWS-INSTALL.md#is-a-portable-installer-possible)
