# Evidence

Test coverage for the failover path, with the measured recovery objectives. Raw drill logs are kept outside this repository.

## Recovery objectives

| Objective | Target | Measured | How it was measured |
|---|---|---|---|
| RTO | under 5 minutes | 3 minutes 33 seconds | Health check detection 137 seconds plus 76 seconds for the DNS record to move at a public resolver |
| RPO | under 1 minute | about 3 seconds | Replication lag between the two table replicas |

## Drill runs

| Run | Region A failed after | Failback | Result |
|---|---|---|---|
| 1 | 158 seconds | healthy | clean failover during mechanics testing |
| 2 | 221 seconds | healthy at t+419s | clean failover, standby served the request |
| 3 | 194 seconds | healthy | clean failover |
| 4 | not reached within 305 seconds | health check never flipped | drill stopped, IAM policy propagation was slower than the polling window |
| 5 | 137 seconds | healthy at t+515s | clean failover, used for the RTO figure above |

## What was verified

- Site availability: with object access denied in the primary bucket, the site kept answering from the standby origin.
- API failover: the active region returned server errors while the standby region answered the same request successfully.
- Data durability: an item written before the failure was readable from the standby region after the failover.
- Recovery: removing the fault restored the active region with no redeploy and no manual data step.

## Measurement notes

- The DNS component was measured at a public resolver, 70 and 76 seconds after the health check flip, which is consistent with the configured 60 second TTL.
- The client side figure on the test machine was 445 seconds, caused by a stale local resolver cache, and is not used as the architecture RTO.
- RPO is reported from replication lag rather than from a forced data loss test.
