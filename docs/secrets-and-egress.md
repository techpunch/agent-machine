# Secrets and egress

Two separate questions, both worth getting right: where provisioning secrets live on the host, and
what may live inside an agent sandbox. Read this before pointing an agent at anything. It is short on
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
`/usr/bin/security` itself and read the same items. The real boundary for agent code is the sandbox
below: its own kernel, no view of the Mac's filesystem, no keychain access. Do not confuse the two.

One caveat to confirm on your own server: whether a Keychain read succeeds over SSH while the GUI
session is auto-logged in. It is version-dependent. If it does not work, the failure is safe — the
read times out and the recipe gates — and the fix is to store the item over Screen Sharing instead.

# Part 2 — Where agents may run

## Yolo mode on the host is for this cookbook only

Two places can run Claude Code with permissions skipped, and they are not interchangeable.

| Where | What for | Why it is allowed |
|---|---|---|
| The host Mac | This cookbook, and nothing else | Provisioning the machine needs root, and the only inputs are recipes from this repo |
| A sandbox | Everything else, always | Own kernel, no path inward, nothing valuable inside |

The host case rests entirely on there being no untrusted content in the loop. You wrote the recipes,
you reviewed them, and they read no external input. Point that same session at a project and the
argument collapses — source you did not write, dependencies that execute code, issues and docs the
agent reads, any one of which can carry a prompt injection. On the host there is nothing left to
catch it: it runs as your admin user, with your Keychain, your SSH keys, your files, and your tailnet
reach.

So every other project goes in a sandbox. Not "usually" — every one. The exception you make because
a change is small, or because starting a sandbox is a faff right now, is the one that removes the
boundary altogether. If a task seems to need host access, treat that as a reason to look harder at
the task, not as a reason to run the agent outside a sandbox.

This is also why the cookbook keeps nothing sensitive on the host that an agent would want: no
secrets in `server.env`, and the Keychain items scoped to provisioning. It narrows what the host case
is worth compromising, but it does not make the host safe for general agent work.

## What may live in an agent sandbox

A sandbox runs an agent with permissions skipped. That is defensible because of what is kept out of
it and where it cannot reach. Break either half and it stops being defensible.

## The rule

Anything inside a sandbox can leave it. Treat everything you put there as publishable.

The egress policy is deny-by-default rather than open, which narrows this considerably compared with
the open-egress VM it replaced — but "narrow" is not "none". There is no approval gate between a malicious
instruction and a request to an allowed domain, and a prompt injection buried in a dependency's
README or a GitHub issue does not need an unusual destination to do damage. What the design does is
make the payoff worthless, the pivot impossible, and the destinations few.

## Never put these in a sandbox

- SSH keys, or an agent forwarded from your laptop
- Cloud credentials of any kind: AWS, GCP, Cloudflare, provider API keys
- Any credential that can push to a repository you care about. Pushing to your real branches is the
  host's job. A fine-grained token that can only write a throwaway scratch repo is the one
  deliberate exception — see [`pushing-agent-code.md`](pushing-agent-code.md)
- `.env` files, or a repo whose git history contains one
- Password-manager exports, recovery codes, session cookies
- Your actual working copy. Use `sbx run --clone`, which gives the sandbox its own clone rather than
  your working tree.

`--clone` is the mechanism, not a preference. The default mount is read-write and an agent that can
write `.git/config` in a directory you later run git in has a path to executing commands on your Mac.
[`pushing-agent-code.md`](pushing-agent-code.md) walks that attack in full.

## The one exception, stated plainly

Signing the agent in with your subscription puts a long-lived OAuth token inside the sandbox. This
setup accepts that knowingly.

What makes it survivable rather than reckless:

- It is the only thing in there worth stealing. Everything else on the list above is absent, so an
  exfiltration gets one revocable credential instead of your estate.
- It cannot pivot. See below.
- It is revocable, and you should know how before you need to: sign out everywhere from your
  Anthropic account settings, which invalidates the refresh token. Do that the moment anything looks
  off — an unexplained session, unfamiliar usage, an agent that behaved strangely.

If that trade sounds wrong for your situation, the alternative is a scoped, spend-limited API key
instead of the subscription — still a static secret, but a bounded one you can cap and rotate
without touching your main account.

## Out, and not sideways

All sandbox traffic goes through a proxy on the host. HTTP and HTTPS reach allowed domains only, and
non-HTTP protocols — raw TCP, UDP including DNS, ICMP — are blocked at the network layer. The host,
its localhost services, and private ranges are unreachable.

That last part matters more than it first appears. The server is itself a Tailscale node, so without
it a compromised agent would inherit reach into your private network — your laptop, other machines on
the tailnet, anything on the LAN. That was the surprise specific to this design, and it is now
structural rather than something we maintain.

Verify it rather than trusting it. `have-agent-sandbox`'s verify creates a probe sandbox and removes
it; if you want to check egress by hand, try reaching a `100.64.x.x` address from inside one and
watch it fail.

## Research versus containment, the tension you will actually feel

Default-deny and an agent that needs to read a wide, unpredictable range of documentation are in
genuine conflict, and no configuration removes it. You cannot enumerate every site an agent might
want, and an allowlist broad enough to cover the long tail has stopped being a firewall.

The resolving idea is that the danger is not reading the web. It is having broad outbound access and
something worth stealing in the same place at the same time. Exfiltration needs both. So aim never to
have both at once rather than choosing between research and safety:

- Keep the research and the secret-holding apart. A sandbox with a wide policy and no credentials can
  read whatever it likes and has nothing to leak. The sandbox holding a token and a real repo runs
  under the baseline. `sbx policy allow network ... --sandbox <name>` scopes a rule to one sandbox,
  which is what makes this practical rather than theoretical.
- Put one trusted endpoint in front of documentation instead of allowlisting the web. A doc broker —
  Context7, or a self-hosted equivalent — collapses thousands of libraries into a single allowed
  host, or none at all if you run it locally.
- Curate rather than paste. Documentation and package hosts earn a place; telemetry and analytics do
  not.

The honest tradeoff: the cleaner you keep egress, the more research friction you accept. Nothing
gives unrestricted reading and zero exfiltration risk together.

Watch for the failure mode too. Default-deny fails quietly — a blocked agent falls back to memory and
writes confidently outdated code rather than telling you it could not reach the docs. If output
quality drops for no visible reason, check what is being denied before assuming the model got worse.

## Match the posture to the work

The default preset is a compromise, and you can move it. `sbx policy` tightens or loosens what a
sandbox can reach, per sandbox if you want.

Proprietary code is the case that deserves thought. Secret-free is not the same as sensitive-free —
for private work the source itself is the asset, and any allowed domain is a way out. Tighten the
policy for that work rather than assuming the default covers it.

Decide per project rather than once. The question is not "does this repo have credentials in it", it
is "what can this task afford to lose".

## Working shape

```
sbx run --clone claude        # a sandbox on a clone of the current repo
git fetch sandbox-<name>      # bring the work back, on the host
sbx rm <name>                 # done with it
```

Destroy the sandbox when the task is done. Persistence is not a feature here — a fresh sandbox per
task is what keeps it boring to compromise.


## Getting code back out

A sandbox clones over HTTPS with no credential, so it can read a public repo and commit locally, and
that is all it should be able to do. Pushing happens on the Mac, with credentials that never enter a
sandbox.

How the work crosses that gap — fetching from the sandbox as a git remote, a scratch repo for when
the agent should push directly, why a shared mount is the one shortcut to avoid, and how to scope the
token you push with — is [`pushing-agent-code.md`](pushing-agent-code.md).
