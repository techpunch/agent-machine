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
session is auto-logged in. The login keychain is unlocked by the GUI login, so with auto-login it
should be unlocked by the time you can SSH in, and `-T /usr/bin/security` on the item means the CLI
can read it without a GUI prompt. But it can relock on a timeout, and this is a common enough failure
that other tools hit it too. Check it directly rather than inferring:

```
security show-keychain-info ~/Library/Keychains/login.keychain-db
```

An answer means unlocked. A password prompt means locked, and `security unlock-keychain` is the fix.
If the read does not work at all, the failure is safe — it times out and the recipe gates — and the
fallback is to store the item over Screen Sharing instead.

# Part 2 — Where agents may run

## Yolo mode on the host is for this cookbook only

Two places can run Claude Code with permissions skipped, and they are not interchangeable.

| Where | What for | Why it is allowed |
|---|---|---|
| The host Mac | This cookbook, and nothing else | Provisioning the machine needs root, and the only inputs are recipes from this repo |
| The agent sandbox | Everything else, always | Own kernel, nothing from the Mac mounted, credentials injected rather than held |

The host case rests entirely on there being no untrusted content in the loop. You wrote the recipes,
you reviewed them, and they read no external input. Point that same session at a project and the
argument collapses — source you did not write, dependencies that execute code, issues and docs the
agent reads, any one of which can carry a prompt injection. On the host there is nothing left to
catch it: it runs as your admin user, with your Keychain, your SSH keys, your files, and whatever the
server can reach on its own LAN. The tailnet is the one thing bounded here rather than open, because
the policy denies the server as a source — but that is a single control, and everything else on this
list is untouched by it.

So every other project goes in the agent sandbox — `ssh <server> -t agents`. Not "usually" — every one. The exception you make because
a change is small, or because starting a sandbox is a faff right now, is the one that removes the
boundary altogether. If a task seems to need host access, treat that as a reason to look harder at
the task, not as a reason to run the agent outside a sandbox.

This is also why the host is worth protecting more than it first looks. Its Keychain holds the
provisioning secrets and every token the sandbox has injected — the Claude, Codex and GitHub sign-ins
— so an agent running on the host directly would hold everything the sandbox is built to keep from
it.

## What may live in the agent sandbox

Every agent on this machine runs in one sandbox with permissions skipped. That is defensible because
of what is kept out of it and what it cannot reach: nothing from the Mac is mounted, and the
credentials it uses are injected rather than held. Break either half and it stops being defensible.

## The rule

Anything inside the sandbox can leave it. Treat everything you put there as publishable.

That is not a figure of speech here. The network preset is `allow-all`, chosen so agents can read any
documentation site, so there is no allowlist between a prompt injection buried in a dependency's
README and any server on the internet. What the design does is make sure the sandbox holds nothing
whose loss would hurt beyond the source of the projects in it, and nothing that reaches the Mac.

## Never put these in the sandbox

- SSH keys, or an agent forwarded from your laptop. sbx forwards the host's SSH agent into every
  sandbox by default, which on this machine means whatever arrived with `ssh -A`;
  `have-agent-sandbox` turns that off and its verify checks it stays off
- Cloud credentials of any kind: AWS, GCP, Cloudflare, provider API keys — as files or variables
- Any credential as a readable value. The Claude, Codex and GitHub sign-ins are the deliberate
  exceptions, and they are exceptions only because they are injected: stored on the Mac, added to
  requests by the proxy, never readable inside
- `.env` files, or a repo whose git history contains one
- Password-manager exports, recovery codes, session cookies
- Anything mounted from the Mac. The sandbox clones what it works on; a writable folder from the Mac
  is a path to running commands on it, which [`pushing-agent-code.md`](pushing-agent-code.md) walks
  in full

And one thing about what is already there: every project in the sandbox can read every other. A repo
that must not leak at all — where the source itself is the asset — belongs in a sandbox of its own,
or not on this machine.

## The sign-ins are not an exception

You might expect signing the agents in to put long-lived tokens inside the sandbox. It does not, and
this is the one place where the design is better than it looks.

`/login` is typed inside the sandbox, but the OAuth flow terminates on the host. The session token is
stored in the host keychain, and the proxy injects it into outbound requests on the way past — the
sandbox sees a sentinel value. So the agent can make authenticated calls and cannot read, log or
exfiltrate the credential, and recreating the sandbox does not cost you the login.

Codex arrives at the same place from the other end: `sbx secret set openai --oauth` runs the flow on
the host to begin with, and the tokens go to the host keychain and are injected the same way. The
GitHub token agents push with is stored with `sbx secret set github` and works the same way again —
see [`../recipes/join-github/recipe.md`](../recipes/join-github/recipe.md).

