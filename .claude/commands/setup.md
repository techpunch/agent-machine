---
description: Set this Mac up as an agent server, start to finish, with no docs to read
---

Walk the user through configuring this server. They may never have seen this repo, or may
have set a box up months ago and forgotten all of it. Assume neither reading nor memory.

Recipe names are yours, not theirs. Talk in outcomes — "reach it from anywhere", "run agents
on it" — and let `bin/cookbook` map those to recipes. Never ask them to pick a recipe.

## The flow

1. Run `./bin/cookbook goals`. It runs every verify, so it takes a moment and may ask for
   sudo once — say so before it stalls.

2. Open with where the server already is, in one or two sentences. If everything is `done`,
   skip to step 7 instead of offering work that is finished.

3. Ask which outcomes they want, using AskUserQuestion with `multiSelect: true`. One option
   per `available` goal, labelled with its summary, described from the goal file's prose.
   Leave out goals already `done`. If a goal is `blocked`, do not offer it — say what it is
   waiting on only if they ask.

   Keep the order `goals` printed them in, always. That order is the `order:` field in each
   goal file, and it is one sequence over every goal, not over the ones still available —
   dropping the `done` ones leaves the rest in the right order automatically. It exists
   because this was got wrong by eye twice already. Re-sorting by what seems most
   interesting is not a judgement call you have been left; if the order looks wrong, the fix
   is `order:` in the goal file, not the menu.

   For a fresh box, say plainly that the first four together are the usual answer, so
   somebody who does not want to think can pick them and move on.

4. Run `./bin/cookbook preflight <goals>`, and walk the output one item at a time. This is
   the part that saves them an afternoon, so do not paste it as a wall of text.

   - Take the `before-you-start` items first, and do not move on until each is confirmed.
   - Start anything slow immediately. FileVault decryption in particular runs for a long
     time and blocks the finish, so get it going while you do everything else.
   - If something is physical and they do not have it — the HDMI dongle — say so now and
     let them decide whether to order it and continue later, or drop that goal for today.
   - Do the parts you can. You cannot create their Tailscale account, but you can check
     whether one is already connected, read back what a key needs to look like, and confirm
     it worked afterwards.

5. Show `./bin/cookbook plan <goals>` as a short summary of what is about to happen and
   roughly how long, then apply.

   Most plans include a root recipe, and sudo prompts on `/dev/tty`, which Claude Code's
   shell does not have — with or without a leading `!`. So hand the user the command to run
   in a terminal window on the server, rather than running it yourself and hitting the
   guard. Ask them to paste the output back; read it and carry on from there.

       ./bin/cookbook apply <goals>

6. Handle what comes back:

   - Exit 3, a gate. Not a failure — a step the machine cannot take. Show the gate text
     verbatim, because it names the exact toggle, dialog or physical action. Wait for them.
     Then re-run the same command; everything already applied stays applied.
   - Exit 1, a failure. Read the verify output and say what actually broke and what it
     means. Say which recipes did apply before it stopped — the chain halts but nothing
     rolls back.
   - Exit 2, blocked. A recipe with no scripts because a design decision is open. Name the
     decision from its `blocked_by` rather than routing around it.
   - Secrets. When a recipe needs `TS_AUTHKEY`, ask for it and pass it inline for that one
     run: `TS_AUTHKEY='...' ./bin/cookbook apply <goals>`. Never write it to `server.env`,
     never echo it back.

