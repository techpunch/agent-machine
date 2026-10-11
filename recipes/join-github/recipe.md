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

## What Docker's own people have said about it

The docs say only that the `github` service "gives the agent access to the `gh` CLI". Two things
said on Docker's tracker go further:

- `git push` over HTTPS is covered. A Docker engineer, explaining why a GitLab kit could not do what
  GitHub's built-in credential already does, wrote that GitHub's "Bearer traffic goes to
  `api.github.com` while git-over-HTTPS goes to `github.com` — two different domains, so each inject
  rule matches"
  ([docker/sbx-releases#552](https://github.com/docker/sbx-releases/issues/552)). The proxy adds the
  credential to every request to those hosts, so git never has to ask for one.
- `gh` needs the token stored before the sandbox is created. Injection starts as soon as it is
  stored, but the placeholder `GH_TOKEN` that tells `gh` to try is set only at creation
  ([#477](https://github.com/docker/sbx-releases/issues/477),
  [#25](https://github.com/docker/sbx-releases/issues/25)). That is why `have-shared-sandbox`
  requires this recipe.

## Not yet confirmed on a real server

That a sandbox created as `claude` gets the `github` service at all. Docker's credentials page says
the proxy injects for services the kit declares, and the claude kit declares only `anthropic` — but
the same page says a stored `github` secret is injected into requests to its listed hosts, and #25
was reported from a Claude Code sandbox whose `gh` worked once the placeholder was set. In a pane, run
`gh auth status`, then push a branch. If either fails, the cookbook's kit has to declare `github` —
Docker documents `scheme: basic` with `username: x-access-token` as the form for Git over HTTPS —
and this section should say which one it was.
