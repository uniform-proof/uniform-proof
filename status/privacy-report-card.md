# Worker Privacy Report Card

- Overall status: **PASS**
- Generated at (UTC): 2026-03-11T02:51:21.151Z
- Source repo: https://github.com/tubularity/uniform-zk
- Source commit: `de65b4769b162a2d49a9bc277858b714d9e07925`
- Verification run: https://github.com/tubularity/uniform-zk/actions/runs/22934348175
- Claim map: https://github.com/uniform-proof/uniform-proof/blob/main/status/worker-privacy-claim-map.json
- Verifier source snapshot: https://github.com/uniform-proof/uniform-proof/tree/main/status/verifier-source

## Check Results

| Check | Status | Duration (ms) |
| --- | --- | ---: |
| Privacy hardening guardrails | PASS | 1795 |
| Privacy hardening QA suite | PASS | 2087 |
| Billing gate auth suite | PASS | 1780 |

## Commands

- `npm run check:privacy-hardening --workspace=apps/web`
- `npm run test --workspace=apps/web -- src/server/domains/__tests__/privacy-hardening-qa.test.js`
- `npm run test --workspace=apps/web -- src/server/domains/__tests__/auth-domain-billing-gate.test.js`

## Claims Covered

- `no_contact_fields_in_worker_runtime`: Worker runtime account/session/content records do not include real-name, personal email, or phone identity fields.
- `no_auth_session_ip_persistence`: Worker app auth/session records are structured without stored IP or browser/device fingerprint fields.
- `wake_only_push_payloads`: Push payloads are reduced to wake/action references and exclude message-body or sender-context metadata.
- `actor_id_redaction_mode`: Content responses in worker runtime redact direct account IDs and expose actor identifiers in actor mode.
- `billing_gate_fails_closed`: Billing-gated worker sign-in is denied when membership pass is missing, invalid, inactive, or verification is unavailable.

This report verifies application/runtime privacy controls for worker accounts.
It does not attest to external infrastructure/provider logs outside app DB scope.
