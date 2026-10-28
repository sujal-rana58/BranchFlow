/**
 * BranchFlow Cloud Functions — Email OTP
 *
 * Callable functions used by the Flutter app:
 *   - requestOtp            : generate a 6-digit code and email it
 *                             (purpose: 'verify_email' | 'reset_password')
 *   - verifyEmailOtp        : confirm a sign-up code and mark the account verified
 *   - resetPasswordWithOtp  : confirm a reset code and set a new password
 *
 * Codes are never returned to the client. Only a SHA-256 hash is stored in
 * Firestore (`otp_codes`, locked down by security rules), with an expiry,
 * a resend cooldown and a maximum number of attempts.
 */
const crypto = require('crypto');
const nodemailer = require('nodemailer');
const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore, FieldValue, Timestamp } = require('firebase-admin/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret, defineString, defineInt } = require('firebase-functions/params');
const logger = require('firebase-functions/logger');

initializeApp();
const db = getFirestore();

// -------------------------------------------------------------
// CONFIG (set with `firebase functions:secrets:set` / .env)
// -------------------------------------------------------------
const SMTP_USER = defineSecret('SMTP_USER');
const SMTP_PASS = defineSecret('SMTP_PASS');
const SMTP_HOST = defineString('SMTP_HOST', { default: 'smtp.gmail.com' });
const SMTP_PORT = defineInt('SMTP_PORT', { default: 465 });
const MAIL_FROM = defineString('MAIL_FROM', { default: '' });

const OTP_TTL_MINUTES = 10;
const RESEND_COOLDOWN_SECONDS = 60;
const MAX_ATTEMPTS = 5;

const PURPOSES = {
  verify_email: {
    subject: 'Verify your BranchFlow email',
    heading: 'Verify your email address',
    intro: 'Use the code below to finish creating your BranchFlow account.',
  },
  reset_password: {
    subject: 'Your BranchFlow password reset code',
    heading: 'Reset your password',
    intro: 'Use the code below to reset your BranchFlow password.',
  },
};

const callableOptions = { secrets: [SMTP_USER, SMTP_PASS] };

// -------------------------------------------------------------
// HELPERS
// -------------------------------------------------------------
function normalizeEmail(raw) {
  const email = String(raw || '').trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new HttpsError('invalid-argument', 'Please enter a valid email address.');
  }
  return email;
}

function otpDocId(purpose, email) {
  const emailHash = crypto.createHash('sha256').update(email).digest('hex');
  return `${purpose}_${emailHash}`;
}

function hashCode(docId, code) {
  return crypto.createHash('sha256').update(`${docId}:${code}`).digest('hex');
}

function safeEqual(a, b) {
  const bufA = Buffer.from(a);
  const bufB = Buffer.from(b);
  return bufA.length === bufB.length && crypto.timingSafeEqual(bufA, bufB);
}

function generateCode() {
  return crypto.randomInt(0, 1000000).toString().padStart(6, '0');
}

function renderEmail(purpose, code) {
  const copy = PURPOSES[purpose];
  const text =
    `${copy.heading}\n\n${copy.intro}\n\n` +
    `Your code: ${code}\n\n` +
    `This code expires in ${OTP_TTL_MINUTES} minutes. ` +
    `If you did not request it, you can safely ignore this email.`;
  const html = `
  <div style="font-family:Arial,Helvetica,sans-serif;max-width:480px;margin:0 auto;padding:24px;color:#1f2937">
    <h2 style="margin:0 0 8px">${copy.heading}</h2>
    <p style="margin:0 0 20px;color:#4b5563">${copy.intro}</p>
    <div style="font-size:32px;font-weight:bold;letter-spacing:8px;text-align:center;
                padding:16px;border-radius:12px;background:#f3f4f6">${code}</div>
    <p style="margin:20px 0 0;font-size:13px;color:#6b7280">
      This code expires in ${OTP_TTL_MINUTES} minutes. If you did not request it, you can safely ignore this email.
    </p>
  </div>`;
  return { subject: copy.subject, text, html };
}

async function sendOtpEmail(to, purpose, code) {
  const port = Number(process.env.SMTP_PORT || SMTP_PORT.value());
  const user = process.env.SMTP_USER || SMTP_USER.value();
  const pass = process.env.SMTP_PASS || SMTP_PASS.value();
  const host = process.env.SMTP_HOST || SMTP_HOST.value();
  const from = process.env.MAIL_FROM || MAIL_FROM.value() || `BranchFlow <${user}>`;

  const transporter = nodemailer.createTransport({
    host,
    port,
    secure: port === 465,
    auth: { user, pass },
  });
  await transporter.sendMail({ from, to, ...renderEmail(purpose, code) });
}

