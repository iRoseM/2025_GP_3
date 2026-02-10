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
});const { DateTime } = require("luxon");

/* ============================================================
 * 🔔 Immediate Trigger: "بكره" reminder عند إنشاء/تحديث scheduledTasks
 * - Runs on create/update
 * - Checks if scheduledFor is TOMORROW in Asia/Riyadh AND status == scheduled
 * - Prevents duplicates via stable notifId
 * ============================================================ */
exports.sendImmediateTomorrowReminderOnScheduledTaskWrite = functions
  .region("us-central1")
  .firestore.document("scheduledTasks/{scheduledTaskId}")
  .onWrite(async (change, context) => {
    // deleted
    if (!change.after.exists) return null;

    const db = admin.firestore();
    const docId = context.params.scheduledTaskId;

    const afterData = change.after.data() || {};
    const beforeData = change.before.exists ? (change.before.data() || {}) : null;

    // ✅ لازم يكون فيها userId + scheduledFor
    const userId = afterData.userId;
    if (!userId) return null;

    const ts = afterData.scheduledFor;
    if (!ts || typeof ts.toDate !== "function") return null;

    // ✅ فقط scheduled
    if ((afterData.status || "").toLowerCase() !== "scheduled") return null;

    // ✅ لو ما تغير شيء مهم (status/scheduledFor) وما هي إنشاء جديد، تجاهل لتقليل التنفيذ
    const isCreate = !change.before.exists;
    const scheduledForChanged =
      !beforeData || !beforeData.scheduledFor || beforeData.scheduledFor.toMillis?.() !== ts.toMillis?.();
    const statusChanged =
      !beforeData || (beforeData.status || "").toLowerCase() !== (afterData.status || "").toLowerCase();

    if (!isCreate && !scheduledForChanged && !statusChanged) return null;

    // ===== حساب "بكره" بتوقيت الرياض =====
    const nowRiyadh = DateTime.now().setZone("Asia/Riyadh");
    const startTomorrow = nowRiyadh.plus({ days: 1 }).startOf("day");
    const endTomorrow = nowRiyadh.plus({ days: 1 }).endOf("day");

    // موعد المهمة بتوقيت الرياض
    const scheduledForRiyadh = DateTime.fromJSDate(ts.toDate()).setZone("Asia/Riyadh");

    // ✅ لازم تكون المهمة داخل يوم "بكره" (كتاريخ)
    const isTomorrow =
      scheduledForRiyadh >= startTomorrow && scheduledForRiyadh <= endTomorrow;

    if (!isTomorrow) return null;

    // ✅ ymd ثابت لليوم (بكره) لمنع التكرار
    const ymd = startTomorrow.toFormat("yyyyLLdd");

    const taskTitle = afterData.taskTitle || "مهمة";

    const notifId = `rem1d_sched_${docId}_${ymd}`;
    const notifRef = db.collection("notifications").doc(notifId);

    const exists = await notifRef.get();
    if (exists.exists) return null;

    await notifRef.set({
      type: "scheduled_task_one_day_reminder",
      userId,
      scheduledTaskId: docId,
      taskId: afterData.taskId || null,
      taskTitle,

      title: "تذكير ⏳",
      body: `لا تنسى مهمتك "${taskTitle}"، بكره موعدها 🌿`,

      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      seen: false,
    });

    return null;
  });
