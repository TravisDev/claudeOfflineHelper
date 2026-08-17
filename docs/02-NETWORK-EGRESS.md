# 02 — Network and egress

Everything the app talks to, what turns each path off, and the exact allowlist to hand
your firewall team.

All traffic is HTTPS on port 443. Allowlist **by hostname (SNI)** — path-level rules are
not required.

---

## The headline

With the **offline installer** and the four `disable*` keys set, Claude Desktop makes
**no outbound connections to Anthropic-operated hosts at all**. Your inference provider
is the only required egress.

Anthropic states this directly:

> With `disableEssentialTelemetry`, `disableNonessentialTelemetry`,
> `disableNonessentialServices`, and `disableAutoUpdates` all set to `true`, the desktop
> application makes **no outbound connections to Anthropic-operated hosts at runtime**.
> […] With the offline installer variant, `downloads.claude.ai` is not needed either,
> and your inference provider is the only required egress.
>
> — [Telemetry and egress](https://claude.com/docs/third-party/claude-desktop/telemetry)

---

## Two independent boundaries

Do not confuse these:

1. **Perimeter firewall** — what the device can reach. The hostnames on this page.
2. **Agent egress allowlist** — the `coworkEgressAllowedHosts` key, controlling what the
   agent's own web-fetch and shell tools may reach from inside the sandbox. Independent
   of, and stricter than, the perimeter.

A host must pass *both* for an agent tool to reach it.

> **Authoritative source for your build:** the **Egress** section of the in-app
> configuration window computes the exact allowlist from your current settings and
> exports it as a text file for your firewall team. Use the tables here as a static
> reference and defer to that window.

---

## Always required

| Host | Purpose |
|---|---|
| `downloads.claude.ai` | VM workspace bundle and Claude CLI binary, fetched at session start. **Not needed with the offline installer** — that package contains both, verified against checksums compiled into the app. |

Without this host *and* without the offline installer, **Cowork sessions cannot start**.
This is the single fact that determines whether your deployment works.

---

## Inference provider — Amazon Bedrock

These carry your conversation content.

| Host | Purpose |
|---|---|
| `bedrock-runtime.<region>.amazonaws.com` | Model inference. Replaced by the host of `inferenceBedrockBaseUrl` if set. |
| `bedrock.<region>.amazonaws.com` | Control plane (model discovery) |
| `sts.amazonaws.com`, `sts.<region>.amazonaws.com` | STS token exchange — **profile auth only** |
| `portal.sso.<region>.amazonaws.com`, `oidc.<region>.amazonaws.com` | AWS SSO — **profile auth only** |

With `inferenceBedrockBearerToken` set, only the runtime and control-plane hosts are
required.

**AWS GovCloud** (`us-gov-*`): the app automatically switches to FIPS endpoints —
`bedrock-runtime-fips.<region>.amazonaws.com` and `bedrock-fips.<region>.amazonaws.com`.

**VPC endpoints:** set `inferenceBedrockBaseUrl` to your PrivateLink endpoint and
allowlist that host instead of the public runtime host.

---

## Everything below is optional — turn it off

### Auto-updates (`disableAutoUpdates: false`)

| Host | Purpose |
|---|---|
| `claude.ai` | Update feed |
| `api.anthropic.com` | Update feed |
| `downloads.claude.ai` | Update binaries |

With `updateViaUpdatesHost: true` the feed moves to `releases.claude.com` instead of
`claude.ai` and `api.anthropic.com`.

**For an offline deployment, set `disableAutoUpdates: true`.** The app cannot reach the
feed anyway, and you update by redistributing offline installers. Anthropic explicitly
pairs the offline installer with this key.

### Essential telemetry (`disableEssentialTelemetry: false`)

| Host | Purpose |
|---|---|
| `sentry.io` | Crash and error reporting (apex — some firewalls do not match it under `*.sentry.io`) |
| `*.sentry.io` | Crash and error reporting |
| `*.ingest.us.sentry.io` | Listed separately for firewalls that match wildcards one label deep |
| `browser-intake-us5-datadoghq.com` | Performance timing (the config window lists additional regional Datadog hosts) |

Contains app version, OS, error type and redacted stack frames — **never prompt or
response content**.

> **Think before disabling this.** It opts you into a manual support model: Anthropic
> gets zero remote visibility into failures on your fleet, so every support request
> requires your team to collect and send logs by hand. Anthropic recommends leaving it
> **enabled during initial rollout**. On a network that blocks these hosts it fails
> closed and harmlessly, so you may prefer to leave the key unset and let the firewall
> do the blocking.

### Non-essential telemetry (`disableNonessentialTelemetry: false`)

| Host | Purpose |
|---|---|
| `a-cdn.anthropic.com` | Analytics SDK |
| `api.anthropic.com` | Claude Code usage telemetry, sent from inside the agent sandbox |
| `a-api.anthropic.com` | Analytics events |
| `claude.ai` | Analytics events |

Leaving this enabled **also auto-adds `api.anthropic.com` to the agent egress
allowlist** so Claude Code can deliver telemetry from inside the sandbox. Disable it.

Side effect: this also gates the **Send** button in Help → Generate Diagnostic Report.
With it disabled, diagnostic bundles can only be saved locally — which is what you want
anyway on a closed network.

### Non-essential services (`disableNonessentialServices: false`)

| Host | Purpose |
|---|---|
| `api.anthropic.com` | MCP connector directory |
| `www.claudeusercontent.com` | Artifact preview iframe |
| `*.claudemcpcontent.com` | MCP App widgets (each loads on its own generated subdomain — allowlist the wildcard) |
| `assets.claude.ai` | Fonts for MCP App widget iframes |
| `cdnjs.cloudflare.com`, `cdn.jsdelivr.net`, `fonts.googleapis.com` | Artifact preview asset CDNs |
| `www.google.com`, `*.gstatic.com` | Connector favicons |

Cosmetic only. Disabling degrades the UI — generic icons, no directory suggestions,
static artifact previews, connector widgets rendered as plain text — but breaks no
functionality.

If you want artifact previews on a closed network, point `userContentRendererUrl` at an
HTTPS origin you host internally.

### Other optional paths

| Host | Required when |
|---|---|
| Host of `otlpEndpoint` | You export telemetry to your own OpenTelemetry collector |
| `github.com`, `objects.githubusercontent.com`, `pypi.org`, `files.pythonhosted.org` | Python-based desktop extensions are enabled |
| Hosts of each `managedMcpServers` entry (plus `oauth.authorizationServer`, and `login.microsoftonline.com` if configured) | Managed MCP servers are configured |
| Hosts in `coworkEgressAllowedHosts` | Sandbox web access is configured |

The OTLP collector host is auto-added to the sandbox allowlist, but **your perimeter
firewall still needs it**.

---

## The final allowlist for this deployment

Windows, offline installer, Bedrock via AWS SSO, everything optional disabled:

```
# Inference
bedrock-runtime.us-east-1.amazonaws.com
bedrock.us-east-1.amazonaws.com

# AWS SSO sign-in (drop these if using a bearer token)
portal.sso.us-east-1.amazonaws.com
oidc.us-east-1.amazonaws.com
sts.amazonaws.com
sts.us-east-1.amazonaws.com
```

Substitute your region. **No Anthropic hosts.**

If you are on **Linux**, add `downloads.claude.ai` — it is not optional there, because
no Linux offline installer exists.

---

## Proxies

The Cowork sandbox honors the host OS proxy configuration, **including PAC files**, with
no extra setup. If the device routes HTTPS through a corporate proxy, the sandbox does
too.

### TLS-intercepting proxies

If your proxy performs TLS interception it presents its own CA, and the CLI runtime must
trust it.

**macOS.** Claude configures its CLI processes to trust the System keychain in addition
to bundled CA roots, so a corporate CA installed there normally just works. If requests
still fail certificate verification, the CA was likely added with *policy-restricted*
trust — `security add-trusted-cert -p ssl …` is trusted by Safari and Chrome but not
picked up by the CLI runtime's keychain reader. Re-add with full root trust:

```bash
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain /path/to/corp-ca.pem
```

If the certificate is MDM-managed and you cannot change how it is installed:

```bash
security find-certificate -a -p /Library/Keychains/System.keychain > ~/corp-ca.pem
launchctl setenv NODE_EXTRA_CA_CERTS "$HOME/corp-ca.pem"
```

`launchctl setenv` reaches apps launched from Finder or the Dock, which shell-profile
exports do not. It lasts until reboot; run it from a LaunchAgent at login to persist.

**Windows and Linux.** Install the corporate CA into the OS trust store the normal way
(`certlm.msc` → Trusted Root Certification Authorities on Windows;
`/usr/local/share/ca-certificates/` + `update-ca-certificates` on Debian/Ubuntu). If
inference still fails TLS verification, set `NODE_EXTRA_CA_CERTS` to the PEM as a
system-wide environment variable and fully restart the app.

Note that a TLS-intercepting proxy sees your prompts in cleartext. On a Bedrock
deployment chosen for regulatory reasons, confirm that is acceptable to your compliance
team before enabling interception on these hosts.
