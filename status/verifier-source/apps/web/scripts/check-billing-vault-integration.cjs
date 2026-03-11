#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const webRoot = path.resolve(__dirname, "..");

const checks = [
  {
    file: "src/lib/billing-vault-client.js",
    patterns: [
      "resolveOrCreateSubjectByProviderRefs",
      "redeemBillingClaimTokenForMembershipPass",
      "verifyMembershipPass",
      "issueBillingClaimTokenByRecoveryCode",
      "syncStripeSubscriptionLifecycle",
      "createStripePortalByRecoveryCode",
    ],
  },
  {
    file: "src/app/api/payment/verify-iap/route.js",
    patterns: ["createProviderClaimAndRecovery", "redeemBillingClaimTokenForMembershipPass"],
  },
  {
    file: "src/app/api/webhooks/stripe/route.js",
    patterns: ["syncStripeSubscriptionLifecycle"],
  },
  {
    file: "src/app/auth/register/route.js",
    patterns: [
      "billing_claim_token",
      "redeemBillingClaimTokenForMembershipPass",
      "createProviderClaimAndRecovery",
      "billing_gated_accounts",
    ],
  },
  {
    file: "src/server/domains/billing-domain.js",
    patterns: [
      "createStripePortalByRecoveryCode",
      "verifyMembershipPass",
      "billing_gated_accounts",
      "Manage with recovery code",
    ],
  },
  {
    file: "src/app/api/billing/claim/consume/route.js",
    patterns: ["redeemBillingClaimTokenForMembershipPass", "membership_pass"],
  },
  {
    file: "src/app/api/billing/recovery/claim/route.js",
    patterns: ["issueBillingClaimTokenByRecoveryCode", "membership_pass"],
  },
  {
    file: "src/server/domains/auth-domain.js",
    patterns: ["billing_gated_accounts", "verifyMembershipPass", "BILLING_REQUIRED"],
  },
];

const failures = [];
const forbiddenPaths = [
  "src/app/api/payment/create-intent/route.js",
  "src/server/billing/entitlement-sync.js",
];
const forbiddenMarkers = [
  {
    file: "src/server/domains/billing-domain.js",
    patterns: ["account_subscription_states"],
  },
  {
    file: "src/server/domains/auth-domain.js",
    patterns: ["account_subscription_states"],
  },
];

for (const check of checks) {
  const absPath = path.join(webRoot, check.file);
  if (!fs.existsSync(absPath)) {
    failures.push(`${check.file} is missing`);
    continue;
  }

  const source = fs.readFileSync(absPath, "utf8");
  const missingPatterns = check.patterns.filter((pattern) => !source.includes(pattern));
  if (missingPatterns.length > 0) {
    failures.push(
      `${check.file} is missing required markers: ${missingPatterns.join(", ")}`,
    );
  }
}

for (const file of forbiddenPaths) {
  const absPath = path.join(webRoot, file);
  if (fs.existsSync(absPath)) {
    failures.push(`${file} must be removed in billing-vault hard-cut mode`);
  }
}

for (const check of forbiddenMarkers) {
  const absPath = path.join(webRoot, check.file);
  if (!fs.existsSync(absPath)) {
    continue;
  }
  const source = fs.readFileSync(absPath, "utf8");
  const hitPatterns = check.patterns.filter((pattern) => source.includes(pattern));
  if (hitPatterns.length > 0) {
    failures.push(
      `${check.file} contains forbidden legacy markers: ${hitPatterns.join(", ")}`,
    );
  }
}

if (failures.length > 0) {
  console.error("[billing-vault-integration] Failed:");
  for (const failure of failures) {
    console.error(` - ${failure}`);
  }
  process.exit(1);
}

console.log("[billing-vault-integration] OK");
