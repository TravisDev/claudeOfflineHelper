# 10 — Claude Code CLI on Bedrock

The fallback path. Relevant when Claude Desktop is not viable — most often **Linux where
`downloads.claude.ai` cannot be allowlisted**, since no Linux offline installer exists.

The CLI has a far lighter network footprint: no VM workspace bundle, no Electron app, no
sandbox VM. Against Bedrock it talks to AWS and nothing else.

---

## When to choose this

| Situation | Use |
|---|---|
| Windows, offline installer available | **Claude Desktop** — full features, zero Anthropic egress |
| Linux, `downloads.claude.ai` allowlisted | **Claude Desktop** — works fine |
| Linux, `downloads.claude.ai` blocked | **Claude Code CLI** |
| Headless server, CI, or SSH-only access | **Claude Code CLI** |

The tradeoff is real: you get a terminal coding agent, not Chat / Cowork / Code in a
desktop UI. It is not a drop-in replacement for the desktop app — it is a different
product that happens to solve the same network problem.

---

## Install

The npm route needs a reachable npm registry (or your internal mirror):

```bash
npm install -g @anthropic-ai/claude-code
```

For a machine with no npm access, pack it on a connected machine and carry the tarball:

```bash
# connected machine
npm pack @anthropic-ai/claude-code
# -> anthropic-ai-claude-code-<version>.tgz

# target machine
npm install -g ./anthropic-ai-claude-code-<version>.tgz
```

Requires Node.js 18+. If the target has no Node either, stage a Node runtime the same
way — `nodejs` from your distro archives, or the official tarball from `nodejs.org`.

Verify:

```bash
claude --version
```

---

## Point it at Bedrock

Bedrock mode is environment variables, not a config file:

```bash
export CLAUDE_CODE_USE_BEDROCK=1
export AWS_REGION=us-east-1
export ANTHROPIC_MODEL='us.anthropic.claude-sonnet-5'
export ANTHROPIC_SMALL_FAST_MODEL='us.anthropic.claude-haiku-4-5'
```

Credentials come from the standard AWS chain — environment variables, `~/.aws/credentials`,
a named profile, SSO, or an instance role:

```bash
export AWS_PROFILE=bedrock-prod
# or
aws sso login --profile bedrock-prod
```

Make it permanent in `~/.bashrc`, `/etc/profile.d/claude-bedrock.sh`, or a systemd unit's
`Environment=` lines, depending on how it is launched.

Set the model to an **inference-profile ID** whose regional prefix matches your region —
`us.`, `eu.`, or `apac.`. Enable model access in the Bedrock console first; access is
granted per account and per region, and a model you cannot invoke fails at request time
rather than at startup.

Confirm what your account can actually call:

```bash
aws bedrock list-foundation-models --region "$AWS_REGION" \
  --query 'modelSummaries[?contains(modelId,`anthropic`)].modelId' --output table
```

### Private endpoints

```bash
export ANTHROPIC_BEDROCK_BASE_URL='https://bedrock-runtime.vpce-0abc.us-east-1.vpce.amazonaws.com'
```

GovCloud regions (`us-gov-*`) use FIPS endpoints
(`bedrock-runtime-fips.<region>.amazonaws.com`).

---

## Cut the remaining egress

```bash
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export DISABLE_TELEMETRY=1
export DISABLE_ERROR_REPORTING=1
export DISABLE_AUTOUPDATER=1
```

With these set and Bedrock configured, the allowlist is:

```
bedrock-runtime.<region>.amazonaws.com
bedrock.<region>.amazonaws.com
sts.amazonaws.com                       # profile / SSO auth
portal.sso.<region>.amazonaws.com       # SSO only
oidc.<region>.amazonaws.com             # SSO only
```

Plus your npm registry if you install or update through npm.

---

## Verify

```bash
claude -p "reply with exactly: ok"
```

A clean `ok` means inference is reaching Bedrock. If it hangs or errors:

```bash
# is the region reachable at all?
aws bedrock list-foundation-models --region "$AWS_REGION" >/dev/null && echo "control plane ok"

# are credentials resolving?
aws sts get-caller-identity
```

Run with `--debug` for the request-level detail.

---

## Corporate TLS interception

Same as the desktop app — the CLI runs on Node, so:

```bash
export NODE_EXTRA_CA_CERTS=/etc/ssl/certs/corp-ca.pem
```

Install the CA into the OS trust store as well
(`/usr/local/share/ca-certificates/` then `update-ca-certificates` on Debian/Ubuntu).

---

## Also available inside Claude Desktop

Worth knowing before you deploy the CLI separately: Claude Desktop ships Claude Code as
its **Code** tab, governed by `isClaudeCodeForDesktopEnabled` (default `true`). If the
desktop app works in your environment, you already have this. Deploy the standalone CLI
when the desktop app is what you cannot run.
