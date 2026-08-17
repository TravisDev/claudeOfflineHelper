# 03 — Bedrock configuration

How to point Claude Desktop at Amazon Bedrock, on every platform, with all four
authentication methods.

---

## How Bedrock mode is activated

There is no special Bedrock installer. You install the **same** package shipped in this
repo, then supply managed configuration naming Bedrock as the inference provider. At
launch the app detects a configured provider and the sign-in screen offers to skip
Anthropic authentication and start from your provider configuration instead.

Deploy the configuration **before** the app, so users never see the claude.ai sign-in
screen.

---

## Where configuration goes

| Platform | Managed (admin, wins) | Local (per-user) |
|---|---|---|
| **Windows** | `HKLM\SOFTWARE\Policies\Claude` (machine)<br>`HKCU\SOFTWARE\Policies\Claude` (user) | `%LOCALAPPDATA%\Claude-3p\configLibrary\` |
| **Linux** | `/etc/claude-desktop/managed-settings.json` | `~/.config/Claude-3p/configLibrary/` |
| **macOS** | `/Library/Managed Preferences/<user>/com.anthropic.claudefordesktop.plist` | `~/Library/Application Support/Claude-3p/configLibrary/` |

When an admin profile is present, users cannot override it — the in-app configuration
window opens read-only.

> **Windows precedence trap (v1.19367.0+).** Any `REG_SZ`, `REG_EXPAND_SZ`, or
> `REG_DWORD` value directly under `HKLM\SOFTWARE\Policies\Claude` makes the app ignore
> `HKCU` **entirely**. Do not split configuration across both hives. Worse, a
> `REG_EXPAND_SZ` value shows up fine in `reg query` output while the app reports the
> managed configuration as invalid or absent — it counts as machine policy but the app
> cannot read its contents. **Use `REG_SZ` only.**

---

## Value types — the rule that catches everyone

On **Windows and macOS**, every value is written as a **string**, even booleans,
integers, and arrays:

| Type | Format | Example |
|---|---|---|
| string | plain | `"bedrock"` |
| boolean | `"true"` / `"false"` | `"true"` |
| integer | decimal string | `"3600"` |
| string[] | JSON array as a string | `"[\"us.anthropic.claude-sonnet-5\"]"` |
| object | JSON object as a string | `"{\"X-Org-Id\":\"team1\"}"` |

**Linux is the exception:** `/etc/claude-desktop/managed-settings.json` uses **native
JSON types**. Booleans are real booleans, arrays are real arrays.

The app silently ignores a misspelled key rather than reporting an error, so a typo
looks exactly like a key that was never delivered. Verify with the Managed Configuration
Report (below).

---

## Minimum viable Bedrock config

```json
{
  "inferenceProvider": "bedrock",
  "inferenceBedrockRegion": "us-east-1"
}
```

Two keys. Everything else is authentication and tuning.

---

## The four authentication methods

Pick one. `inferenceCredentialKind` may be set explicitly (`static`, `helper-script`,
`interactive`, `vendor-profile`, `oauth`, `workforce`) but is usually inferred.

### 1. AWS SSO / IAM Identity Center — recommended for user fleets

Users sign in through your identity provider inside the app. No long-lived secrets on
disk.

```json
{
  "inferenceProvider": "bedrock",
  "inferenceBedrockRegion": "us-east-1",
  "inferenceBedrockSsoStartUrl": "https://my-sso-portal.awsapps.com/start",
  "inferenceBedrockSsoRegion": "us-east-1",
  "inferenceBedrockSsoAccountId": "123456789012",
  "inferenceBedrockSsoRoleName": "BedrockAccess"
}
```

`inferenceBedrockSsoRegion` is your **IAM Identity Center home region**, which is not
necessarily the same as your Bedrock inference region. Account ID is the 12-digit
number; role name is the permission-set name.

Extra egress: `portal.sso.<region>.amazonaws.com`, `oidc.<region>.amazonaws.com`, STS.

### 2. Named AWS profile — good for a single machine or a server

Reuses credentials already on the box from `aws configure` or `aws sso login`.

```json
{
  "inferenceProvider": "bedrock",
  "inferenceBedrockRegion": "us-west-2",
  "inferenceBedrockProfile": "bedrock-prod",
  "inferenceBedrockAwsDir": "~/.aws",
  "inferenceBedrockAwsCliPath": "/usr/local/bin/aws"
}
```

`inferenceBedrockAwsDir` defaults to `~/.aws`. Set `inferenceBedrockAwsCliPath` if the
`aws` binary is not on the app's PATH — GUI apps often have a narrower PATH than your
shell, and this is a common cause of "credentials not found" when the CLI clearly works
in a terminal.

Extra egress: STS.

### 3. Static bearer token — simplest, least safe

```json
{
  "inferenceProvider": "bedrock",
  "inferenceBedrockRegion": "us-east-1",
  "inferenceBedrockBearerToken": "<token>"
}
```

Only the runtime and control-plane hosts are needed — no STS, no SSO. But the token sits
in your MDM profile and in the registry, it does not rotate, and every user sharing the
profile shares the identity. Use SSO or a credential helper for anything beyond a pilot.

### 4. Credential helper script — for custom or brokered credentials

An executable on the device that prints credentials on stdout.

```json
{
  "inferenceProvider": "bedrock",
  "inferenceBedrockRegion": "us-east-1",
  "inferenceCredentialHelper": "C:\\ProgramData\\Corp\\get-bedrock-token.exe",
  "inferenceCredentialHelperTtlSec": 3600,
  "inferenceCredentialHelperTimeoutSec": 60,
  "inferenceCredentialHelperSilentRefreshEnabled": true
}
```

| Key | Default | Notes |
|---|---|---|
| `inferenceCredentialHelper` | — | Absolute path to the executable |
| `inferenceCredentialHelperTtlSec` | `3600` | How long output is cached |
| `inferenceCredentialHelperTimeoutSec` | `60` | Max wait, 1–600 |
| `inferenceCredentialHelperSilentRefreshEnabled` | `true` | Re-run for silent refresh |

Use an absolute path and make sure the binary is readable and executable by the user
running Claude, not just by an admin.

---

## Models

Bedrock model IDs use the **inference-profile** format, with a regional prefix:

```
us.anthropic.claude-sonnet-5
us.anthropic.claude-opus-4-8
eu.anthropic.claude-sonnet-5
apac.anthropic.claude-sonnet-5
```

The prefix must match the region you configured. A `us.` profile ID will not work
against an `eu-west-1` endpoint.

Let the app discover what your account can actually call:

```json
{ "modelDiscoveryEnabled": true }
```

Or pin an explicit list — **the first entry becomes the default**:

```json
{
  "inferenceModels": [
    { "name": "us.anthropic.claude-sonnet-5", "isFamilyDefault": true, "supports1m": true },
    { "name": "us.anthropic.claude-opus-4-8", "labelOverride": "Opus (heavy tasks)" }
  ],
  "modelPrefer1mContext": false
}
```

| Field | Meaning |
|---|---|
| `name` | Bedrock inference-profile ID |
| `labelOverride` | What users see in the picker |
| `supports1m` | Model offers a 1M-context variant |
| `prefer1m` | Default this model to its 1M variant |
| `anthropicFamilyTier` | `sonnet`, `opus`, `haiku`, `fable`, `mythos` |
| `isFamilyDefault` | Default within its family |

**Enable each model in the Bedrock console first.** Model access is per-account and
per-region; a model listed here that your account cannot invoke fails at request time,
not at startup, so it looks like a runtime error rather than a config error.

---

## Private endpoints, service tiers, GovCloud

```json
{
  "inferenceBedrockBaseUrl": "https://bedrock-runtime.vpce-0abc123.us-east-1.vpce.amazonaws.com",
  "inferenceBedrockServiceTier": "priority"
}
```

- `inferenceBedrockBaseUrl` — PrivateLink / VPC endpoint or an internal gateway.
  Replaces the public runtime host in your allowlist.
- `inferenceBedrockServiceTier` — `flex` (cheaper, best-effort) or `priority` (higher
  throughput). Omit for standard.
- **GovCloud** (`us-gov-*` regions) — the app switches to FIPS endpoints automatically.
  No key required.

---

## Platform examples

### Windows — `.reg` (Bedrock via SSO, locked down)

```
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Claude]
"inferenceProvider"="bedrock"
"inferenceBedrockRegion"="us-east-1"
"inferenceBedrockSsoStartUrl"="https://my-sso-portal.awsapps.com/start"
"inferenceBedrockSsoRegion"="us-east-1"
"inferenceBedrockSsoAccountId"="123456789012"
"inferenceBedrockSsoRoleName"="BedrockAccess"
"disableAutoUpdates"="true"
"disableNonessentialTelemetry"="true"
"disableNonessentialServices"="true"
"disableDeploymentModeChooser"="true"
```

Ready-to-edit files are in [`windows/config/`](../windows/config/). Note every value is
`REG_SZ`, including the booleans.

### Linux — `/etc/claude-desktop/managed-settings.json`

```json
{
  "inferenceProvider": "bedrock",
  "inferenceBedrockRegion": "us-west-2",
  "inferenceBedrockProfile": "bedrock-prod",
  "inferenceModels": [
    { "name": "us.anthropic.claude-sonnet-5", "isFamilyDefault": true }
  ],
  "deploymentOrganizationUuid": "550e8400-e29b-41d4-a716-446655440000",
  "disableAutoUpdates": true,
  "disableNonessentialTelemetry": true,
  "disableNonessentialServices": true,
  "disableDeploymentModeChooser": true,
  "coworkEgressAllowedHosts": ["api.github.com", "*.corp.example.com"]
}
```

Native JSON types here — real booleans, real arrays. Files in
[`linux/config/`](../linux/config/).

### macOS — MDM `.plist`

Deploy to `/Library/Managed Preferences/<user>/com.anthropic.claudefordesktop.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>inferenceProvider</key>
  <string>bedrock</string>
  <key>inferenceBedrockRegion</key>
  <string>us-east-1</string>
  <key>inferenceBedrockSsoStartUrl</key>
  <string>https://my-sso-portal.awsapps.com/start</string>
  <key>inferenceBedrockSsoRegion</key>
  <string>us-east-1</string>
  <key>inferenceBedrockSsoAccountId</key>
  <string>123456789012</string>
  <key>inferenceBedrockSsoRoleName</key>
  <string>BedrockAccess</string>
  <key>disableAutoUpdates</key>
  <string>true</string>
</dict>
</plist>
```

---

## Verify it took

**Help → Troubleshooting → Copy Managed Configuration Report** — shows which keys were
detected, which source they came from, and whether credentials validated. Secrets
redacted. This is the fastest way to catch a typo'd key name.

Then check **Developer → Configure Third-Party Inference…** opens **read-only**.

---

## Single-machine setup without MDM

For a pilot, configure directly in the app:

1. Install Claude Desktop. **Do not sign in or create an Anthropic account.**
2. Application menu ☰ (top-left of the login screen) → **Help → Troubleshooting →
   Enable Developer Mode**.
3. **Developer → Configure Third-Party Inference…**
4. Enter provider, region, and credentials.
5. **Apply locally.** The app relaunches; the sign-in screen now offers the third-party
   option.

This writes to the local config file for that user only. When it works, export it as the
MDM profile you deploy to the fleet.
