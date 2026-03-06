# Proof: Wake-only push payloads

Claim:
Push notifications are wake-only and avoid sender text or message body content in metadata payload.

Evidence snippets:

```js
// apps/web/src/lib/privacy-flags.js
export const PUSH_WAKE_ONLY = true;
```

```js
// apps/web/src/lib/expo-push.js
function buildWakeOnlyPayload(data) {
  const payload = {};
  // copies only source_type/source_id and approved ref hints
  payload.wake_only = true;
  return payload;
}
```

```js
// tests assert no sender handle or source_metadata is sent
// apps/web/src/server/domains/__tests__/privacy-hardening-qa.test.js
expect(sentPayload.source_metadata).toBeUndefined();
```

What this proves:
- Notification payloads are intentionally reduced to action/reference hints in wake-only mode.
