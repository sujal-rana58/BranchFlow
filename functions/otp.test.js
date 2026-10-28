const test = require("node:test");
const assert = require("node:assert");
const otp = require("./otp");

test("generateCode returns six digits", () => {
  for (let i = 0; i < 200; i++) assert.match(otp.generateCode(), /^\d{6}$/);
});

test("codesMatch accepts only the right code", () => {
  const hash = otp.hashCode("042817", "salt");
  assert.ok(otp.codesMatch("042817", "salt", hash));
  assert.ok(!otp.codesMatch("042818", "salt", hash));
  assert.ok(!otp.codesMatch("042817", "other", hash));
  assert.ok(!otp.codesMatch("123456", "salt", hash));
});

test("otpDocId ignores email case and whitespace", () => {
  assert.strictEqual(otp.otpDocId("verify", " A@B.com "), otp.otpDocId("verify", "a@b.com"));
  assert.notStrictEqual(otp.otpDocId("verify", "a@b.com"), otp.otpDocId("reset", "a@b.com"));
});

test("checkSendAllowed enforces cooldown and hourly limit", () => {
  const now = 10_000_000;
  assert.deepStrictEqual(otp.checkSendAllowed(null, now), { ok: true, windowStart: now, sendCount: 1 });

  const recent = { lastSentAt: now - 5_000, windowStart: now - 5_000, sendCount: 1 };
  assert.strictEqual(otp.checkSendAllowed(recent, now).ok, false);

  const capped = { lastSentAt: now - 60_000, windowStart: now - 600_000, sendCount: otp.MAX_SENDS_PER_HOUR };
  assert.strictEqual(otp.checkSendAllowed(capped, now).ok, false);

  const oldWindow = { lastSentAt: now - 60_000, windowStart: now - 3_700_000, sendCount: 5 };
  assert.deepStrictEqual(otp.checkSendAllowed(oldWindow, now), { ok: true, windowStart: now, sendCount: 1 });
});

test("checkCode handles expiry, lockout and mismatch", () => {
  const now = 1_000_000;
  const doc = { salt: "s", codeHash: otp.hashCode("111111", "s"), attempts: 0, expiresAt: now + 1000 };
  assert.strictEqual(otp.checkCode(null, "111111", now), "missing");
  assert.strictEqual(otp.checkCode(doc, "111111", now), "ok");
  assert.strictEqual(otp.checkCode(doc, "222222", now), "mismatch");
  assert.strictEqual(otp.checkCode(doc, "111111", now + 2000), "expired");
  assert.strictEqual(otp.checkCode({ ...doc, attempts: otp.MAX_VERIFY_ATTEMPTS }, "111111", now), "locked");
});
