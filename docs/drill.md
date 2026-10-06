# Failover drill

`scripts/drill.sh` exercises the failover path end to end and records how long each part takes. It is the same script used to produce the numbers in [evidence.md](evidence.md).

## What the drill does

1. Confirms the region A health check starts healthy, and that both endpoints answer.
2. Writes one item to the API in region A, then fails region A by attaching a deny policy to the health function role.
3. Polls the Route 53 health check until it reports the region as unhealthy, and records the elapsed time.
4. Reads the item back through region B to confirm replication, then removes the deny policy and waits for region A to return to healthy.

No data plane resource is created or destroyed. The drill only adds and removes an IAM policy.

## Prerequisites

- The stack deployed in both regions, with the health check and role present.
- AWS CLI credentials for the account holding the stack.
- `drilldeny.json` in the working directory. Replace the account id and table name:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Deny",
      "Action": "dynamodb:PutItem",
      "Resource": "arn:aws:dynamodb:us-east-1:<ACCOUNT_ID>:table/<TABLE_NAME>"
    }
  ]
}
```
- A bash shell such as Git Bash on Windows.

The script reads the role name, the health check id, and the API endpoints straight from the CloudFormation stack, so no configuration is needed.

## Usage

```bash
./scripts/drill.sh
```

To keep the region failed for longer and give DNS caches time to expire, pass a hold time in seconds:

```bash
HOLD_SECONDS=240 ./scripts/drill.sh
```

The polling loops use a 600 second deadline, because IAM policy propagation to the endpoint is not instant.

## Expected output

```text
== Baseline health check (must be Healthy before strike) ==
  Healthy (16/16 checkers healthy)

== Baseline health ==
A: 200 (must be 200)
B: 200 (must be 200)

== Strike region A: attach DrillDeny ==
  t+10s : Healthy (16/16 checkers healthy)
  ...
  t+137s : Unhealthy (4/16 checkers healthy)

FLIP detected at t+137s (A -> Unhealthy)
A: 503 (must be 503)
B: 200 (must be 200)

== Re-check RPO via endpoint B ==
{"pk": "item:rp-...", "id": "rp-...", "data": "rpo-sample"}

== Failback: delete DrillDeny ==
RESTORE at t+515s (A -> Healthy)

== Summary ==
flip (A->Unhealthy)   : t+137s
restore (A->Healthy)  : t+515s
```

## Watching DNS during a drill

`scripts/watch-dns.sh` logs the API region and the DNS answer every 10 seconds, which is how the DNS part of the recovery time was measured. Point it at your own endpoint:

```bash
API_HOST=api.example.com ./scripts/watch-dns.sh
```

## Teardown

Deleting a stack that contains a versioned bucket requires removing object versions and delete markers first, otherwise the stack ends in `DELETE_FAILED`. The hosted zone can only be deleted after the certificate validation records are removed.
