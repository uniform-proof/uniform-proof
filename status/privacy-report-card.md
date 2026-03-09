# Worker Privacy Report Card

- Overall status: **PASS**
- Generated at (UTC): 2026-03-09T19:20:25.994Z
- Source repo: https://github.com/tubularity/uniform-zk
- Source commit: `21bda10902544966fbbe05ddb8ad87011d3281ba`

## Check Results

| Check | Status | Duration (ms) |
| --- | --- | ---: |
| Privacy hardening guardrails | PASS | 1785 |
| Privacy hardening QA suite | PASS | 1872 |
| Billing gate auth suite | PASS | 820 |

## Commands

- `npm run check:privacy-hardening --workspace=apps/web`
- `npm run test --workspace=apps/web -- src/server/domains/__tests__/privacy-hardening-qa.test.js`
- `npm run test --workspace=apps/web -- src/server/domains/__tests__/auth-domain-billing-gate.test.js`

This report verifies application/runtime privacy controls for worker accounts.
It does not attest to external infrastructure/provider logs outside app DB scope.
