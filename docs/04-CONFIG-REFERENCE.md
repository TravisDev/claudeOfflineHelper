# 04 — Configuration reference

Every managed-configuration key, transcribed from Anthropic's third-party configuration
reference (2026-08-17). Bedrock-specific keys are covered in depth in
[03 — Bedrock configuration](03-BEDROCK-CONFIG.md).

"MDM + Bootstrap" means the key can arrive either through a managed profile or a
bootstrap server response.

---

## Config file locations

| Platform | Managed | Local (per-user) |
|---|---|---|
| macOS | `/Library/Managed Preferences/<user>/com.anthropic.claudefordesktop.plist` | `~/Library/Application Support/Claude-3p/configLibrary/` |
| Windows | `HKLM\SOFTWARE\Policies\Claude`, `HKCU\SOFTWARE\Policies\Claude` | `%LOCALAPPDATA%\Claude-3p\configLibrary\` |
| Linux | `/etc/claude-desktop/managed-settings.json` | `~/.config/Claude-3p/configLibrary/` |

## Value types

Windows registry and macOS plist values are **all strings**, including booleans,
integers, and arrays. Linux `managed-settings.json` uses **native JSON types**.

| Type | Windows / macOS | Linux |
|---|---|---|
| boolean | `"true"` | `true` |
| integer | `"3600"` | `3600` |
| string[] | `"[\"a\",\"b\"]"` | `["a","b"]` |
| object | `"{\"k\":\"v\"}"` | `{"k":"v"}` |

---

## Connection and credentials

| Key | Type | Default | Description |
|---|---|---|---|
| `inferenceProvider` | enum | — | `gateway`, `anthropic`, `bedrock`, `mantle`, `vertex`, `foundry` |
| `inferenceCredentialKind` | enum | — | `static`, `helper-script`, `interactive`, `vendor-profile`, `oauth`, `workforce` |
| `inferenceCustomHeaders` | object | — | Extra headers on every inference request |
| `inferenceSessionLifetimeSec` | integer | — | Sign-in session lifetime |
| `inferenceCredentialHelper` | string | — | Absolute path to a credential helper executable |
| `inferenceCredentialHelperTtlSec` | integer | `3600` | Helper output cache duration |
| `inferenceCredentialHelperTimeoutSec` | integer | `60` | Max wait for helper (1–600) |
| `inferenceCredentialHelperSilentRefreshEnabled` | boolean | `true` | Re-run helper for silent refresh |
| `userContentRendererUrl` | string | — | HTTPS origin for the artifact preview iframe |

## Anthropic provider

| Key | Type | Description |
|---|---|---|
| `inferenceAnthropicApiKey` | string | Claude API key; leave blank for browser sign-in |

## Amazon Bedrock

| Key | Type | Description |
|---|---|---|
| `inferenceBedrockRegion` | string | AWS region for the Bedrock runtime endpoint |
| `inferenceBedrockBaseUrl` | string | Custom base URL (VPC endpoints, gateways) |
| `inferenceBedrockServiceTier` | enum | `flex` or `priority` |
| `inferenceBedrockBearerToken` | string | Static AWS bearer token |
| `inferenceBedrockSsoStartUrl` | string | AWS SSO start URL (enables in-app sign-in) |
| `inferenceBedrockSsoRegion` | string | IAM Identity Center home region |
| `inferenceBedrockSsoAccountId` | string | 12-digit AWS account ID |
| `inferenceBedrockSsoRoleName` | string | Permission-set name |
| `inferenceBedrockProfile` | string | AWS named profile |
| `inferenceBedrockAwsDir` | string | Folder with AWS config/credentials (default `~/.aws`) |
| `inferenceBedrockAwsCliPath` | string | Absolute path to the `aws` executable |

## Gateway

| Key | Type | Default | Description |
|---|---|---|---|
| `inferenceGatewayBaseUrl` | string | — | Gateway endpoint URL |
| `inferenceGatewayApiKey` | string | — | API key |
| `inferenceGatewayAuthScheme` | enum | `bearer` | `bearer` or `x-api-key` |
| `inferenceGatewayOidcAuthFlow` | enum | — | `browser` or `broker` |
| `inferenceGatewayOidc` | object | — | External IdP for gateway sign-in |

`inferenceGatewayOidc` shape:

```json
{
  "clientId": "string",
  "issuer": "string",
  "authorizationUrl": "string",
  "tokenUrl": "string",
  "bearerTokenType": "id_token",
  "scopes": "string",
  "appendOfflineAccess": true,
  "resource": "string",
  "redirectPort": 0,
  "additionalRedirectReferrerHosts": "string"
}
```

## Microsoft Foundry

| Key | Type | Description |
|---|---|---|
| `inferenceFoundryResource` | string | Azure AI Foundry resource name |
| `inferenceFoundryApiKey` | string | API key |
| `inferenceFoundryTenantId` | string | Entra ID tenant (directory) ID |
| `inferenceFoundryClientId` | string | Entra ID client ID |
| `inferenceFoundryAuthFlow` | enum | `device-code`, `browser`, `broker` |

## Google Vertex AI

| Key | Type | Description |
|---|---|---|
| `inferenceVertexProjectId` | string | GCP project ID |
| `inferenceVertexRegion` | string | GCP region |
| `inferenceVertexBaseUrl` | string | PSC endpoint |
| `inferenceVertexOAuthClientId` | string | Desktop-app OAuth client ID |
| `inferenceVertexOAuthClientSecret` | string | OAuth client secret |
| `inferenceVertexOAuthScopes` | string | Space-separated scope override |
| `inferenceVertexOAuthLoginHint` | string | Pre-fill account chooser (`{username}` expands to OS login) |
| `inferenceVertexWorkforceAudience` | string | Workforce-pool provider audience |
| `inferenceVertexWorkforceUserProject` | string | GCP project for STS billing |
| `inferenceVertexWorkforceAuthFlow` | enum | `browser` or `broker` |
| `inferenceVertexWorkforceOidc` | object | Organization OIDC IdP |
| `inferenceVertexCredentialsFile` | string | Absolute path to service-account JSON |

## Models

| Key | Type | Description |
|---|---|---|
| `modelDiscoveryEnabled` | boolean | Auto-populate the model picker from the provider |
| `modelPrefer1mContext` | boolean | Default to the 1M-context variant when available |
| `inferenceModels` | object[] | Explicit model list; **first entry is the default** |

Entry shape:

```json
{
  "name": "string",
  "labelOverride": "string",
  "supports1m": false,
  "prefer1m": false,
  "anthropicFamilyTier": "sonnet",
  "isFamilyDefault": false
}
```

`anthropicFamilyTier` accepts `sonnet`, `opus`, `haiku`, `fable`, `mythos`.

## Workspace and features

| Key | Type | Default | Description |
|---|---|---|---|
| `disableDeploymentModeChooser` | boolean | `false` | Hide the claude.ai sign-in option |
| `disableDeepLinkRegistration` | boolean | `false` | Disable `claude://` deep links |
| `chatTabEnabled` | boolean | — | Enable Chat |
| `chatAdvancedFileAnalysisEnabled` | boolean | — | Advanced file analysis in the sandbox |
| `isClaudeCodeForDesktopEnabled` | boolean | `true` | Enable Code |
| `coworkTabEnabled` | boolean | `true` | Enable Cowork |
| `disabledBuiltinTools` | string[] | — | Built-in tools removed from Cowork |
| `disableBundledSkills` | boolean | — | Disable bundled skills/workflows |
| `skillCreationEnabled` | boolean | — | Allow user-created skills |
| `builtinToolPolicy` | object | — | Per-tool approval policy (`ask`, `allow`) |
| `autoModeEnabled` | boolean | `false` | Allow Auto mode |
| `toolSearchEnabled` | boolean | `false` | Load MCP tool schemas on demand |
| `allowedWorkspaceFolders` | object[] | — | Folders Claude may work in |
| `coworkEgressAllowedHosts` | string[] | — | Hostnames agent tools may reach |
| `requireCoworkFullVmSandbox` | boolean | `false` | **Deprecated.** Run tools in an isolated VM |

