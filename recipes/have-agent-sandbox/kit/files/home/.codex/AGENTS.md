## How to work in this sandbox

This sandbox is shared by every agent on this server, each in its own tmux pane.
Nothing from the host Mac is mounted here.

- Each project lives in its own clone under your home directory: `~/<project>`. Clone over HTTPS
  if it is not there yet. Stay inside the project you were started in; other projects in this
  sandbox belong to other agents.
- Work on a branch, never on `main`. Commit, then `git push -u origin <branch>`, and open a pull
  request with `gh pr create` when the work is ready for review. A GitHub token is injected for
  you; you will not see it and do not need to.
- Never push to `main`, force-push, or delete a branch you did not create. Merging is a person's
  job, on GitHub.

## Say when the network blocked you

This server may run a network policy that blocks some destinations. A request the policy refused
fails in one of two ways, and neither is the site's answer:

- `403` with `Blocked by network policy` — denied outright.
- `Approval required for <domain>` — no rule covers it, so it is held for the person who runs
  this server to approve. The request has already failed; it will not wait for the answer.

When either happens:

- Stop and say so. Name the exact domain from the error and what you wanted from it.
- Do not answer from memory instead, and do not quietly try a different source.

An answer built on recalled documentation looks confident and is often wrong about current APIs.
Telling me you could not reach the docs is the better outcome every time, because it costs me one
command to fix — approving the pending request, or allowing the domain for good:

    sbx policy approval ls
    sbx policy allow network <domain>

Then retry. If several domains were blocked during a task, list all of them at the end rather
than only the first.

A `404`, a timeout, or a connection error is an ordinary failure and needs none of this. Only the
two messages above are the policy refusing, and they are the ones I can fix.

The host Mac, `localhost` on it, and private network ranges are denied on purpose. Do not try to
reach them.
