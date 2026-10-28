// Pure OTP helpers (no Firebase dependencies) so they can be unit tested.
const crypto = require("crypto");

const OTP_LENGTH = 6;
const OTP_TTL_MS = 10 * 60 * 1000; // codes expire after 10 minutes
const RESEND_COOLDOWN_MS = 30 * 1000; // matches the 30s cooldown in the app
const MAX_SENDS_PER_HOUR = 5;
const MAX_VERIFY_ATTEMPTS = 5;

const PURPOSES = ["verify", "reset"];

function normalizeEmail(email) {
  return String(email || "").trim().toLowerCase();
}

function isValidEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

function generateCode() {
  return crypto.randomInt(0, 10 ** OTP_LENGTH).toString().padStart(OTP_LENGTH, "0");
}

function hashCode(code, salt) {
  return crypto.createHash("sha256").update(`${salt}:${code}`).digest("hex");
}

function codesMatch(code, salt, expectedHash) {
  const actual = Buffer.from(hashCode(code, salt), "hex");
  const expected = Buffer.from(String(expectedHash || ""), "hex");
  return actual.length === expected.length && crypto.timingSafeEqual(actual, expected);
}

// One Firestore doc per (purpose, email). The email is hashed so doc IDs don't leak addresses.
function otpDocId(purpose, email) {
  const emailHash = crypto.createHash("sha256").update(normalizeEmail(email)).digest("hex");
  return `${purpose}_${emailHash}`;
}

// Decides whether a new code may be sent, given the existing OTP doc (or null).
// Returns { ok: true, windowStart, sendCount } or { ok: false, retryAfterMs }.
function checkSendAllowed(existing, now) {
  if (!existing) return { ok: true, windowStart: now, sendCount: 1 };

  const sinceLastSend = now - existing.lastSentAt;
  if (sinceLastSend < RESEND_COOLDOWN_MS) {
    return { ok: false, retryAfterMs: RESEND_COOLDOWN_MS - sinceLastSend };
  }

  const windowExpired = now - existing.windowStart >= 60 * 60 * 1000;
  if (windowExpired) return { ok: true, windowStart: now, sendCount: 1 };

  if (existing.sendCount >= MAX_SENDS_PER_HOUR) {
    return { ok: false, retryAfterMs: existing.windowStart + 60 * 60 * 1000 - now };
  }
  return { ok: true, windowStart: existing.windowStart, sendCount: existing.sendCount + 1 };
}

// Checks a submitted code against the stored OTP doc.
// Returns "ok", "missing", "expired", "locked" or "mismatch".
function checkCode(existing, code, now) {
  if (!existing || !existing.codeHash) return "missing";
  if (now > existing.expiresAt) return "expired";
  if (existing.attempts >= MAX_VERIFY_ATTEMPTS) return "locked";
  return codesMatch(String(code || ""), existing.salt, existing.codeHash) ? "ok" : "mismatch";
}

module.exports = {
  OTP_LENGTH,
  OTP_TTL_MS,
  RESEND_COOLDOWN_MS,
  MAX_SENDS_PER_HOUR,
  MAX_VERIFY_ATTEMPTS,
  PURPOSES,
  normalizeEmail,
  isValidEmail,
  generateCode,
  hashCode,
  codesMatch,
  otpDocId,
  checkSendAllowed,
  checkCode,
};
