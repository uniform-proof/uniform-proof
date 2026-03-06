# Uniform Proof Artifacts

This public repository contains claim-specific proof artifacts linked from Section 2 ("How we protect identity") on the Uniform Technical Information page.

## Proof Button Mapping

- `Device-key session authentication` -> `proofs/device-key-session-auth.md`
- `No auth/session IP persistence in app DB` -> `proofs/no-auth-session-ip-persistence.md`
- `Wake-only push payloads` -> `proofs/wake-only-push-payloads.md`
- `Actor-ID content identity mode` -> `proofs/actor-id-content-identity-mode.md`
- `Billing vault separation` -> `proofs/billing-vault-separation.md`

## Publication Guardrails

- Include only the minimum snippet needed to validate the claim.
- Do not publish secrets, env var values, internal hostnames, or private keys.
- Do not publish full internal modules when a short excerpt proves the control.
- Prefer migration and policy snippets for data-model claims.

Last updated: March 6, 2026