/** Creates a fresh code for (purpose, email), stores its hash and emails it. */
async function issueOtp(purpose, email, uid) {
  const docId = otpDocId(purpose, email);
  const ref = db.collection('otp_codes').doc(docId);

  const existing = await ref.get();
  if (existing.exists) {
    const sentAt = existing.get('createdAt');
    const elapsed = sentAt ? (Date.now() - sentAt.toMillis()) / 1000 : Infinity;
    if (elapsed < RESEND_COOLDOWN_SECONDS) {
      const wait = Math.ceil(RESEND_COOLDOWN_SECONDS - elapsed);
      throw new HttpsError('resource-exhausted', `Please wait ${wait}s before requesting a new code.`);
    }
  }

  const code = generateCode();
  await ref.set({
    email,
    uid,
    purpose,
    codeHash: hashCode(docId, code),
    attempts: 0,
    createdAt: FieldValue.serverTimestamp(),
    expiresAt: Timestamp.fromMillis(Date.now() + OTP_TTL_MINUTES * 60 * 1000),
  });

  try {
    await sendOtpEmail(email, purpose, code);
  } catch (err) {
    logger.error('Failed to send OTP email', { purpose, error: err.message });
    await ref.delete();
    throw new HttpsError('internal', 'We could not send the email right now. Please try again shortly.');
  }
}

/** Checks a submitted code. Consumes it on success, counts attempts on failure. */
async function consumeOtp(purpose, email, rawCode) {
  const code = String(rawCode || '').trim();
  if (!/^\d{6}$/.test(code)) {
    throw new HttpsError('invalid-argument', 'Please enter the 6-digit code.');
  }

  const docId = otpDocId(purpose, email);
  const ref = db.collection('otp_codes').doc(docId);

  const outcome = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return { status: 'missing' };

    const data = snap.data();
    if (data.expiresAt.toMillis() < Date.now()) {
      tx.delete(ref);
      return { status: 'expired' };
    }
    if (data.attempts >= MAX_ATTEMPTS) {
      tx.delete(ref);
      return { status: 'locked' };
    }
    if (!safeEqual(data.codeHash, hashCode(docId, code))) {
      const attempts = data.attempts + 1;
      if (attempts >= MAX_ATTEMPTS) {
        tx.delete(ref);
        return { status: 'locked' };
      }
      tx.update(ref, { attempts });
      return { status: 'invalid', remaining: MAX_ATTEMPTS - attempts };
    }
    tx.delete(ref);
    return { status: 'ok', uid: data.uid };
  });

  switch (outcome.status) {
    case 'ok':
      return outcome;
    case 'invalid':
      throw new HttpsError(
        'permission-denied',
        `Invalid OTP code. ${outcome.remaining} attempt${outcome.remaining === 1 ? '' : 's'} remaining.`,
      );
    case 'expired':
      throw new HttpsError('deadline-exceeded', 'This code has expired. Please request a new one.');
    case 'locked':
      throw new HttpsError('permission-denied', 'Too many incorrect attempts. Please request a new code.');
    default:
      throw new HttpsError('not-found', 'No active code found. Please request a new one.');
  }
}

// -------------------------------------------------------------
// CALLABLE: requestOtp
// -------------------------------------------------------------
exports.requestOtp = onCall(callableOptions, async (request) => {
  const purpose = request.data?.purpose;
  if (!PURPOSES[purpose]) {
    throw new HttpsError('invalid-argument', 'Unknown OTP purpose.');
  }

  if (purpose === 'verify_email') {
    // Only the signed-in user may request a verification code for their own email.
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Please sign in to verify your email.');
    }
    const email = normalizeEmail(request.auth.token.email);
    const user = await getAuth().getUser(request.auth.uid);
    if (user.emailVerified) {
      return { sent: false, alreadyVerified: true };
    }
    await issueOtp(purpose, email, user.uid);
    return { sent: true };
  }

  // reset_password: respond the same way whether or not the account exists,
  // so the endpoint cannot be used to discover registered emails.
  const email = normalizeEmail(request.data?.email);
  let user;
  try {
    user = await getAuth().getUserByEmail(email);
  } catch (err) {
    if (err.code === 'auth/user-not-found') return { sent: true };
    throw err;
  }
  await issueOtp(purpose, email, user.uid);
  return { sent: true };
});

// -------------------------------------------------------------
// CALLABLE: verifyEmailOtp
// -------------------------------------------------------------
exports.verifyEmailOtp = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Please sign in to verify your email.');
  }
  const email = normalizeEmail(request.auth.token.email);
  const { uid } = await consumeOtp('verify_email', email, request.data?.otp);
  if (uid !== request.auth.uid) {
    throw new HttpsError('permission-denied', 'This code does not belong to your account.');
  }
  await getAuth().updateUser(uid, { emailVerified: true });
  return { verified: true };
});

// -------------------------------------------------------------
// CALLABLE: resetPasswordWithOtp
// -------------------------------------------------------------
exports.resetPasswordWithOtp = onCall(async (request) => {
  const email = normalizeEmail(request.data?.email);
  const newPassword = String(request.data?.newPassword || '');
  if (newPassword.length < 6) {
    throw new HttpsError('invalid-argument', 'New password must be at least 6 characters.');
  }

  const { uid } = await consumeOtp('reset_password', email, request.data?.otp);
  // Receiving the code proves ownership of the inbox, so the email is verified too.
  await getAuth().updateUser(uid, { password: newPassword, emailVerified: true });
  await getAuth().revokeRefreshTokens(uid);
  return { reset: true };
});
