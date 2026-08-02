# Getting agent work out of the VM

The agent writes code in the VM. You push it from the Mac. This page is how the code crosses that
gap, and why the obvious shortcut is the one thing not to do.

The rule: **no credential that can push to your real repository ever enters the VM.** Everything
below is a way of honouring that while still being pleasant to use.

Why it matters more than it looks. The standing rule is that anything in the VM can leave the VM —
full egress, permissions skipped, and a prompt injection can arrive in a dependency's README or a
GitHub issue the agent reads. A push token in the guest is a token that can be read out and used.
"It's only for git" does not change what it is.

## Recommended: a scratch repo the VM can write and nothing else

One-time setup, then it is ordinary git in both directions. This is the simple default worth having.

1. Make an empty private repo — `<you>/agent-scratch`. It never holds anything that matters.
2. Mint a **fine-grained** personal access token scoped to exactly two repositories:
   - your real repo — Contents: **Read**
   - `agent-scratch` — Contents: **Read and write**
3. Put that token in the VM.

The property that makes this work: the VM can read your project and write only to a repo that
contains nothing. A compromised agent cannot push to your real branches, because the credential it
holds has no write access to them. If the token leaks, the loss is somebody writing junk to an empty
private repo.

Then the loop is boring, which is the point:

```
# in the VM
git push scratch HEAD:work/<topic>

# on the Mac, in your real checkout
git fetch scratch
git log -p scratch/work/<topic>     # read it
git merge --ff-only scratch/work/<topic>
git push                            # your real credential, host only
```

You are pulling objects into a repository whose config you control. Nothing from the VM is executed
on the Mac by fetching, and you read the diff before it goes anywhere.

## No setup at all: a patch over the pipe

For a one-off, or before you have bothered with a scratch repo. No token in the VM whatsoever — the
VM clones the public repo anonymously, commits locally, and the work comes out as text:

```
# on the Mac, in your real checkout
colima ssh --profile agent -- \
  git -C ~/work/<repo> format-patch --stdout origin/main > /tmp/<repo>.patch
git am /tmp/<repo>.patch            # or `git apply` to stage without committing
git log -p
git push
```

Clunky once the work is more than a few commits, and it loses branch structure. Fine for a fix.

## The shortcut, and what it costs: a shared mount

The obvious idea is to mount one folder into the VM so the agent and the Mac see the same working
tree, and push from the Mac with your real credentials. No patches, no scratch repo, nothing to sync.

It is genuinely the simplest thing, and it is the one option here that breaks the boundary the rest
of this project is built on. The reason is specific rather than purist:

A git repository's `.git/config` can set `core.pager`, `core.fsmonitor`, `core.sshCommand` and
aliases — all of which run commands. If the VM can write into that directory, it can write
`.git/config`. The next `git push` you run on the Mac executes whatever it put there, as your admin
user, with your Keychain and your tailnet. The same goes for anything else the host runs from that
folder: a Makefile, a build script, an `npm install` and its postinstall hooks.

So the workflow the mount exists to enable — `cd` into the shared folder on the Mac and push — is
precisely the trigger. It is not a risk you can be careful around, because being careful would mean
never using the folder from the host, which is the entire feature.

`have-agent-vm` writes `mounts: []` and its verify checks twice: the profile config, and `findmnt`
inside the running guest. Adding a mount will make that recipe fail and stay failed. That is the
check working, not a bug to route around.

If you take it anyway — a machine with nothing sensitive on it, a repo you would not mind losing —
do it knowingly, and understand that the VM is no longer a boundary against host compromise. It is
then a resource cap and a tidiness measure.

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
the VM's scratch token above, where per-repository scoping is the whole point.

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
