# Disaster Recovery on AWS — Quiz

Five quick questions. Click to reveal the answers.

---

**Q1.** Your SLA allows 4 hours of downtime and up to 6 hours of data loss. Which is the cheapest DR strategy that satisfies it?

<details>
<summary>Answer</summary>

**Backup & Restore.** Nothing runs in the DR region — you just restore from backups when disaster strikes. Hours-scale RTO/RPO at minimal cost.

</details>

---

**Q2.** What is the difference between RTO and RPO?

<details>
<summary>Answer</summary>

**RTO (Recovery Time Objective)** = how long you may be *down* before service is restored.
**RPO (Recovery Point Objective)** = how much data you may *lose*, measured as the time window between the last good backup/replica and the failure.

</details>

---

**Q3.** In a Pilot Light setup, what makes the RDS read replica the "pilot light"?

<details>
<summary>Answer</summary>

The read replica continuously receives replicated data, so it is always nearly current. On failover you **promote** it to a standalone primary — a few minutes of work versus hours of restoring from a snapshot. It is the small flame kept burning so the full system can start fast.

</details>

---

**Q4.** Route 53 failover routing relies on… what, exactly?

<details>
<summary>Answer</summary>

**Health checks.** Route 53 probes the primary endpoint (HTTP/HTTPS/TCP, every 30s by default — 10s with fast checks). When the primary is unhealthy, DNS responses flip to the secondary record set automatically.

</details>

---

**Q5.** Your DR region was hand-built once by clicking through the console "just to get it working". What is wrong with this picture?

<details>
<summary>Answer</summary>

Almost everything. A DR region that is not defined as **Infrastructure as Code** will drift from production and fail when you need it most. The rule: `terraform apply` from the same modules must recreate the whole DR environment except the data.

</details>

---

**Scoring:** 5/5 — run the next game-day drill. 3–4 — re-read the strategies table. Below 3 — start from the TL;DR and try again.
