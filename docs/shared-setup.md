# Shared setup

Set up once, before the first server, and shared by everything afterwards: the accounts the agents
sign in to and the tailnet your client devices and servers all join. Nothing here is repeated per
server.

The shape this assumes: your client devices — laptops, phones — and at least one always-on server,
typically a Mac mini on a desk somewhere, or a cloud machine if you would rather not own hardware.
Nothing below is limited to one server; add a second and it joins the same tailnet with the same
tagged key.

Each server keeps its own record locally, in `~/.agent-machine/server.md` on the machine itself.
There is no central inventory to maintain. That record is on the server, though, so keep a human copy
of each machine's details alongside the credentials below — the password manager named under Identity
is the natural place. `/setup` assembles that copy for you at the end of a run.

## Identity

The cookbook is meant to be reused, so everything else refers to the values here instead of
hardcoding them. Filling this block in is what makes a copy of the cookbook yours.

- Shared account (the account the agents sign in to): `<FILL IN>`
- Tailnet owner (the account that owns the Tailscale tailnet — may be a different address): `<FILL IN>`
- Password manager (where account passwords, 2FA codes, and the Tailscale auth keys live): `<FILL IN>`

## Accounts and resources

- [ ] Shared account — one account the agents sign in to, rather than one per server. Password and
      2FA recovery codes go in the password manager.
- [ ] Tailscale tailnet — clients and servers all join the same tailnet, which can live under any
      account. Each server puts its macOS host on the tailnet; agent sandboxes have no tailnet access at
      all, so there is one node per server.
      - In the admin console, define a tag in the ACL policy with yourself as tag owner: `tag:host`
        for the macOS hosts, e.g. `"tagOwners": { "tag:host": ["<your-account>"] }`.
      - Generate one reusable, non-ephemeral, pre-approved auth key for it (Settings → Keys). A
        tagged node is owned by the tailnet rather than a user and has key expiry disabled, so a
        server stays connected across reboots. This is what `join-tailnet` consumes as `TS_AUTHKEY`.
      - Add an `autoApprovers` entry for `tag:host` if you want exit-node routes approved
        automatically. Without it, `make-exit-node` stops at a gate on every server.
      - Treat the key as a secret — password manager only. It expires within 90 days, so regenerate
        before provisioning, or mint it from a Tailscale OAuth client.
      - Write the policy under "Tailnet policy" below before the first server joins.
      - Tailnet name / org: `<FILL IN>`
      - Reusable `tag:host` auth key — stored at: `<FILL IN>`
- [ ] Agent accounts and keys — set up once, servers authenticate against them. A server runs one or
      more of these; you sign in with `/login` inside a sandbox on first use.
      - Claude Code (Anthropic) — subscription login or `ANTHROPIC_API_KEY`: `<FILL IN>`
      - Codex (OpenAI) — ChatGPT plan or `OPENAI_API_KEY`: `<FILL IN>`

## Tailnet policy

Tailscale applies a default allow-all policy when the `acls` section is absent, so a server that
just joined can open a connection to every other device you own. Nothing in this design needs that.
Traffic goes one way: your devices reach the server, the server reaches nothing.

Write this before the first server joins, so there is never a window where it has full reach.

Access controls has two editors. Use the JSON one and replace the whole file — the allow-all you
are removing is the entire default policy, not a single rule you can edit in the visual editor.

