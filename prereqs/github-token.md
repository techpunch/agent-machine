---
name: github-token
summary: A GitHub token limited to the repos agents work on, and main protected on each of them
when: during
---
Agents push their own branches and open pull requests. They do it with one token, stored on the
server and injected into requests by the sandbox proxy, so no agent can read it — but every agent
can use it while it runs, and so can anything that hijacks one. Two settings bound what that costs.

1. A fine-grained personal access token, at https://github.com/settings/personal-access-tokens:
   - Repository access: Only select repositories — the repos agents will work on, and nothing else.
   - Permissions: Contents read and write (push branches), Pull requests read and write (open PRs).
     Metadata read-only is added for you. Grant nothing else.
   - An expiry you will notice. Note the date in your password manager; an expired token shows up
     as agents that suddenly cannot push.

2. On each of those repos, Settings, then Rules, then Rulesets: a branch ruleset targeting the default
   branch with Restrict deletions, Block force pushes, and Require a pull request before merging, and
   nobody on the bypass list. Use a ruleset rather than a classic branch protection rule, which lets
   admins bypass it unless told otherwise — and the token acts as you, an admin.

The token cannot be read from a sandbox, so a leak is not the risk. Use is: while an agent runs it
can push any branch and open any PR in those repos. The ruleset is what keeps that off `main`, and
the repo list is what keeps it out of everything else you own.

You store it yourself, on the server, when `join-github` asks — `sbx secret set github`, which
prompts for it. Revoke it from the same settings page if the server is ever suspect.