That has three consequences worth being explicit about:

- An injected token cannot be stolen, but it can be used — by the agent, and by anything that hijacks
  it, for as long as it runs. For the agents' own accounts that means spent quota. For GitHub it means
  pushes, which is why that token is limited to some repos and `main` is protected; see
  [`../prereqs/github-token.md`](../prereqs/github-token.md).
- An API key is not a safer alternative to a subscription. It is injected by the same proxy, so it
  buys no isolation the subscription does not already have, and it swaps a flat subscription for
  metered billing.
- Revocation is worth knowing before you need it: sign out everywhere from your Anthropic account
  settings, from your ChatGPT ones for Codex, and revoke the GitHub token from GitHub's settings. Do
  that the moment anything looks off — an unexplained session, unfamiliar usage, a branch nobody
  asked for.

What this does not cover is the model's own output. A compromised agent cannot steal a token, but it
can still put whatever it can read into a request to anywhere. The credentials are safe; the source
in the sandbox is not.

## Out, and not sideways

All sandbox traffic goes through a proxy on the host. Under `allow-all` it reaches the internet
freely. What matters for this design is the other direction: the host, its localhost services, and
the networks it sits on.

The tailnet is closed by its own policy. [`shared-setup.md`](shared-setup.md) names no rule with
`tag:host` as a source, so the server cannot open a connection to a device you own — from the sandbox,
from the host, as root, or after everything else here has failed. Tailscale enforces that on the
receiving device, which makes it the one control in this design a compromised server cannot switch
off, and the one that covers the host rather than only the sandbox.

The host's own services are the part `allow-all` does not cover. The preset is a `**` allow rule,
and Docker no longer lists the host or private ranges among what is blocked regardless of policy: a
sandbox reaches the Mac's services through `host.docker.internal`, and the Mac's LAN and tailnet
addresses are private addresses like any other. So
[`have-agent-sandbox`](../recipes/have-agent-sandbox/recipe.md) adds deny rules for `localhost`,
`host.docker.internal` and the private ranges, which outrank `**`, and its verify tries the Mac's
SSH from inside a sandbox.

The LAN goes with them. It is out of scope — nothing on it trusts this machine, so reaching it would
get an agent nothing a random internet host would not; put the Mac on a network where that stays
true — but denying it costs nothing, because no agent here needs it.

## Research versus containment, and why research won

Default-deny and an agent that needs to read a wide, unpredictable range of documentation are in
genuine conflict. You cannot enumerate every site an agent might want, and an allowlist broad enough
to cover the long tail has stopped being a firewall. A blocked agent does not say so either — it falls
back to memory and writes confidently outdated code.

The danger in reading the web is having broad outbound access and something worth stealing in the
same place at the same time. This design resolves that by keeping the second half small rather than
the first: the credentials are injected, nothing from the Mac is inside, and the projects in the
sandbox are ones whose source you can afford to lose. So the preset is `allow-all`.

If a project does not fit that — the source is the asset — it does not belong in the shared sandbox.
The preset is global and set once, so a deny-by-default sandbox means a server initialized with
`SBX_POLICY=balanced`, which allows AI providers, package managers, code hosts and registries and holds
anything else for approval. On this server, per-sandbox deny rules can narrow a sandbox —
`sbx create --deny-network <host>`, or `sbx policy deny network --sandbox <name> <host>` after — but a
deny rule takes precedence over every allow, so they block destinations rather than build an
allowlist.

Under any stricter preset, `./bin/cookbook denials` shows what was blocked and what is waiting for
approval, and the kit tells agents to say when a request was refused rather than work around it.

## Working shape

```
ssh <server> -t agents                                     # the grid, inside the sandbox
git clone https://github.com/<you>/<project> ~/<project>   # once per project
cd ~/<project> && claude                                   # or codex
```

The sandbox is long-lived and kept. The sign-ins are not inside it, so recreating it costs you the
checkouts and whatever was installed, nothing else — and the checkouts are on GitHub as soon as they
are pushed.

Recreate it deliberately rather than habitually. Worth doing after work you did not trust, or when you
want a known-clean starting point — a sandbox that has been running untrusted code for a month has
accumulated whatever that code left behind. Not worth doing after every task, because installed
tooling goes with it.

## Getting code back out

Agents push branches to GitHub with the injected token and open pull requests; you review and merge
there. Why that is allowed, what bounds it, and the alternative for a repo where no agent should push
at all are in [`pushing-agent-code.md`](pushing-agent-code.md).