```json
{
  "tagOwners": {
    "tag:host": ["<your-login@example.com>"],
  },

  "hosts": {
    // Any device you want the test below to prove is unreachable from a server. The alias is
    // yours to choose and is referenced by the tests block; client1, client2 numbers upwards as
    // you add devices. Add a line per device you care about.
    "client1": "<FILL IN — that device's tailnet IP, e.g. 100.101.102.103>",
  },

  "acls": [
    // You reach the server: SSH, and Screen Sharing on 5900.
    {
      "action": "accept",
      "src":    ["autogroup:member"],
      "dst":    ["tag:host:22,5900"],
    },
    // You route traffic through the server as an exit node.
    {
      "action": "accept",
      "src":    ["autogroup:member"],
      "dst":    ["autogroup:internet:*"],
    },
    // Your own devices reach each other. Drop this rule if you would rather they did not.
    {
      "action": "accept",
      "src":    ["autogroup:member"],
      "dst":    ["autogroup:self:*"],
    },
  ],

  // Deliberately absent: any rule with "tag:host" as src. That omission is the whole point —
  // a tagged node is owned by the tailnet rather than by a user, so it is not a member of
  // autogroup:member and matches no rule above as a source.

  "autoApprovers": {
    "exitNode": ["tag:host"],
  },

  "tests": [
    {
      "src":  "tag:host",
      "deny": ["client1:22", "client1:5900"],
    },
  ],
}
```

The `tests` block is what makes this durable. Tailscale runs it on every save and rejects the
policy if the assertion fails, so a future edit that accidentally grants the server reach is
refused rather than accepted quietly. Fill in the `hosts` entry or the test cannot run.

`tag:host` names a role — a machine this cookbook manages — and not a particular machine. Every
server gets the same one. That is what lets a single reusable key provision the next server with
no policy edit, and one ACL rule cover all of them. Naming a tag after a machine costs you both
and buys nothing: a device is already addressable by its name and tailnet IP, so the tag is not
how you identify it. It also multiplies the one mistake this policy exists to prevent, since the
protection is an absence — no rule naming the tag as a source — and every extra tag is another
place to forget it. Add a second tag when servers need different rules, `tag:exit-node` for the
ones that route traffic, and keep it a role rather than a name.

The `hosts` alias is the opposite case, which is why it is prompted for and this is not: it maps
to one device's IP, so it has to be chosen per device, and nothing outside the policy file reads
it. The tag is read by `join-tailnet` and by every rule here.

Two things this does not cover, both worth knowing rather than discovering:

- Exit-node traffic. Routing through the server means the server handles your traffic — that is
  what an exit node is. TLS protects contents; hostnames, DNS lookups, timing and volume are
  visible to whoever controls the machine. No policy changes this. If you would not route your
  traffic through a machine you are treating as potentially compromised, do not advertise it as an
  exit node.
- The LAN. ACLs govern the tailnet, not the physical network the server sits on. A compromised host
  can still reach other machines on its own subnet. Agent sandboxes cannot, since their egress
  policy blocks private ranges, but the host is not covered by either mechanism. Put the server
  somewhere you are comfortable with that, or segment it.

## Account safety — reduce ban-cascade risk

If the agents' shared account shares a recovery phone number or email with anyone's personal
account, the provider associates the two. Once associated, an automation flag on the agent account
risks spilling over onto the personal one. Check this rather than assuming it is clear — an account
created in a hurry usually reuses a recovery phone.

Break the linkage:

- [ ] Remove the shared phone number from at least one account's recovery settings. Give the agent
      account its own recovery phone, or none — never the personal account's number.
- [ ] Do not cross-list recovery email or phone in either direction.
- [ ] No shared payment method, storage plan, or family group between the two.

Keep them separated operationally:

- [ ] Separate browser profiles per account; never sign both into the same profile.
- [ ] Don't sign in and out of both back-to-back from the same session or device. Keep the personal
      account off the servers entirely.
- [ ] Give the agent account independent recovery options, so recovering it never touches the
      personal account.

Stay inside the provider's automation tolerances:

- [ ] Prefer a business or workspace tier over a consumer account for anything automation-heavy —
      those terms are built for programmatic use and consumer terms are not.
- [ ] Use official APIs with OAuth rather than scripted UI or IMAP logins, which automation
      detection flags hardest.
- [ ] Avoid bursty patterns: many rapid sign-ins or new-device logins from many IPs in a short
      window. Keep per-server behavior human-plausible.
- [ ] Watch for security notices on both accounts and answer any verification prompt immediately.

The bar: an agent-account suspension should be recoverable and contained, never able to take your
personal account down with it.
