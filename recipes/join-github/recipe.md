---
name: join-github
summary: A GitHub token stored in sbx, so agents can push branches and open PRs without seeing it.
requires: [have-agent-sandbox]
needs: [github-token]
root: no
gates: storing the GitHub token, which only you type
---

Agents push their own work. Each one clones its repo inside the sandbox over HTTPS, works on a
branch, and pushes that branch to GitHub — and with `gh`, opens the pull request. You review and merge
on GitHub.

The token they push with is stored on the Mac, in sbx's Keychain store, and never inside a sandbox:

```
sbx secret set github     # prompts for the token; run it yourself, as the admin user
```

The proxy adds it to requests from every sandbox to `github.com`, `api.github.com` and the other
GitHub hosts Docker lists for the `github` service. An agent can use it and cannot read it, so it
cannot be copied out and used later from somewhere else.

What it does not stop is use. While an agent runs, it — or a prompt injection riding in one — can
push any branch and open any PR the token allows. Two things bound that, both in
[`../../prereqs/github-token.md`](../../prereqs/github-token.md): a fine-grained token limited to the
repos agents work on, and a ruleset on each of them that keeps everything off `main` without a pull
request. With both, the worst case is junk branches and PRs in repos agents were already working in.

Why this rather than pushing from the Mac, which is what this cookbook used to insist on, is in
[`../../docs/pushing-agent-code.md`](../../docs/pushing-agent-code.md). In short: the old rule existed
because a token in a sandbox could be stolen, and injection removed that. What is left is bounded by
GitHub's own settings, and the gain is that nobody has to fetch and push by hand.

## The mini's own `gh` login is a different thing

If `gh` is signed in on the Mac itself, `sbx secret set github --command 'gh auth token'` would inject
that session instead and keep it refreshed. It is not the default here because a `gh` login is
usually your whole account rather than a few repos, and GitHub's own docs steer fine-grained tokens
away from `gh auth login`. A scoped token stored directly is both simpler and narrower.

## Not yet confirmed on a real server

That the token is injected into the agent sandbox at all. `github` is a built-in service, but
Docker's credentials page says the proxy injects only for services the sandbox's kit declares, and
the claude kit the sandbox is built on declares only `anthropic`. If `gh auth status` in a pane shows
no token, the cookbook's kit has to declare `github` as well — Docker documents `scheme: basic` with
`username: x-access-token` as the form for Git over HTTPS.

And that the injected token reaches `git push` over HTTPS, not only `gh` and the API. Docker lists
`github.com` among the hosts the `github` service is injected for, which says it does, but its docs
only describe the `gh` case. Push a branch from the sandbox on the first run and fix this section.
