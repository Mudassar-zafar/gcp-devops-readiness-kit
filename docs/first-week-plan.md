# The First Week

What actually happens in the first five working days of an engagement. No discovery theater, no month of meetings. The structure below is the same Assess → Plan → Build loop the whole engagement runs on; week one is simply its first pass.

---

## Day 1 · Access and baseline (Assess)

- Receive **Viewer-level access only**. Write access comes later, and only where needed.
- Run the read-only assessment (`scripts/gcp-assess.sh`) across the target projects.
- Map what exists: projects, networks, clusters, pipelines, monitoring, billing structure.
- **Deliverable by end of day:** a short written baseline. What is there, what surprised us, what we still need access to.

## Day 2 · Deep pass (Assess)

- IAM review: who and what can touch production, and through which paths.
- Cost snapshot: top ten spend lines, obvious leaks (idle disks, unused IPs, over-provisioned nodes).
- CI/CD review: how code reaches production today, where it can fail silently.

## Day 3 · Findings and plan (Plan)

- **Deliverable: a one-page prioritized report.** Every finding in one of three buckets:
  - 🔴 **Critical** · fix this week (exposure, single points of failure)
  - 🟡 **Quick win** · high value, low effort (cost leaks, missing alerts)
  - 🟢 **Structural** · plan properly (IaC coverage, environment parity, upgrade strategy)
- Walk through it together, agree the order. You own the priorities; we own the execution.

## Day 4 to 5 · First fixes (Build)

- Execute the agreed criticals and quick wins.
- Everything lands as code: reviewed, versioned, revertible. No console-only changes.
- **Deliverable by end of week:** fixes merged, before/after evidence, and the backlog for week two.

---

## The cadence after week one

| Rhythm | What you get |
|---|---|
| **Every working day** | A short written update: done, blocked, next. If nothing moved, the update says so. |
| **Urgent issues** | Response within 4 business hours, usually much faster. |
| **Weekly** | A 30-minute review: what shipped, what the metrics say, what is next. The loop restarts. |

Silence is the only thing we consider a failure mode. Everything else is just work.