`allowedWorkspaceFolders` entry shape:

```json
{ "path": "string", "isDefaultSelected": true, "mode": "rw" }
```

`mode` is `rw` or `ro`.

## Connectors and extensions

| Key | Type | Default | Description |
|---|---|---|---|
| `claudeAiImport` | object | — | Enable claude.ai data import |
| `microsoftAuthBroker` | enum | `auto` | `auto` or `disabled` |
| `isDesktopExtensionEnabled` | boolean | `false` | Allow `.dxt` / `.mcpb` installs |
| `isDesktopExtensionSignatureRequired` | boolean | `false` | Require signed extensions |
| `managedMcpServers` | object[] | — | Org-pushed MCP servers |
| `mcpPersistentAlwaysAllowEnabled` | boolean | `true` | Allow persistent tool approvals |
| `isLocalDevMcpEnabled` | boolean | `true` | Allow user-added MCP servers |

`managedMcpServers` entry shape (partial):

```json
{
  "name": "string",
  "server": "github",
  "transport": "http",
  "url": "string",
  "command": "string",
  "args": ["string"],
  "env": { "VAR": "value" },
  "headers": { "Header-Name": "value" },
  "headersHelper": "string",
  "headersHelperTtlSec": 3600,
  "oauth": { "clientId": "string", "clientSecret": "string" },
  "toolPolicy": { "tool_name": "allow" }
}
```

`server` accepts `microsoft365`, `websearch`, `github`. `transport` accepts `http`,
`sse`, `stdio`. `toolPolicy` values are `blocked`, `ask`, `allow`.

## Telemetry and updates