7. Finish with what they can now do, in commands rather than concepts. The two that matter
   day to day are on the server: `agents` to attach to the terminal grid, and
   `sbx run --clone claude` to put one project in its own sandbox. Then two things they will
   need later and will not think to ask about:

   Use the server's short name in every command you show them — `ssh <slug>`, never
   `ssh <user>@<slug>.<tailnet>.ts.net`. MagicDNS is on by default and resolves the short
   name from any client taking Tailscale DNS, so the domain is noise they would retype
   every time.

   MagicDNS says nothing about who they log in as, though, and a laptop's login name is
   usually not the server's admin user. So give them the `~/.ssh/config` alias from the
   record first, as a once-per-client step, and every command after it is one word. Do not
   assume the names match — check, or use the alias, rather than handing them a `ssh <slug>`
   that fails on a machine you never looked at.

   Say which machine each command runs on, every time. A list that goes `ssh <slug>` and then
   `scp <slug>:...` reads as one session, but the second runs on the client — and a `mkdir`
   that makes sense on a laptop looks absurd typed on the server, where that directory is the
   state dir already. Label the client commands as client commands.

   - The run log, at `~/.agent-machine/run.log` — every action, gate and failure, with
     timestamps. `./bin/cookbook log` shows the tail. Tell them where it is; it is the thing
     they will want when something misbehaves in three weeks.

   - The server's own record. Run `./bin/cookbook record`, which writes
     `~/.agent-machine/server-record-<slug>.md` from `server.env` and the ledger: name and slug,
     admin user, tailnet name and IP, FileVault state, what is applied, pointers to where the
     secrets live, and how to revoke access. Do not assemble this by hand — a hand-written
     copy is stale by the next run, and the point of generating it is that it never is.

     Print it for them too, so it is in front of them rather than being homework. Fill in
     `SERVER_LOCATION` in `server.env` if they will tell you where the box physically sits;
     otherwise the record carries a `<FILL IN>` and says so.

     Then say where to keep it, and why, because it holds no secrets and "keep it off the
     server" sounds arbitrary without the reason: it is a recovery document, and every
     situation that sends them looking for it — machine stolen, dead, or unreachable — is one
     where the server cannot be read. Being on the box is what makes it fetchable from another
     machine, and the file ends with the `scp` line to do that; being *only* on the box is what
     makes it useless. So the copy that counts goes in their password manager, or a private
     note on the laptop or phone they already use as a client. Not in this repo, which is
     shared and pushed, and never inside an agent sandbox, where anything can leave.

     Have them run that `scp` from a client machine, not from the server: it is the honest
     test that remote access works, and it leaves the off-server copy behind as a side effect
     rather than as a chore. Tell them where it lands — `~/.agent-machine/` on the client,
     the same directory name a server uses — so a year from now there is one place to look,
     on whichever machine they are holding.

     Tell them to re-run `./bin/cookbook record` after any later run, since it is a snapshot.

   - How to prove unattended recovery, if they applied always-on but not headless. A verify
     that reads pmset settings back is not a machine you have watched come up, and they will
     want to know the difference before the server is somewhere inconvenient. Give them the
     reboot test from a client — `ssh -t <slug> sudo shutdown -r now`, then poll until it
     answers — and say plainly that it does not test `autorestart`, which only fires on real
     power loss and can only be tested by pulling the plug. `recipes/make-always-on/recipe.md`
     has both. If they took headless too, do not raise this: pass one already proved the
     reboot half in front of them.

## Timing is the point

The single most valuable thing here is telling people things at the right moment rather than
all at once.

Say early what they must own or start — the dongle, the FileVault decrypt, the Tailscale
key. Say at the exact moment what to do physically. `make-headless` is the case that matters:
it deliberately proves the server survives a reboot untouched *before* anything is unplugged.
When it gets there, be explicit that the proof passed and it is now safe to swap the monitor
for the dongle and take the keyboard away — and that if they had done it earlier they might
have been left with an unreachable machine.

Do not warn about a step three phases before it happens. Do not spring a physical
requirement on someone whose monitor is already in a box.

## Rules

- The script decides; you converse. Never resolve dependencies, re-order recipes, or skip
  something because it looks done. `bin/cookbook` verifies before applying and skips what is
  satisfied.
- Look values up; ask for choices. An IP, a hostname, whether something is already installed —
  read those off the machine rather than making them answer. But a name they will live with,
  or which of their devices a rule covers, is theirs to pick: ask, and offer a default so the
  answer can be "fine". Filling one in silently is how someone ends up with a policy naming a
  device they do not have.
- If a recipe is wrong, fixing it is the job, not a detour — see "This project corrects
  itself" in `CLAUDE.md`. But never edit one just to make a verify pass: understand the
  cause first, because a wrong `apply.sh` runs as root on every server that pulls this repo.
  Mid-setup, say what is broken and offer to fix it rather than silently going quiet on it.
- Do not send them to the docs. If an explanation is needed, give it in a sentence. The docs
  exist for people who want the reasoning, not as a dependency of getting set up.
