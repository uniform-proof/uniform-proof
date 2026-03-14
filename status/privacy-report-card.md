# Worker Privacy Report Card

- Overall status: **PASS**
- Generated at (UTC): 2026-03-14T02:34:46.255Z
- Source repo: https://github.com/tubularity/uniform-zk
- Source commit: `20901c56bd5403730de73779a5eb9282600a6321`
- Verification run: https://github.com/tubularity/uniform-zk/actions/runs/23078455284
- Claim map: https://github.com/uniform-proof/uniform-proof/blob/main/status/worker-privacy-claim-map.json
- Verifier source snapshot: https://github.com/uniform-proof/uniform-proof/tree/main/status/verifier-source

## Check Results

| Check | Status | Duration (ms) |
| --- | --- | ---: |
| Privacy hardening guardrails | PASS | 2226 |
| Privacy hardening QA suite | PASS | 2243 |
| Billing gate auth suite | PASS | 2065 |

## Commands

- `npm run check:privacy-hardening --workspace=apps/web`
- `npm run test --workspace=apps/web -- src/server/domains/__tests__/privacy-hardening-qa.test.js`
- `npm run test --workspace=apps/web -- src/server/domains/__tests__/auth-domain-billing-gate.test.js`

## Claims Covered

- `no_contact_fields_in_worker_runtime`: Active worker account, session, and protected-content records do not include real-name, personal email, or phone identity fields.
- `no_auth_session_ip_persistence`: Worker app auth/session records are structured without stored IP or browser/device fingerprint fields.
- `wake_only_push_payloads`: Push payloads are reduced to wake/action references and exclude message-body or sender-context metadata.
- `actor_id_redaction_mode`: Active worker content records and client-visible payloads use scoped actor identifiers and omit direct account-ID fields.
- `legacy_union_contact_linking_removed`: Legacy union contact-linking surfaces and runtime linkage tables are removed from active proof scope, and the former member-profile endpoint is an explicit 410 tombstone.
- `legacy_worker_linkage_tables_removed`: Legacy worker linkage tables used for member-profile/contact-linking and old entitlement/auth-linkage flows are absent from the runtime schema snapshot.
- `billing_gate_fails_closed`: Billing-gated worker sign-in is denied when membership pass is missing, invalid, inactive, or verification is unavailable.

This report publishes reproducible verification evidence for worker-account privacy controls.
It does not attest to external infrastructure/provider logs outside app DB scope.