| Key | Type | Default | Description |
|---|---|---|---|
| `deploymentOrganizationUuid` | string | — | UUID tagging telemetry to your fleet |
| `disableEssentialTelemetry` | boolean | `false` | Block crash/performance reports |
| `disableNonessentialTelemetry` | boolean | `false` | Block usage analytics |
| `disableNonessentialServices` | boolean | `false` | Block favicons, registry, artifact preview |
| `disableAutoUpdates` | boolean | `false` | Stop auto-update checks |
| `autoUpdaterEnforcementHours` | integer | — | Hours before a downloaded update force-installs (1–72) |
| `updateViaUpdatesHost` | boolean | `false` | Read the update feed from `releases.claude.com` |
| `endUserAttribution` | boolean | — | Set `false` to remove user identity from the app and OTLP export |

> `autoUpdaterEnforcementHours` **tunes** the 72-hour forced-restart window; it does not
> enable it. Enforcement is always on unless `disableAutoUpdates` is set. Setting the key
> also makes the window strict — the restart fires as soon as it elapses, without waiting
> for a pause in user activity.

## OpenTelemetry

| Key | Type | Default | Description |
|---|---|---|---|
| `otlpEndpoint` | string | — | Collector base address, e.g. `https://otel.example.com:4318` |
| `otlpProtocol` | enum | `http/protobuf` | `http/protobuf`, `http/json`, `grpc` |
| `otlpHeaders` | object | — | Static collector headers |
| `otlpAuthMode` | enum | — | `none` or `inference-credential` |
| `otlpHeadersHelper` | string | — | Executable printing JSON headers |
| `otlpResourceAttributes` | object | — | Extra resource attributes per span |
| `otlpDesktopLogLevel` | enum | `error` | `off`, `error`, `warn`, `info`, `debug` |
| `otlpContentCapture` | enum[] | — | `userPrompts`, `assistantResponses`, `toolDetails`, `toolContent`, `rawApiBodies` |
| `otlpTracesEnabled` | boolean | — | Export traces (beta; requires 1.22209.0+) |

Notes worth knowing before you wire up a collector:

- Give `otlpEndpoint` the **base** address. The app appends `/v1/logs`, `/v1/metrics`,
  `/v1/traces` itself. A path prefix like `https://obs.example.com/otlp` is preserved.
- Streams arrive under `service.name` values `cowork`, `claude-code-desktop`, and
  `claude-desktop`.
- **Cowork does not support gRPC export** and falls back to `http/protobuf`; the desktop
  app's own stream is **always** `http/json`. The fallback changes protocol but not
  endpoint, so pointing `otlpEndpoint` at a gRPC receiver on :4317 silently loses those
  two streams. Use `http/protobuf` on :4318 to receive all three.
- Failures are silent: if the collector is unreachable the app keeps working, shows no
  error, and drops the batches. Check the collector's own request logs.
- Both keys are read at launch — restart after changing them.
- The collector host is auto-added to the sandbox egress allowlist, but your perimeter
  firewall still needs it.
- Records carry `enduser.id` and `process.owner`. `endUserAttribution: false` removes
  the former; `process.owner` is standard OTel process metadata and is always present.
- On 1.17377+, enabling `userPrompts` also captures model responses. No configuration
  captures prompts without responses.

## Token limits

| Key | Type | Description |
|---|---|---|
| `inferenceMaxTokensPerWindow` | integer | Soft per-user token cap |
| `inferenceTokenWindowHours` | integer | Window length, 1–720 hours (30 days) |

## Appearance

| Key | Type | Description |
|---|---|---|
| `userInterfaceAppearance` | enum | `light`, `dark`, `system` |

---

## Recommended locked-down profile

For an offline Bedrock deployment:

```json
{
  "inferenceProvider": "bedrock",
  "inferenceBedrockRegion": "us-east-1",
  "inferenceBedrockSsoStartUrl": "https://my-sso.awsapps.com/start",
  "inferenceBedrockSsoRegion": "us-east-1",
  "inferenceBedrockSsoAccountId": "123456789012",
  "inferenceBedrockSsoRoleName": "BedrockAccess",

  "disableAutoUpdates": true,
  "disableNonessentialTelemetry": true,
  "disableNonessentialServices": true,
  "disableDeploymentModeChooser": true,
  "disableDeepLinkRegistration": true,

  "isDesktopExtensionEnabled": false,
  "isLocalDevMcpEnabled": false,
  "autoModeEnabled": false,

  "allowedWorkspaceFolders": [
    { "path": "/home/user/work", "isDefaultSelected": true, "mode": "rw" }
  ],
  "coworkEgressAllowedHosts": []
}
```

`disableEssentialTelemetry` is deliberately left unset — see the warning in
[02 — Network and egress](02-NETWORK-EGRESS.md#essential-telemetry-disableessentialtelemetry-false).
Your firewall already blocks those hosts; disabling the key as well costs you Anthropic's
support visibility for no additional network benefit.
