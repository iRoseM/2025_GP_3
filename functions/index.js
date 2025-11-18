// ================== تحميل المتغيرات من ملف .env ==================
require("dotenv").config();

// ================== إعداد Firebase Functions & Admin ==================
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
      // username: email ? email.split("@")[0] : null,
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
// exports.reserveUsername = onCall(async (request) => {
//   const auth = request.auth;
//   if (!auth || !auth.uid) {
//     throw new HttpsError("unauthenticated", "UNAUTHENTICATED");
//   }

//   const uid = auth.uid;
//   const usernameRaw = (request.data?.username || "").trim();
//   const username = toLowerSafe(usernameRaw);

//   const re = /^[a-z0-9._-]{3,24}$/;
//   if (!re.test(username)) {
//     throw new HttpsError("invalid-argument", "INVALID_USERNAME");
//   }

//   const db = admin.firestore();
//   const usernameRef = db.collection("usernames").doc(username);
//   const userRef = db.collection("users").doc(uid);

//   await db.runTransaction(async (tx) => {
//     const snap = await tx.get(usernameRef);

//     if (snap.exists) {
//       const existing = snap.data();
//       if (existing && existing.uid && existing.uid !== uid) {
//         throw new HttpsError("failed-precondition", "USERNAME_TAKEN");
//       }
//     }

//     tx.set(
//       usernameRef,
//       {
//         uid,
//         reservedAt: admin.firestore.FieldValue.serverTimestamp(),
//       },
//       { merge: true }
//     );

//     tx.set(
//       userRef,
//       {
//         username: username,
//         updatedAt: admin.firestore.FieldValue.serverTimestamp(),
//       },
//       { merge: true }
//     );
//   });

//   return { ok: true, username };
// });

/* ============================================================
 * markVerified (Callable) - v2
 * ============================================================ */
// exports.markVerified = onCall(async (request) => {
//   const auth = request.auth;
//   if (!auth || !auth.uid) {
//     throw new HttpsError("unauthenticated", "UNAUTHENTICATED");
//   }
//   const uid = auth.uid;

//   const userRec = await admin.auth().getUser(uid);
//   if (!userRec.emailVerified) {
//     return { ok: false, reason: "NOT_VERIFIED" };
//   }

//   const db = admin.firestore();
//   await db.collection("users").doc(uid).set(
//     {
//       isVerified: true,
//       updatedAt: admin.firestore.FieldValue.serverTimestamp(),
//     },
//     { merge: true }
//   );

//   return { ok: true };
// });

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

  if (!articleText || articleText.length < 80) {
    throw new HttpsError("invalid-argument", "ARTICLE_TEXT_TOO_SHORT");
  }

  const prompt = `
اقرأ النص التالي وصِغ سؤال تحقق واحد فقط مع أربع خيارات.
أرجع الإجابة بصيغة JSON فقط بدون أي نص إضافي:
{
  "question": "...",
  "options": ["...", "...", "...", "..."],
  "answer": "...",
  "explanation": "..."
}

النص:
${articleText}
`;

  try {
    const apiKey = process.env.GEMINI_API_KEY;

    // 🔎 لو وده ناقص نرمي خطأ واضح
    if (!apiKey) {
      console.error("❌ GEMINI_API_KEY is missing in env!");
      throw new HttpsError("failed-precondition", "GEMINI_API_KEY_MISSING");
    }

    const url = `https://generativelanguage.googleapis.com/v1/models/gemini-2.5-pro:generateContent?key=${apiKey}`;

    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
      }),
    });

    const result = await response.json();
    // ✅ لو الـ API رجع error واضح من Google
    if (result.error) {
      console.error("❌ Gemini API error:", result.error);
      throw new HttpsError(
        "internal",
        `GEMINI_API_ERROR: ${result.error.message || result.error.status || "UNKNOWN_ERROR"}`
      );
    }

    let text = result?.candidates?.[0]?.content?.parts?.[0]?.text || "";

    // 🧹 تنظيف Markdown
    text = text.replace(/```json/g, "")
               .replace(/```/g, "")
               .trim();

    // 🧹 استخراج JSON فقط
    const first = text.indexOf("{");
    const last = text.lastIndexOf("}");
    if (first === -1 || last === -1 || last <= first) {
      console.error("❌ No valid JSON in Gemini response text:", text);
      throw new HttpsError("internal", "NO_VALID_JSON_RETURNED");
    }

    const jsonBlock = text.substring(first, last + 1).trim();

    // 🧪 تأكيد أن JSON صالح
    let parsed;
    try {
      parsed = JSON.parse(jsonBlock);
    } catch (e) {
      console.error("❌ Failed to parse JSON from Gemini:", jsonBlock, e);
      throw new HttpsError("internal", "INVALID_JSON_FROM_AI");
    }

    // تأكد من وجود الحقول الأساسية
    if (
      !parsed.question ||
      !Array.isArray(parsed.options) ||
      parsed.options.length < 2 ||
      !parsed.answer
    ) {
      console.error("❌ Parsed JSON missing required fields:", parsed);
      throw new HttpsError("internal", "MALFORMED_AI_RESPONSE");
    }

    // 🎯 نرجع JSON نظيف للكلينت
    return parsed;

  } catch (err) {
    console.error("❌ Gemini Error (outer catch):", err);

    if (err instanceof HttpsError) {
      throw err;
    }

    throw new HttpsError(
      "internal",
      `AI_GENERATION_FAILED: ${err.message || err.toString()}`
    );
  }
});
