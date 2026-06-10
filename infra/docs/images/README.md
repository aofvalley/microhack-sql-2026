# Documentation images

This folder holds the images embedded in the student documentation.

Architecture diagrams (generated from [`../diagrams/`](../diagrams/README.md), official Azure
icons — safe to commit):

- `architecture.png` — per-student architecture (example: user01).
- `access-flow.png` — Challenge 0 access flow (example: user01).
- `network.png` — per-student network & NSG model (example: user01).
- `isolation.png` — subscription isolation (one resource group per student).

Deployer screenshot:

- `web-deployer.png` — the deployer web UI (automatic capture, safe to commit).

> The student access guide ([`../access-guide.md`](../access-guide.md)) and Challenge 0 describe
> the Portal / Bastion / SSMS steps in text. Portal step screenshots are intentionally omitted —
> they depend on a live tenant and would expose tenant-specific data, so the steps are written to
> be followed without them.
