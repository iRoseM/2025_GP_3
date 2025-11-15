/**
 * Firebase Functions (mixed 1st + 2nd gen)
 * - createUserDoc: 1st gen Auth trigger (auth.user().onCreate)
 * - reserveUsername, markVerified, generateShortTestVerification: 2nd gen HTTPS callable
 */

const functions = require("firebase-functions/v1"); // ✅ v1 (عشان auth.user().onCreate & region)
const { onCall, HttpsError } = require("firebase-functions/v2/https"); // ✅ v2 callable
const { setGlobalOptions } = require("firebase-functions/v2/options");
const admin = require("firebase-admin");

admin.initializeApp();

// ✅ إعداد الخيارات العامة للـ v2 functions
setGlobalOptions({
  region: "us-central1",
  maxInstances: 10,
});

/** Helper: normalize safely */
function toLowerSafe(s) {
  return (s || "").trim().toLowerCase();
}

/* ============================================================
 * createUserDoc → 1st gen Auth trigger (onCreate)
 * ============================================================ */
exports.createUserDoc = functions
  .region("us-central1")
  .auth.user()
  .onCreate(async (user) => {
    const db = admin.firestore();
    const uid = user.uid;

    const email = toLowerSafe(user.email || "");
    const emailVerified = !!user.emailVerified;

    let isAdmin = false;
    if (email) {
      const adminDoc = await db.collection("admin_emails").doc(email).get();
      isAdmin = adminDoc.exists === true;
    }

    const baseData = {
      email: email || null,
      username: email ? email.split("@")[0] : null,
      role: isAdmin ? "admin" : "regular",
      isVerified: emailVerified,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (!isAdmin) {
      baseData.wallet = 0;
      baseData.completedTask = 0;
      baseData.userLevelId = "beginner";
    }

    await db.collection("users").doc(uid).set(baseData, { merge: true });
    console.log(`✅ users/${uid} created (role=${baseData.role})`);
  });

/* ============================================================
 * reserveUsername (Callable) - v2
 * ============================================================ */
exports.reserveUsername = onCall(async (request) => {
  const auth = request.auth;
  if (!auth || !auth.uid) {
    throw new HttpsError("unauthenticated", "UNAUTHENTICATED");
  }

  const uid = auth.uid;
  const usernameRaw = (request.data?.username || "").trim();
  const username = toLowerSafe(usernameRaw);

  const re = /^[a-z0-9._-]{3,24}$/;
  if (!re.test(username)) {
    throw new HttpsError("invalid-argument", "INVALID_USERNAME");
  }

  const db = admin.firestore();
  const usernameRef = db.collection("usernames").doc(username);
  const userRef = db.collection("users").doc(uid);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(usernameRef);

    if (snap.exists) {
      const existing = snap.data();
      if (existing && existing.uid && existing.uid !== uid) {
        throw new HttpsError("failed-precondition", "USERNAME_TAKEN");
      }
    }

    tx.set(
      usernameRef,
      {
        uid,
        reservedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

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
 * markVerified (Callable) - v2
 * ============================================================ */
exports.markVerified = onCall(async (request) => {
  const auth = request.auth;
  if (!auth || !auth.uid) {
    throw new HttpsError("unauthenticated", "UNAUTHENTICATED");
  }
  const uid = auth.uid;

  const userRec = await admin.auth().getUser(uid);
  if (!userRec.emailVerified) {
    return { ok: false, reason: "NOT_VERIFIED" };
  }

  const db = admin.firestore();
  await db.collection("users").doc(uid).set(
    {
      isVerified: true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  return { ok: true };
});

/* ============================================================
 * generateShortTestVerification (Callable) - v2
 * توليد "تحقق عبر اختبار قصير" لمقال استدامة
 * ============================================================ */
exports.generateShortTestVerification = onCall(async (request) => {
  const auth = request.auth;
  if (!auth || !auth.uid) {
    throw new HttpsError("unauthenticated", "User not logged in");
  }

  const articleText = request.data?.articleText;
  const apiType = request.data?.apiType || "gemini";

  if (!articleText || articleText.length < 80) {
    throw new HttpsError("invalid-argument", "ARTICLE_TEXT_TOO_SHORT");
  }

  const prompt = `
اقرأ النص التالي وصِغ "تحققًا عبر اختبار قصير" مكونًا من سؤال واحد مع أربع اختيارات.
اجعل السؤال متعلقًا بمضمون النص فقط.
أرجع النتيجة بصيغة JSON واضحة كالتالي:
{
  "question": "...",
  "options": ["...", "...", "...", "..."],
  "answer": "..."
}
---
النص:
${articleText}
`;

  try {
    // ✅ نستخدم fetch المدمج في Node 20 (ما نحتاج node-fetch)
    let response;
    let jsonText;

    if (apiType === "gemini") {
      // ✅ Gemini API
      response = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent?key=${process.env.GEMINI_API_KEY}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            contents: [{ parts: [{ text: prompt }] }],
          }),
        }
      );

      const result = await response.json();
      jsonText =
        result?.candidates?.[0]?.content?.parts?.[0]?.text || "No response";
    } else {
      // ✅ OpenAI API
      response = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
        },
        body: JSON.stringify({
          model: "gpt-4o-mini",
          messages: [{ role: "user", content: prompt }],
        }),
      });

      const result = await response.json();
      jsonText = result?.choices?.[0]?.message?.content || "{}";
    }

    // نرجع النص كما هو (وتقدرين بالعميل تسوين JSON.parse إذا حابة)
    return jsonText;
  } catch (err) {
    console.error("❌ AI Function Error:", err);
    throw new HttpsError("internal", "AI_GENERATION_FAILED");
  }
});
