/**
 * Firebase Functions v2 (Node 18)
 * - createUserDoc (onUserCreated): ينشئ users/{uid} ويضبط الدور
 * - reserveUsername (onCall): يحجز username فريد (usernames/{username} => { uid })
 * - markVerified (onCall): يحدّث isVerified=true بعد التأكد من التحقق عبر Admin SDK
 */

const { setGlobalOptions } = require('firebase-functions/v2/options');
const { onUserCreated } = require('firebase-functions/v2/identity');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

admin.initializeApp();

setGlobalOptions({
  region: 'us-central1',
  maxInstances: 10,
  // memory: '256MiB',
  // timeoutSeconds: 60,
});

/** Helper: normalize safely */
function toLowerSafe(s) {
  return (s || '').trim().toLowerCase();
}

/* ============================================================
 * onUserCreated → createUserDoc
 * - ينشئ users/{uid} عند إنشاء المستخدم
 * - يضبط role=admin إذا كان بريده موجودًا في admin_emails/{email}
 * - يملأ حقولًا افتراضية للمستخدم العادي
 * ============================================================ */
exports.createUserDoc = onUserCreated(async (event) => {
  const db = admin.firestore();

  const uid = event?.data?.uid;
  if (!uid) return; // احتياط

  const email = toLowerSafe(event?.data?.email || '');
  const emailVerified = !!event?.data?.emailVerified;

  // هل هو أدمن؟ عبر كولكشن admin_emails/{email}
  let isAdmin = false;
  if (email) {
    const adminDoc = await db.collection('admin_emails').doc(email).get();
    isAdmin = adminDoc.exists === true;
  }

  // بيانات أساسية
  const baseData = {
    email: email || null,
    username: email ? email.split('@')[0] : null, // اسم افتراضي
    role: isAdmin ? 'admin' : 'regular',
    isVerified: emailVerified,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  // قيم إضافية للمستخدم العادي فقط
  if (!isAdmin) {
    baseData.wallet = 0;
    baseData.completedTask = 0;
    baseData.userLevelId = 'beginner';
  }

  try {
    await db.collection('users').doc(uid).set(baseData, { merge: true });
    console.log(
      `✅ users/${uid} created (role=${baseData.role}, email=${email || 'N/A'})`
    );
  } catch (err) {
    console.error(`❌ Failed to write users/${uid}:`, err);
    throw err;
  }
});

/* ============================================================
 * reserveUsername (Callable)
 * - يتحقق من شكل الاسم [a-z0-9._-]{3,24}
 * - يتأكد أنه غير محجوز في usernames/{usernameLower}
 * - يحجزه (usernameLower → uid)
 * - يحدّث users/{uid}.username أيضًا
 * ============================================================ */
exports.reserveUsername = onCall(async (request) => {
  const auth = request.auth;
  if (!auth || !auth.uid) {
    throw new HttpsError('unauthenticated', 'UNAUTHENTICATED');
  }

  const uid = auth.uid;
  const usernameRaw = (request.data?.username || '').trim();
  const username = toLowerSafe(usernameRaw);

  // تحقق فورمات
  const re = /^[a-z0-9._-]{3,24}$/;
  if (!re.test(username)) {
    throw new HttpsError('invalid-argument', 'INVALID_USERNAME');
  }

  const db = admin.firestore();
  const usernameRef = db.collection('usernames').doc(username);
  const userRef = db.collection('users').doc(uid);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(usernameRef);

    if (snap.exists) {
      // الاسم محجوز
      const existing = snap.data();
      if (existing && existing.uid && existing.uid !== uid) {
        // محجوز لمستخدم آخر
        throw new HttpsError('failed-precondition', 'USERNAME_TAKEN');
      }
      // لو كان محجوز لنفس المستخدم، نعدّله ونكمّل (Idempotent)
    }

    // احجز/حدّث المابنج
    tx.set(
      usernameRef,
      {
        uid,
        reservedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    // حدّث users/{uid}.username
    tx.set(
      userRef,
      {
        username: username,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  });

  return { ok: true, username };
});

/* ============================================================
 * markVerified (Callable)
 * - يقرأ حالة المستخدم من Admin SDK (مصدر الحقيقة)
 * - إذا verified → يحدّث users/{uid}.isVerified = true
 * ============================================================ */
exports.markVerified = onCall(async (request) => {
  const auth = request.auth;
  if (!auth || !auth.uid) {
    throw new HttpsError('unauthenticated', 'UNAUTHENTICATED');
  }
  const uid = auth.uid;

  // حالة التحقق من Admin SDK
  const userRec = await admin.auth().getUser(uid);
  if (!userRec.emailVerified) {
    // لسه مو متحقق
    return { ok: false, reason: 'NOT_VERIFIED' };
    // أو: throw new HttpsError('failed-precondition', 'NOT_VERIFIED');
  }

  const db = admin.firestore();
  await db
    .collection('users')
    .doc(uid)
    .set(
      {
        isVerified: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

  return { ok: true };
});
