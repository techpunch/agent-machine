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
   roughly how long, then run `./bin/cookbook apply <goals>`.

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

   - The run log, at `~/.agent-machine/run.log` — every action, gate and failure, with
     timestamps. `./bin/cookbook log` shows the tail. Tell them where it is; it is the thing
     they will want when something misbehaves in three weeks.

   - Their own copy of the server's details, kept off the server. Do not just mention this —
     assemble it and hand it to them ready to paste, because nobody does it if it is
     homework. Read `server.env` and the ledger and print:

     - The machine's name and slug, the admin user, the Tailscale IP, and where the box
       physically is.
     - Whether FileVault is off, and where the admin password lives — they need it to log in
       at the keyboard, and this cookbook deliberately never took it from them.
     - Pointers, never values: which password-manager entry holds the tailnet auth key, and
       that the server has a Keychain item under `agent-machine`. Never print a secret.
     - What is applied, from the ledger.
     - How to revoke, which is what they will want when they cannot reach the machine at all:
       remove the node in the Tailscale admin console, sign out everywhere from the Claude
       account to kill the token in the sandbox, and rotate the reusable auth key so a stolen
       machine cannot rejoin.

     Say where to put it: their password manager, or a private note on the laptop or phone
     they already use as a client. Not in this repo, and never inside an agent sandbox, where
     anything can leave.

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
- If a recipe is wrong, fixing it is the job, not a detour — see "This project corrects
  itself" in `CLAUDE.md`. But never edit one just to make a verify pass: understand the
  cause first, because a wrong `apply.sh` runs as root on every server that pulls this repo.
  Mid-setup, say what is broken and offer to fix it rather than silently going quiet on it.
- Do not send them to the docs. If an explanation is needed, give it in a sentence. The docs
  exist for people who want the reasoning, not as a dependency of getting set up.
