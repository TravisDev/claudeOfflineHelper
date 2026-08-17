# 05 — Windows install

Including a direct answer to the portable-installer question.

---

## Use the offline MSIX

| | |
|---|---|
| File | `Claude-1.30096.5-x64-offline.msix` |
| Size | 1.80 GB |
| SHA256 | `c2ae7281a3d10e74abfdd430359da813ada90fd5b9eefb0db2212e574ac0895a` |
| Arm64 | Not staged here — `https://claude.ai/api/desktop/win32/arm64/offline/latest/redirect` |

This package contains the VM workspace bundle and Claude CLI, so **sessions start with
no connection to Anthropic**. Confirmed by inspecting its contents:

```
app/resources/preseed/vm_bundle/rootfs.vhdx.zst        1274 MB
app/resources/preseed/vm_bundle/initrd.zst               71 MB
app/resources/preseed/vm_bundle/vmlinuz.zst              14 MB
app/resources/preseed/claude-code/win32-x64/claude.exe  293 MB
app/resources/preseed/claude-code/win32-x64.zst          68 MB
app/resources/preseed/claude-code/linux-x64.zst          65 MB
```

The standard MSIX (267 MB) has none of these — only a 36 MB `smol-bin.x64.vhdx` — and
downloads them from `downloads.claude.ai` at session start. **Do not stage the standard
MSIX for an offline network.**

---

## Requirements

| Requirement | Value |
|---|---|
| OS | Windows 10 build 19041 (version 2004) or later, or Windows 11 |
| CPU | x64 or Arm64 |
| Virtualization | Hardware virtualization enabled in firmware — Cowork requires it |
| S Mode | Must be off |
| Certificates | Current root store; the package is signed by `Anthropic, PBC` via DigiCert |

Check a machine before rolling out, with Anthropic's standalone readiness checker (no
install, no sign-in):

```
https://claude.ai/api/desktop/win32/x64/cowork-readiness-check/latest/redirect
https://claude.ai/api/desktop/win32/arm64/cowork-readiness-check/latest/redirect
```

A ready device reports **This computer is ready for Cowork**. Run it on one device of
each hardware model before a fleet rollout.

---

## Install

Configuration first (see [03 — Bedrock configuration](03-BEDROCK-CONFIG.md)), then:

```powershell
.\Install-Claude.ps1 -MsixPath .\Claude-1.30096.5-x64-offline.msix
```

The script verifies the SHA256, checks S Mode and the Windows build, and refuses to
proceed on a mismatch. Or do it by hand:

```powershell
Add-AppxPackage -Path .\Claude-1.30096.5-x64-offline.msix
```

For machine-wide provisioning so every user on the device gets it (needs admin):

```powershell
Add-AppxProvisionedPackage -Online -PackagePath .\Claude-1.30096.5-x64-offline.msix -SkipLicense
```

In a managed fleet, deploy the MSIX through Intune or ConfigMgr as a line-of-business
app instead.

### If signature validation fails

The failure mode on a stale certificate store is a signature error from
`Add-AppxPackage`. Install the **DigiCert Trusted Root G4** chain, then retry. Check what
the package is actually signed with:

```powershell
Get-AuthenticodeSignature .\Claude-1.30096.5-x64-offline.msix | Format-List *
```

Expected publisher: `CN="Anthropic, PBC", O="Anthropic, PBC", L=San Francisco, S=California, C=US`.

---

## The `Claude Setup.exe` trap

The `.exe` from the download page is a **6.9 MB bootstrapper, not an installer**.
Inspecting the binary shows the build path
`packages/desktop/win32-bootstrapper/install_squirrel.go`, the string
`https://downloads.claude.ai`, a URL template `%s/%s/msix/latest/redirect`, and the
user-facing message *"Ask your IT team to allow access to %s."*

It carries no application payload. On an offline machine it runs, fails to reach
`downloads.claude.ai`, and quits.

Separately, Anthropic notes that fleets provisioned with the **legacy `.exe` installer
get Claude Desktop without Cowork**, and migrating them to `.msix` is what enables it.
Either way: use the MSIX.

---

## Is a portable installer possible?

**Short answer: not for a working deployment.** You can extract the payload and probably
get the chat UI to launch, but Cowork and Code — the agent features that make this worth
deploying — cannot work from a portable folder.

