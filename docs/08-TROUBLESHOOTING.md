# 08 — Troubleshooting

Ordered roughly by how often each one bites.

---

## Logs and diagnostics

| Platform | Application log |
|---|---|
| Windows | `%LOCALAPPDATA%\Claude-3p\Logs\main.log` |
| macOS | `~/Library/Logs/Claude-3p/main.log` |
| Linux | `~/.config/Claude-3p/logs/main.log` |

Two built-in tools, both under **Help → Troubleshooting**:

- **Copy Managed Configuration Report** — which keys were detected, what source they came
  from, whether credentials validated. Secrets redacted. Start here for any config issue.
- **Generate Diagnostic Report** — full bundle for Anthropic support. Contains config
  state, logs, environment. No user data or conversation content.

With `disableNonessentialTelemetry: true`, the diagnostic report's **Send** button is
disabled and you can only save locally — which is what you want on a closed network.
Attach the folder to your support ticket manually.

---

## The app shows the claude.ai sign-in screen

The configuration was not read. In order of likelihood:

1. **`inferenceProvider` missing, misspelled, or unrecognized.** The app silently ignores
   unknown keys rather than erroring, so a typo is invisible. Check the Managed
   Configuration Report.
2. **Config applied while the app was running.** Fully quit — not just close the window —
   and relaunch.
