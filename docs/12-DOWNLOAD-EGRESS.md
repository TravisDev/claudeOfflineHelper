# 12 — Firewall request: fetching the installers

This is **not** the runtime allowlist. [02 — Network and egress](02-NETWORK-EGRESS.md)
covers what the installed application needs. This page covers what a machine needs in
order to **download** the installers in the first place, which is a different, smaller,
and more temporary set of hosts.

Two separate requests, depending on which machine you are unblocking. Most deployments
need only one of them.

---

## Request A — a staging machine that fetches from Anthropic

For the machine that builds the bundle. Ideally this is **not** the isolated machine; it
is a connected box that downloads the artifacts, which you then move across your
boundary.

| Host | Port | Protocol | Purpose |
|---|---|---|---|
| `claude.ai` | 443 | HTTPS | Version resolution only. `GET /api/desktop/<platform>/<arch>/<kind>/latest/redirect` returns a `307` naming the current build. No payload. |
| `downloads.claude.ai` | 443 | HTTPS | All artifact bytes: installers (`.msix`, `.deb`, `.dmg`), the VM workspace bundle, and the Claude CLI. |

That is the whole list. Two hostnames, both under the **same domain** — a single rule for
`claude.ai` plus `*.claude.ai` covers the entire download path.

### `anthropic.com` is never contacted

Verified by tracing a real download. The only TCP connections made are:

```
Trying 160.79.104.10:443 ...   > Host: claude.ai
Trying 35.190.46.17:443  ...   > Host: downloads.claude.ai
```

No `anthropic.com` connection, and no `anthropic.com` reference in any response header.
`anthropic.com` can stay blocked permanently — during download **and** at runtime, since
inference goes to Bedrock.

**Three distinct domains are involved here and they are easy to conflate.** Name
hostnames in the request rather than asking to "unblock Anthropic", which invites a
reviewer to grant or deny all three together:

| Domain | Needed? | What it is |
|---|---|---|
| `claude.ai` | **Yes** | Version resolution and artifact downloads |
| `claude.com` | Optional | Anthropic's documentation only |
| `anthropic.com` | **No** | Model API, analytics, telemetry — not used by this deployment |

### Allowlist by hostname, not IP

`downloads.claude.ai` resolved to `35.190.46.17` (Google Cloud) at the time of writing.
That address will change without notice. An IP-based rule breaks silently, usually
mid-rollout. Match on hostname/SNI.

If your perimeter filters by **vendor category** rather than hostname, `claude.ai` may
sit in the same category as `anthropic.com` and be denied alongside it even though you
only requested the former. Confirm how the existing block is implemented before filing.

**Optional, documentation only:**

| Host | Port | Purpose |
|---|---|---|
| `claude.com` | 443 | Anthropic's deployment documentation (`claude.com/docs/third-party/...`) |

### Justification text you can paste into a ticket

> Two Anthropic-operated hostnames are required on a single staging workstation to
> download Claude Desktop installer packages for offline deployment. `claude.ai` is used
> only to resolve the current version number and returns an HTTP redirect with no
> payload. `downloads.claude.ai` serves the installer files themselves. Both are HTTPS on
> port 443, outbound only. No inbound access, no other Anthropic hosts, and no
> conversation or business data traverses either host — this is software distribution
> only. Access can be time-boxed to the download window and revoked afterwards.

### What is deliberately not on this list

- `api.anthropic.com` — model inference. **Not needed**; inference goes to Bedrock.
- `platform.claude.com`, `a-api.anthropic.com`, `a-cdn.anthropic.com` — console and
  analytics. Not needed.
- `sentry.io`, `*.datadoghq.com` — telemetry. Not needed.
- `storage.googleapis.com` or any cloud-storage host. `downloads.claude.ai` serves the
  bytes directly under its own hostname; the redirect chain does not leave it.

The full redirect chain is exactly one hop, both hosts on the list above:

```
GET https://claude.ai/api/desktop/win32/x64/offline/latest/redirect
  -> 307 https://downloads.claude.ai/releases-offline/win32/x64/<version>/Claude-<commit>-offline.msix
  -> 200
```

### Gotcha: User-Agent

These endpoints return **HTTP 403** to clients that send no browser `User-Agent`. A
proxy that strips or rewrites `User-Agent` will make downloads fail in a way that looks
like a block. Test with:

```bash
UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36'
curl -s -o /dev/null -D - -A "$UA" \
  https://claude.ai/api/desktop/win32/x64/offline/latest/redirect | grep -i location
```

A `location:` header means the path is open. Note these endpoints reject `HEAD` with
**405** — use `GET` (as above) when testing.

---

## Request B — a target machine that pulls from your GitHub repo

If the isolated machine pulls the bundle from GitHub rather than receiving files by hand,
it needs GitHub, not Anthropic.

| Host | Port | Protocol | Purpose |
|---|---|---|---|
| `github.com` | 443 | HTTPS | Repository clone and the release-asset redirect |
| `release-assets.githubusercontent.com` | 443 | HTTPS | **Release asset payloads** |
| `api.github.com` | 443 | HTTPS | Only if using the `gh` CLI |

**The second host is the one people miss.** A release download issues a `302` from
`github.com` to `release-assets.githubusercontent.com`, and allowlisting only `github.com`
produces a download that starts and immediately fails. Many older allowlists carry
`objects.githubusercontent.com`; release assets no longer resolve there:

```
GET https://github.com/<owner>/<repo>/releases/download/<tag>/<asset>
  -> 302 https://release-assets.githubusercontent.com/github-production-release-asset/...
  -> 200
```

With this repository public, no authentication is needed — but the `-L` flag is
mandatory, since without it `curl` stops at the 302 and writes a zero-byte file.

If GitHub is entirely blocked, skip this request and move the files across your boundary
by whatever means you already use for software distribution. Nothing about the bundle
requires GitHub; it is only a convenient transport.

---

## Which request do I actually need?

| Situation | Request |
|---|---|
| Staging box downloads from Anthropic; files moved manually | **A only** |
| Staging box downloads; target pulls from your GitHub repo | **A and B** |
| Someone else supplies the bundle; target pulls from GitHub | **B only** |
| Files arrive by approved file-transfer process | **Neither** |

Requests A and B rarely need to apply to the same machine. Keeping them separate is
usually an easier approval: the connected staging box gets Anthropic access, and the
isolated machine gets either GitHub access or nothing at all.

---

## After installation

None of these hosts are needed at runtime. Once installed:

- **Windows offline installer** — needs only your Bedrock endpoint.
- **Rebuilt offline `.deb`** — needs only your Bedrock endpoint.
- **Stock `.deb`** — additionally needs `downloads.claude.ai` at every session start,
  because it fetches the VM bundle then. This is the one case where a download-time host
  becomes a permanent runtime dependency, and it is the reason the rebuilt package exists.

See [02 — Network and egress](02-NETWORK-EGRESS.md) for the runtime allowlist and
[06 — Linux install](06-LINUX-INSTALL.md) for that distinction.
