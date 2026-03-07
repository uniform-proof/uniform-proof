# Proof: Wake-only push payloads

Claim:
Push notification metadata is reduced to wake/action references and excludes sender/body context fields.

Evidence snippets:

```js
// apps/web/src/lib/privacy-flags.js:17-22
// Hard-cut defaults: privacy controls are always-on in active runtime.
export const PUSH_WAKE_ONLY = true;
```

```js
// apps/web/src/lib/expo-push.js:121-153
function buildWakeOnlyPayload(data) {
  const payload = {};
  const sourceType = normalizeSourceType(data?.source_type || data?.category);
  const sourceId = normalizeRefHintValue(data?.source_id);

  if (sourceType) payload.source_type = sourceType;
  if (sourceId) payload.source_id = sourceId;

  const sourceMetadata =
    data?.source_metadata && typeof data.source_metadata === "object" && !Array.isArray(data.source_metadata)
      ? data.source_metadata
      : null;

  const refHint = {};
  for (const key of PUSH_REF_HINT_KEYS) {
    const value = sourceMetadata?.[key] ?? data?.[key];
    const normalizedValue = normalizeRefHintValue(value);
    if (!normalizedValue) continue;
    refHint[key] = normalizedValue;
  }

  if (Object.keys(refHint).length > 0) payload.ref_hint = refHint;
  payload.wake_only = true;
  return payload;
}
```

```js
// apps/web/src/lib/expo-push.js:551-560
const dispatchEntries = dispatchRows.map((row) => ({
  row,
  message: {
    to: row.push_token,
    sound: "default",
    title,
    body,
    priority,
    data: PUSH_WAKE_ONLY ? buildWakeOnlyPayload(data) : data,
  },
}));
```

```js
// apps/web/src/server/domains/__tests__/privacy-hardening-qa.test.js:754-766
expect(sentPayload).toEqual({
  source_type: "message",
  source_id: "msg_123",
  ref_hint: {
    message_id: "msg_123",
    conversation_id: "thread_123",
    context_id: "ctx_123",
  },
  wake_only: true,
});
expect(sentPayload.tenantId).toBeUndefined();
expect(sentPayload.source_metadata).toBeUndefined();
```

```bash
# Verification command run March 7, 2026
npm run test --workspace=apps/web -- src/server/domains/__tests__/privacy-hardening-qa.test.js -t "push wake-only mode strips metadata down to action \+ ref hints"
# Result: PASS (1 test, 0 failures)
```

What this proves:
- Runtime sends wake-only payload objects by default.
- Only whitelisted ref hints are preserved.
- Sensitive metadata fields are explicitly absent in tested output.

Last verified against code: March 7, 2026.
