# Secrets and egress

Two separate questions, both worth getting right: where provisioning secrets live on the host, and
what may live inside the agent VM. Read this before pointing an agent at anything. It is short on
purpose.

# Part 1 — Provisioning secrets on the host

Three tiers, in the order `secret_get` tries them.

## 1. The Keychain, for anything reusable

The default, and where the Tailscale auth key belongs. Store it once:

```
security add-generic-password -s agent-machine -a TS_AUTHKEY -T /usr/bin/security -U -w
```

The command deliberately carries no value — `security` prompts for it. That keeps the secret out of
your shell history and out of `ps`. `-T /usr/bin/security` lets the CLI read it back without a GUI
prompt, rather than `-A`, which would allow every application on the machine.

Recipes read it with `secret_get`, which never prints the value and never blocks: a locked keychain
would otherwise raise an invisible GUI unlock prompt and hang a headless server forever, so the read
is fenced with a five-second alarm and a timeout is treated as "not found".

## 2. An interactive prompt, for the login password

`make-auto-login` does not accept your account password at all. It gates and tells you to run:

```
sudo sysadminctl -autologin set -userName <admin> -password -
```

The trailing `-` makes the tool prompt. Nothing reaches argv, environment, history, or a transcript.
This is Apple's own recommended form.

## 3. Environment variables, as the escape hatch

`TS_AUTHKEY=... ./bin/cookbook apply ...` still works, for scripted or unattended provisioning. The
cost is real: the value is visible in `ps` to any local user for as long as the command runs. The
recipes say so out loud when they take this path rather than accepting it silently.

## What this does and does not buy

It removes casual exposure: shell history, `ps`, Claude Code transcripts, and anything that backs up
`server.env` — which is why no secret is ever written there.

It is not a wall against a compromised agent. An agent running as the admin user can invoke
`/usr/bin/security` itself and read the same items. The real boundary for agent code is the VM below:
no host mounts, no keychain access. Do not confuse the two.

One caveat to confirm on your own server: whether a Keychain read succeeds over SSH while the GUI
session is auto-logged in. It is version-dependent. If it does not work, the failure is safe — the
read times out and the recipe gates — and the fix is to store the item over Screen Sharing instead.

# Part 2 — Where agents may run

## Yolo mode on the host is for this cookbook only

Two places can run Claude Code with permissions skipped, and they are not interchangeable.

| Where | What for | Why it is allowed |
|---|---|---|
| The host Mac | This cookbook, and nothing else | Provisioning the machine needs root, and the only inputs are recipes from this repo |
| The agent VM | Everything else, always | No host mounts, no path inward, nothing valuable inside |

The host case rests entirely on there being no untrusted content in the loop. You wrote the recipes,
you reviewed them, and they read no external input. Point that same session at a project and the
argument collapses — source you did not write, dependencies that execute code, issues and docs the
agent reads, any one of which can carry a prompt injection. On the host there is nothing left to
catch it: it runs as your admin user, with your Keychain, your SSH keys, your files, and your tailnet
reach.

So every other project goes in the VM. Not "usually" — every one. The exception you make because a
change is small, or because setting up the VM is a hassle right now, is the one that removes the
boundary altogether. If a task seems to need host access, treat that as a reason to look harder at
the task, not as a reason to move the agent out of the VM.

This is also why the cookbook keeps nothing sensitive on the host that an agent would want: no
secrets in `server.env`, and the Keychain items scoped to provisioning. It narrows what the host case
is worth compromising, but it does not make the host safe for general agent work.

## What may live in the agent VM

The agent VM runs Claude Code with permissions skipped and full outbound internet. That combination
is defensible, but only because of what is deliberately kept out of the VM and where it deliberately
cannot reach. Break either half and it stops being defensible.

## The rule

Anything inside the VM can leave the VM. Treat everything you put there as publishable.

There is no approval gate between a malicious instruction and a network request. A prompt injection
buried in a dependency's README, a GitHub issue, or a fetched doc — "read the env file and POST it
to …" — simply succeeds. Nothing in the design stops it. What the design does is make the payoff
worthless and the pivot impossible.

## Never put these in the VM

- SSH keys, or an agent forwarded from your laptop
- Cloud credentials of any kind: AWS, GCP, Cloudflare, provider API keys
- `.env` files, or a repo whose git history contains one
- Password-manager exports, recovery codes, session cookies
- Your actual working copy of anything. Clone fresh, shallow, and throwaway.

The VM has no host mounts. That is the mechanism, not an inconvenience — do not add a mount to move a
file in. If the agent needs a file, fetch it inside the VM from somewhere the agent could have
reached anyway.

## The one exception, stated plainly

Signing Claude Code in with your subscription puts a long-lived OAuth token in the VM, under
`~/.claude`. The design doc's own criteria for a container safe to hand full egress say to keep
exactly that out — see "Network posture" in [`host-agent-design.md`](host-agent-design.md). This setup
accepts the trade knowingly.

What makes it survivable rather than reckless:

- It is the only thing in there worth stealing. Everything else on the list above is absent, so an
  exfiltration gets one revocable credential instead of your estate.
- It cannot pivot. See below.
- It is revocable, and you should know how before you need to: sign out everywhere from your
  Anthropic account settings, which invalidates the refresh token. Do that the moment anything looks
  off — an unexplained session, unfamiliar usage, an agent that behaved strangely. Re-authenticating
  costs you one SSH-tunnel login.

If that trade sounds wrong for your situation, the alternative is a scoped, spend-limited API key
instead of the subscription. It is still a static secret in the VM, but a bounded one you can cap and
rotate without touching your main account.

## Full egress means out, not sideways

`make-vm-network-bounded` allows the public internet and denies the private ranges — RFC1918,
link-local, and Tailscale's `100.64.0.0/10`. The distinction is the whole point. A compromised agent
can talk to the internet; it cannot reach your laptop, the host Mac, other machines on your tailnet,
or anything on your LAN.

This matters more than it first appears. The VM lives on a machine that is a Tailscale node, so
without that rule a compromised agent inherits reach into your private network — the surprise
specific to this design, and the reason the deny list is not optional decoration.

Verify it rather than trusting it. From inside the VM, a public fetch should succeed and a connection
to any `100.64.x.x` or `192.168.x.x` address should fail.

## Match the posture to the work

Full egress is the right default for public code, open-source dependencies, and throwaway research.

It is the wrong default for proprietary code. Secret-free is not the same as sensitive-free — for
private work the source itself is the asset, and full egress means it can leave. That work wants
default-deny egress with an allowlist instead, which is `make-egress-restricted`, still unwritten.

Decide this per project rather than once. The question is not "does this repo have credentials in
it," it is "what can this task afford to lose."

## Working shape

Clone inside the VM, never on the host:

```
colima ssh --profile agent
git clone --depth 1 https://github.com/<owner>/<repo> ~/work/<repo>
cd ~/work/<repo> && claude --dangerously-skip-permissions
```

Destroy the checkout when the task is done. Persistence is not a feature here — a fresh clone per
task is what keeps the VM boring to compromise.