3. **Written to the wrong location.** Managed vs. local are different paths; see
   [04 — Configuration reference](04-CONFIG-REFERENCE.md#config-file-locations).
4. **A required key for the provider is missing.** Bedrock needs at minimum
   `inferenceProvider` and `inferenceBedrockRegion`.
5. **Windows hive precedence.** Config is in `HKCU\SOFTWARE\Policies\Claude` but *any*
   value exists directly under `HKLM\SOFTWARE\Policies\Claude` — the app then ignores
   `HKCU` entirely (v1.19367.0+). Pick one hive.
6. **Windows `REG_EXPAND_SZ`.** Such a value appears normally in `reg query` output while
   the app reports the managed configuration invalid or absent: it counts as machine
   policy but the app cannot read its contents. **Use `REG_SZ` only.**

Quick check on Windows:

```powershell
reg query "HKLM\SOFTWARE\Policies\Claude" /s
```

Every value should read `REG_SZ`.

To hide the claude.ai option entirely once Bedrock works, set
`disableDeploymentModeChooser` to `true`.

---

## The config window is editable when it should not be

On a managed device, **Developer → Configure Third-Party Inference…** opens read-only.

- **macOS/Linux:** an editable window means *no recognized key reached the app*, even if
  your MDM reports the profile as delivered.
- **Windows:** even a misspelled value under `HKLM\SOFTWARE\Policies\Claude` counts as
  machine policy and locks the window — so a locked window is **not** proof your keys
  were read. Use the Managed Configuration Report.
- If your profile deliberately sets only the update keys, an editable window is expected.

---

## Cowork sessions will not start

The highest-value distinction: **does the app open and read its config, but sessions
fail?** That is not a configuration problem.

### On Linux — almost always the missing offline installer

Linux has no offline installer, so the app fetches the VM bundle and CLI from
`downloads.claude.ai` at session start. Blocked host, failed session. See
[06 — Linux install](06-LINUX-INSTALL.md).

Confirm:

```bash
curl -sI -o /dev/null -w '%{http_code}\n' https://downloads.claude.ai/
```

### On Windows — check you installed the offline package

The standard MSIX (267 MB) also fetches at session start. Only the offline MSIX
(1.80 GB) has the components built in. Verify what is installed:

```powershell
Get-AppxPackage -Name Claude | Select-Object Name, Version, InstallLocation
Test-Path "$((Get-AppxPackage -Name Claude).InstallLocation)\app\resources\preseed\vm_bundle\rootfs.vhdx.zst"
```

`True` means you have the offline build. `False` means you installed the standard one.

### Missing virtualization

```powershell
# Windows
Get-ComputerInfo -Property HyperVRequirementVirtualizationFirmwareEnabled, HyperVisorPresent
```

```bash
# Linux
grep -Eoc '(vmx|svm)' /proc/cpuinfo
ls -l /dev/kvm
```

Run Anthropic's readiness checker on Windows — it verifies all of this in one step:
`https://claude.ai/api/desktop/win32/x64/cowork-readiness-check/latest/redirect`

### Missing Linux VM packages

```bash
dpkg -l qemu-system-x86 ovmf virtiofsd | grep '^ii'
```

These are `Recommends`, not `Depends` — the app installs fine without them and then fails
at session start.

### EDR or binary-authorization blocking the agent helper

Distinctive symptom: **the app opens normally and reads its managed configuration, but
Cowork sessions fail to start.** Path-based deny rules in Santa, CrowdStrike Falcon, or
Defender ASR block the helper.

| Platform | Helper path |
|---|---|
| Windows | `%LOCALAPPDATA%\Claude-3p\claude-code\<version>\claude.exe` |
| macOS | `~/Library/Application Support/Claude-3p/claude-code/<version>/claude.app/Contents/MacOS/claude` |

**Allowlist by signing identity, not path** — the path carries a version number and any
path rule breaks at the next update.

- macOS: Team ID `Q6L2SF6YDW` (Anthropic PBC), signing ID `com.anthropic.claude-code`.
  For Santa, a `TEAMID` rule for `Q6L2SF6YDW` survives updates.
- Windows: Authenticode publisher `Anthropic, PBC`. For Defender ASR or AppLocker, use a
  publisher rule.

Standard (non-3P) installs use `~/Library/Application Support/Claude/` and
`%APPDATA%\Claude\` with the same subpaths.

---

## Bedrock credential failures

### "Credentials not found" but the AWS CLI works in a terminal

Almost always PATH. GUI applications inherit a narrower PATH than your shell. Set the
path explicitly:

```json
{ "inferenceBedrockAwsCliPath": "/usr/local/bin/aws" }
```

Also confirm `inferenceBedrockAwsDir` points at the right home directory — a service
account or a different OS user has a different `~/.aws`.

### Model invocation fails at request time, not startup

Model access in Bedrock is granted **per account and per region**. A model ID in
`inferenceModels` that your account cannot invoke passes startup validation and fails
when first used. Enable model access in the Bedrock console, and check the regional
prefix matches your region (`us.` vs `eu.` vs `apac.`).

Verify from the target machine:

```bash
aws bedrock list-foundation-models --region us-east-1 \
  --query 'modelSummaries[?contains(modelId,`anthropic`)].modelId' --output table
```

### SSO sign-in never completes

`inferenceBedrockSsoRegion` is the **IAM Identity Center home region**, which is often
different from your inference region. Also confirm `portal.sso.<region>.amazonaws.com`
and `oidc.<region>.amazonaws.com` are allowlisted — SSO uses hosts that a
Bedrock-runtime-only allowlist does not cover.

---

## TLS and certificate errors

On a TLS-intercepting proxy, install the corporate CA into the OS trust store, then
restart the app fully. If verification still fails, set `NODE_EXTRA_CA_CERTS` to the PEM
bundle. macOS has an extra trap around policy-restricted trust — see
[02 — Network and egress](02-NETWORK-EGRESS.md#tls-intercepting-proxies).

MSIX signature validation failures on Windows are a *different* problem — that is the
package's own DigiCert chain, not your proxy. Install DigiCert Trusted Root G4.

---

## OTLP telemetry never arrives

Failures here are silent by design: the app keeps working, shows no error, and drops the
batches.

1. `otlpEndpoint` must be the **base** address — the app appends `/v1/logs` etc. itself.
2. Restart the app; these keys are read at launch only.
3. If `otlpProtocol` is `grpc`, Cowork falls back to `http/protobuf` and the desktop
   stream is always `http/json`. Pointing at a gRPC receiver on :4317 silently loses two
   of three streams. Use `http/protobuf` on :4318.
4. The collector must present a TLS certificate the OS trusts.
5. Check the collector's own request logs — that is the only reliable signal.

---

## Getting help

Generate a diagnostic report (**Help → Troubleshooting → Generate Diagnostic Report**),
save it locally, and send the folder to your Anthropic representative.

If you set `disableEssentialTelemetry: true`, Anthropic has **zero** remote visibility
into failures on your fleet and every support interaction requires manually collected
logs. Consider leaving that key unset and letting your firewall block the hosts instead —
same network outcome, better support experience.