### Why

The package manifest declares things only a real MSIX installation can register:

```xml
<rescap:Capability Name="packagedServices" />
<rescap:Capability Name="localSystemServices" />
<rescap:Capability Name="unvirtualizedResources" />

<desktop6:Service Name="CoworkVMService"
                  StartupType="auto"
                  StartAccount="localSystem">
  <desktop6:TriggerCustom Action="ActionStart" ...>
    <desktop6:DataItem Value="\pipe\cowork-vm-service" />
```

Cowork runs its sandbox VM through **`CoworkVMService`, a Windows service running as
`localSystem`**, started on demand when the app connects to the named pipe
`\pipe\cowork-vm-service`. The package also registers machine-wide firewall rules for
`Claude.exe` and `cowork-svc.exe`.

A folder you copied onto a machine registers no services, holds no restricted
capabilities, and installs no firewall rules. Nothing in a portable tree can bring
`CoworkVMService` into existence. Copying `cowork-svc.exe` alongside the app does not
help — a service has to be registered with the service control manager, which is a
privileged, machine-modifying operation and precisely what "portable" means to avoid.

This also matches Anthropic's own statement that legacy `.exe` (non-MSIX) installs get
Claude Desktop *without* Cowork.

### What you get if you try anyway

`Make-Portable.ps1` extracts the MSIX into a self-contained folder with a launcher that
redirects user data into the folder:

```powershell
.\Make-Portable.ps1 -MsixPath .\Claude-1.30096.5-x64-offline.msix -OutDir .\Claude-Portable
.\Claude-Portable\Claude-Portable.cmd
```

| Feature | Portable folder |
|---|---|
| Chat against Bedrock | Expected to work — **unverified** |
| Cowork sessions | **Will not work** — no VM service |
| Code sessions | **Will not work** — same reason |
| Deep links, Start menu, firewall rules | Not registered |
| Updates | Manual, by replacing the folder |

The "expected to work, unverified" is deliberate. It was not tested, because testing it
required installing over a working Claude Desktop on the build machine. Treat the
portable tree as a diagnostic tool or a way to inspect the payload, not as a deployment
method.

### What to use instead

**`Add-AppxPackage` without elevation is the closest thing to portable that actually
works.** MSIX packages normally install into the user's own profile and do not need
admin rights, leaving the machine's other users untouched.

Caveat worth testing on one of your machines first: this package registers a
`localSystem` service and machine-wide firewall rules, so it may prompt for elevation on
first install even though ordinary MSIX packages do not. Try it as a standard user and
find out before you plan a rollout around it:

```powershell
Add-AppxPackage -Path .\Claude-1.30096.5-x64-offline.msix
```

To remove it again, cleanly and without admin:

```powershell
Get-AppxPackage -Name Claude | Remove-AppxPackage
```

That is genuinely reversible and leaves nothing in `Program Files`, which is usually
what people actually want when they ask for portable.

---

## Where things live after install

| What | Path |
|---|---|
| Application | `C:\Program Files\WindowsApps\Claude_<version>_x64__<hash>\` |
| 3P user data | `%LOCALAPPDATA%\Claude-3p\` |
| Local (non-managed) config | `%LOCALAPPDATA%\Claude-3p\configLibrary\` |
| Logs | `%LOCALAPPDATA%\Claude-3p\Logs\main.log` |
| Agent helper | `%LOCALAPPDATA%\Claude-3p\claude-code\<version>\claude.exe` |
| Managed config | `HKLM\SOFTWARE\Policies\Claude` |

Standard (non-3P) installs use `%APPDATA%\Claude\` with the same subpaths.

---

## Endpoint security software

If you run binary-authorization or EDR tooling — CrowdStrike Falcon, Microsoft Defender
ASR, AppLocker — with path-based deny rules, the Cowork agent helper may be blocked from
launching. The symptom is specific and easy to misdiagnose: **Claude Desktop opens
normally and reads its managed configuration, but Cowork sessions fail to start.**

The helper lives at:

```
%LOCALAPPDATA%\Claude-3p\claude-code\<version>\claude.exe
```

It is Authenticode-signed with publisher `Anthropic, PBC`. **Allowlist by publisher, not
by path** — the path contains a version number and your rule will break on every update.
