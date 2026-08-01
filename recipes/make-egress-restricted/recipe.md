---
name: make-egress-restricted
summary: Default-deny outbound network from the agent containers, with an allowlist.
requires: [have-containers]
root: no
status: blocked
blocked_by: deferred — make-vm-network-bounded covers full egress with no inward path; this is for proprietary work or durable secrets in the VM
design: docs/host-agent-design.md — "Network posture"
---

Default-deny egress with an allowlist, seeded from an existing agent-sandbox list and tuned by
watching what gets denied.

Two things trigger this and neither has happened yet: proprietary code in the VM, where the source is
the asset even with no credentials present, or more than one durable secret living there, at which
point "nothing worth stealing" stops carrying the argument.

The design doc's "Network posture" section has the reasoning and the four things worth reaching for
when this gets built — the research/build split, a doc broker, a seeded allowlist, and denial logging.
Read it before scripting; the hard part is documentation access, not the firewall.
