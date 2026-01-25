const functions = require("firebase-functions/v1"); // ✅ v1 (عشان auth.user().onCreate & region)
const { onCall, HttpsError } = require("firebase-functions/v2/https"); // ✅ v2 callable
const { setGlobalOptions } = require("firebase-functions/v2/options");
const admin = require("firebase-admin");
const { defineString } = require("firebase-functions/params"); // ✅ للـ params الجديدة

admin.initializeApp();

setGlobalOptions({
  region: "us-central1",
  maxInstances: 10,
});

// ✅ مفاتيح الـ params (من .env أو من إعدادات Firebase)
const GEMINI_API_KEY = defineString("GEMINI_API_KEY");
const MAPS_API_KEY = defineString("MAPS_API_KEY"); // ⬅️ أضفنا هذا

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
 * generateShortTestVerification → Gemini quiz generation
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
    // ✅ نقرأ المفتاح من Firebase params (GEMINI_API_KEY)
    const apiKey = GEMINI_API_KEY.value();

    // 🔎 لو مفقود نرمي خطأ واضح
    if (!apiKey) {
      console.error("❌ GEMINI_API_KEY is missing in params!");
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
        `GEMINI_API_ERROR: ${
          result.error.message || result.error.status || "UNKNOWN_ERROR"
        }`
      );
    }

    let text = result?.candidates?.[0]?.content?.parts?.[0]?.text || "";

    // 🧹 تنظيف Markdown
    text = text.replace(/```json/g, "").replace(/```/g, "").trim();

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

/* ============================================================
 * getMapsKey → ترجع Google Maps API key بشكل آمن
 * ============================================================ */
exports.getMapsKey = onCall((request) => {
  const auth = request.auth;
  if (!auth || !auth.uid) {
    throw new HttpsError("unauthenticated", "User not logged in");
  }

  const apiKey = MAPS_API_KEY.value();

  if (!apiKey) {
    console.error("❌ MAPS_API_KEY is missing in params!");
    throw new HttpsError("failed-precondition", "MAPS_API_KEY_MISSING");
  }

  // 🎯 نرجع الكي للعميل بدون ما يكون مكتوب في الكود
  return { apiKey };
});
/* ============================================================
 * 🔔 Reminder: باقي يوم على المهمة (userTasks.windowEnd)
 * ============================================================ */
exports.sendOneDayReminderForUserTasks = functions
  .region("us-central1")
  .pubsub.schedule("0 9 * * *") // 9:00 AM
  .timeZone("Asia/Riyadh")
  .onRun(async () => {
    const db = admin.firestore();

    const now = new Date();

    // بكرة من 00:00 إلى 23:59
    const startTomorrow = new Date(
      now.getFullYear(),
      now.getMonth(),
      now.getDate() + 1,
      0,
      0,
      0,
      0
    );
    const endTomorrow = new Date(
      now.getFullYear(),
      now.getMonth(),
      now.getDate() + 1,
      23,
      59,
      59,
      999
    );

    const startTs = admin.firestore.Timestamp.fromDate(startTomorrow);
    const endTs = admin.firestore.Timestamp.fromDate(endTomorrow);

    const snapshot = await db
      .collection("userTasks")
      .where("windowEnd", ">=", startTs)
      .where("windowEnd", "<=", endTs)
      .get();

    if (snapshot.empty) return null;

    const pad = (n) => String(n).padStart(2, "0");
    const ymd = `${startTomorrow.getFullYear()}${pad(
      startTomorrow.getMonth() + 1
    )}${pad(startTomorrow.getDate())}`;

    for (const doc of snapshot.docs) {
      const data = doc.data();
      const userId = data.userId;
      if (!userId) continue;

      // نتجاهل المكتملة
      if ((data.status || "").toLowerCase() === "completed") continue;

      const taskTitle = data.taskTitle || "مهمة";

      // DocId ثابت يمنع التكرار
      const notifId = `rem1d_${doc.id}_${ymd}`;
      const notifRef = db.collection("notifications").doc(notifId);

      const exists = await notifRef.get();
      if (exists.exists) continue;

      await notifRef.set({
        type: "user_task_one_day_reminder",
        userId: userId,
        userTaskDocId: doc.id,
        taskId: data.taskId || null,
        taskTitle: taskTitle,

    title: "تذكير ⏳",
    body: `لا تنسى مهمتك "${taskTitle}"، باقي يوم واحد عليها.`,


        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        seen: false,
      });
    }

    return null;
  });
