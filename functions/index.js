const functions = require("firebase-functions/v1");
const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2/options");
const admin = require("firebase-admin");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { defineString } = require("firebase-functions/params");
const { DateTime } = require("luxon");

admin.initializeApp();
const db = admin.firestore();

const { FieldValue } = require("firebase-admin/firestore");

setGlobalOptions({
  region: "us-central1",
  maxInstances: 10,
});

// ✅ مفاتيح الـ params
const GEMINI_API_KEY = defineString("GEMINI_API_KEY");
const GEMINI_PRODUCT_API_KEY = defineString("GEMINI_PRODUCT_API_KEY");
const MAPS_API_KEY = defineString("MAPS_API_KEY");

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
   const apiKey = GEMINI_API_KEY.value();

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

    text = text.replace(/```json/g, "").replace(/```/g, "").trim();

    const first = text.indexOf("{");
    const last = text.lastIndexOf("}");
    if (first === -1 || last === -1 || last <= first) {
      console.error("❌ No valid JSON in Gemini response text:", text);
      throw new HttpsError("internal", "NO_VALID_JSON_RETURNED");
    }

    const jsonBlock = text.substring(first, last + 1).trim();

    let parsed;
    try {
      parsed = JSON.parse(jsonBlock);
    } catch (e) {
      console.error("❌ Failed to parse JSON from Gemini:", jsonBlock, e);
      throw new HttpsError("internal", "INVALID_JSON_FROM_AI");
    }

    if (
      !parsed.question ||
      !Array.isArray(parsed.options) ||
      parsed.options.length < 2 ||
      !parsed.answer
    ) {
      console.error("❌ Parsed JSON missing required fields:", parsed);
      throw new HttpsError("internal", "MALFORMED_AI_RESPONSE");
    }

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
 * resolveProductName → Gemini product name resolver
 * ============================================================ */
exports.resolveProductName = onRequest(
  {
    region: "us-central1",
    cors: true,
  },
  async (req, res) => {
    try {
      if (req.method !== "POST") {
        return res.status(405).json({ error: "Method not allowed" });
      }

      const { productName, productType } = req.body || {};

      if (!productName || productName.toString().trim().length === 0) {
        return res.status(400).json({ error: "productName is required" });
      }

      const apiKey = GEMINI_PRODUCT_API_KEY.value();

      if (!apiKey) {
        console.error("❌ GEMINI_PRODUCT_API_KEY is missing in params!");
        return res.status(500).json({
          error: "GEMINI_PRODUCT_API_KEY_MISSING",
        });
      }

      const prompt = `
You are helping normalize a product name and estimate density for carbon calculation.

User product name: "${productName}"
Product type: "${productType || ""}"

Return JSON only in this exact schema:
{
  "canonical_query": "short english product phrase",
  "alternatives": ["alt 1", "alt 2"],
  "category": "short category",
  "density_kg_per_liter": 0.0,
  "source": "short trusted source note",
  "confidence": 0.0,
  "trusted": true
}

Rules:
- Translate Arabic to English when needed.
- Infer the most likely common product/category.
- If productType is liquid, return density in kg/L.
- If productType is solid, density_kg_per_liter may be null.
- Prefer a reasonable trusted estimate.
- Output valid JSON only.
- No markdown.
`;

      const url =
        `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}`;

      const geminiRes = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          contents: [
            {
              parts: [{ text: prompt }],
            },
          ],
          generationConfig: {
            temperature: 0.2,
            responseMimeType: "application/json",
          },
        }),
      });

      const geminiData = await geminiRes.json();

      if (!geminiRes.ok) {
        console.error("❌ Gemini resolver API error:", geminiData);
        return res.status(geminiRes.status).json(geminiData);
      }

      const text = geminiData?.candidates?.[0]?.content?.parts?.[0]?.text;

      if (!text) {
        return res.status(500).json({ error: "Empty Gemini response" });
      }

      const cleanText = text
        .replace(/```json/g, "")
        .replace(/```/g, "")
        .trim();

      const parsed = JSON.parse(cleanText);

      return res.status(200).json(parsed);
    } catch (e) {
      console.error("❌ resolveProductName error:", e);
      return res.status(500).json({ error: e.message });
    }
  }
);

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

  return { apiKey };
});

/* ============================================================
 *  suggestBonusTask → Callable Function
 * ============================================================ */

exports.suggestBonusTask = onCall(async (request) => {
  const auth = request.auth;
  if (!auth || !auth.uid) {
    throw new HttpsError("unauthenticated", "User not logged in");
  }

  const userId        = auth.uid;
  const pressedAt     = request.data?.pressedAt     || new Date().toISOString();
  const userLocation  = request.data?.userLocation  || null;
  const excludeTaskId = request.data?.excludeTaskId || null;

  // جلب مهمة اليوم (لاستبعادها)
  const today       = DateTime.now().setZone("Asia/Riyadh").toFormat("yyyyLLdd");
  const todayDocId  = `${userId}_${today}`;
  let todayTaskId   = null;

  try {
    const todaySnap = await db.collection("userTasks").doc(todayDocId).get();
    todayTaskId     = todaySnap.data()?.taskId || null;
  } catch (e) {
    console.log("⚠️ Could not fetch today's task:", e.message);
  }

  // استدعاء Python Agent
  try {
    // URL الـ Python function — عدّل المنطقة واسم المشروع
    const AGENT_URL = process.env.PYTHON_AGENT_URL ||
  "https://us-central1-nameer-f3b95.cloudfunctions.net/suggest_task_agent";

    const response = await fetch(AGENT_URL, {
      method:  "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        userId:        userId,
        pressedAt:     pressedAt,
        userLocation:  userLocation,
        excludeTaskId: excludeTaskId,
        todayTaskId:   todayTaskId,
      }),
    });

    if (!response.ok) {
      const errText = await response.text();
      console.error("❌ Python agent error:", errText);
      throw new HttpsError("internal", "AGENT_CALL_FAILED");
    }

    const result = await response.json();

    if (result.error) {
      throw new HttpsError("not-found", result.error);
    }

    console.log(`✅ Agent selected: ${result.title} | reasoning: ${result.agentReasoning}`);
    return result;

  } catch (err) {
    if (err instanceof HttpsError) throw err;
    console.error("❌ suggestBonusTask error:", err);
    throw new HttpsError("internal", `AGENT_ERROR: ${err.message}`);
  }
});
/* ============================================================
 *  updateUserPreferences
 * ============================================================ */
// ── Wilson Score ──────────────────────────────
function wilsonScore(completed, ignored) {
  const n = completed + ignored;

  // If no interaction → neutral score (1.0 × 10 = 10... return 5 as middle value)
  if (n === 0) return 5.0;

  const z = 1.96;     
  const p = completed / n; // Observed completion rate

  // Wilson score formula — lower bound of the confidence interval
  // This balances the observed completion rate against the uncertainty of small sample sizes
  const score = (
    (p + z*z/(2*n) - z * Math.sqrt((p*(1-p) + z*z/(4*n))/n)) /
    (1 + z*z/n)
  ) * 10; // Scale from [0,1] range to [0,10] for easier interpretation

  return Math.max(0.1, score); // Minimum 0.1 to avoid zero
}

exports.updateUserPreferences = onSchedule(
  { schedule: "0 22 * * *", timeZone: "Asia/Riyadh" },
  async () => {
    console.log("⏰ Updating user preferences...");
    const users = await db.collection("users").get();
    let updatedCount = 0;

    for (const userDoc of users.docs) {
      const userId = userDoc.id;
      if (userDoc.data()?.role === "admin") continue;

      try {
        // ── جلب المهام المكتملة من المصدر الأصلي ──────────
        const completedSnap = await db.collection("userTasks")
          .where("userId", "==", userId)
          .where("status", "==", "completed")
          .get();

        // ── جلب المهام المتجاهلة من المصدر الأصلي ─────────
        const ignoredSnap = await db.collection("userTasks")
          .where("userId", "==", userId)
          .where("ignored", "==", true)
          .get();

        // ── حساب العدد لكل مهمة ────────────────────────────
        const completedCount = {}; // taskId → عدد الإنجازات
        const ignoredCount   = {}; // taskId → عدد التجاهلات
        const taskMeta       = {}; // taskId → { title, category }

        completedSnap.forEach(doc => {
          const { taskId, taskTitle, category } = doc.data();
          if (!taskId) return;
          completedCount[taskId] = (completedCount[taskId] || 0) + 1;
          if (!taskMeta[taskId]) {
            taskMeta[taskId] = { title: taskTitle || "", category: category || "" };
          }
        });

        ignoredSnap.forEach(doc => {
          const { taskId } = doc.data();
          if (!taskId) return;
          ignoredCount[taskId] = (ignoredCount[taskId] || 0) + 1;
        });

        // ── جلب viewCount الحالي من الأيجنت ────────────────
        // (لا نعيد حسابه — الأيجنت هو من يحدثه عند عرض المهمة)
        const prefsDoc = await db.collection("userTaskPreferences").doc(userId).get();
        const existingPrefs = prefsDoc.exists
          ? (prefsDoc.data()?.taskPreferences || {})
          : {};

        // ── جمع كل معرفات المهام ────────────────────────────
        const allTaskIds = new Set([
          ...Object.keys(completedCount),
          ...Object.keys(ignoredCount),
        ]);

        const taskPreferences = {};

        for (const taskId of allTaskIds) {
          const completed = completedCount[taskId] || 0;
          const ignored   = ignoredCount[taskId]   || 0;

          // viewCount و lastViewedAt يأتيان من الأيجنت — نحافظ عليهما
          const viewCount    = existingPrefs[taskId]?.viewCount    || 0;
          const lastViewedAt = existingPrefs[taskId]?.lastViewedAt || null;

          // ── Wilson Score ────────────────────────────────────
          let score = wilsonScore(completed, ignored);

          // ── تعديل إضافي: عقوبة المهام المعروضة كثيراً بدون إنجاز ──
          // منطق: لو عُرضت +3 مرات ولم تُكتمل → المستخدم لا يريدها
          if (completed === 0 && viewCount > 3) {
            score = Math.max(0.1, score - viewCount * 0.5);
          }

          // ── نخزن النتيجة فقط — لا نكرر completed و ignored ──
          // البيانات الأصلية موجودة في userTasks (المصدر الحقيقي)
          taskPreferences[taskId] = {
            score,                                               // Wilson Score [0.1 - 10]
            viewCount,                                           // من الأيجنت
            lastViewedAt,                                        // من الأيجنت
            title:    taskMeta[taskId]?.title    || existingPrefs[taskId]?.title    || "",
            category: taskMeta[taskId]?.category || existingPrefs[taskId]?.category || "",
          };
        }

        // ── أعلى 5 مهام بالـ Wilson Score ──────────────────
        const topTasks = Object.entries(taskPreferences)
          .sort((a, b) => b[1].score - a[1].score)
          .slice(0, 5)
          .map(([id]) => id);

        await db.collection("userTaskPreferences").doc(userId).set({
          taskPreferences,
          topTasks,
          topTaskTitle: taskPreferences[topTasks[0]]?.title || "",
          // lastUpdated:  FieldValue.serverTimestamp(),
          // scoringMethod: "wilson_score_miller_2009", // توثيق المنهج المستخدم
        });

        updatedCount++;
        console.log(
          `✅ ${userId}: ${allTaskIds.size} tasks | ` +
          `top: ${taskPreferences[topTasks[0]]?.title} ` +
          `(score: ${taskPreferences[topTasks[0]]?.score?.toFixed(2)})`
        );

      } catch (e) {
        console.error(`❌ Failed for ${userId}:`, e.message);
      }
    }

    console.log(`🎉 Done: updated ${updatedCount}/${users.size} users`);
  }
);

/* ============================================================
 * 🔔 Immediate Trigger: "بكره" reminder
 * ============================================================ */
exports.generateDailyTasks = onSchedule(
  {
    schedule: "0 11 * * *",
    timeZone: "Asia/Riyadh",
  },
  async () => {
    console.log("⏰ Triggering Python daily task agent...");
    
    try {
      const AGENT_URL =
        process.env.DAILY_TASK_AGENT_URL ||
        "https://us-central1-nameer-f3b95.cloudfunctions.net/generate_daily_tasks_agent";

      // ✅ إضافة adminId للـ Python agent
      const response = await fetch(AGENT_URL, {
        method:  "POST",
        headers: { "Content-Type": "application/json" },
        body:    JSON.stringify({ 
          adminId: "SYSTEM_AUTO",  // ✅ مهم جداً
          source: "scheduled_job" 
        }),
      });

      const result = await response.json();
      
      if (result.error) {
        console.error(`❌ Agent error: ${result.error}`);
      } else {
        console.log(`✅ Created: ${result.created}/${result.total_users} for ${result.date}`);
      }
    } catch (err) {
      console.error("❌ Error:", err.message);
    }
  }
);


exports.sendImmediateTomorrowReminderOnScheduledTaskWrite = functions
  .region("us-central1")
  .firestore.document("scheduledTasks/{scheduledTaskId}")
  .onWrite(async (change, context) => {
    if (!change.after.exists) return null;

    const docId = context.params.scheduledTaskId;
    const afterData = change.after.data() || {};
    const beforeData = change.before.exists ? (change.before.data() || {}) : null;

    const userId = afterData.userId;
    if (!userId) return null;

    const ts = afterData.scheduledFor;
    if (!ts || typeof ts.toDate !== "function") return null;

    if ((afterData.status || "").toLowerCase() !== "scheduled") return null;

    const isCreate = !change.before.exists;
    const scheduledForChanged =
      !beforeData || !beforeData.scheduledFor || beforeData.scheduledFor.toMillis?.() !== ts.toMillis?.();
    const statusChanged =
      !beforeData || (beforeData.status || "").toLowerCase() !== (afterData.status || "").toLowerCase();

    if (!isCreate && !scheduledForChanged && !statusChanged) return null;

    const nowRiyadh = DateTime.now().setZone("Asia/Riyadh");
    const startTomorrow = nowRiyadh.plus({ days: 1 }).startOf("day");
    const endTomorrow = nowRiyadh.plus({ days: 1 }).endOf("day");

    const scheduledForRiyadh = DateTime.fromJSDate(ts.toDate()).setZone("Asia/Riyadh");

    const isTomorrow =
      scheduledForRiyadh >= startTomorrow && scheduledForRiyadh <= endTomorrow;

    if (!isTomorrow) return null;

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

/* ============================================================
 * ⏰ Scheduled Function: كل يوم 5:33 صباحاً
 * ============================================================ */
exports.scheduledGetAdminRecommendations = onSchedule({
  schedule: "0 11 1 * *",  // أول يوم من كل شهر فقط
  timeZone: "Asia/Riyadh",
},
async () => {
  console.log("⏰ Triggering Python admin recommendations agent...");
  try {
    const admins = await db
      .collection("users")
      .where("role", "==", "admin")
      .get();

    const adminId = admins.empty ? "SYSTEM_AUTO" : admins.docs[0].id;
    console.log(`👤 Using adminId: ${adminId}`);

    const AGENT_URL =
      process.env.ADMIN_AGENT_URL ||
      "https://us-central1-nameer-f3b95.cloudfunctions.net/admin_recommendations_agent";

    const response = await fetch(AGENT_URL, {
      method:  "POST",
      headers: { "Content-Type": "application/json" },
      body:    JSON.stringify({ adminId }),
    });

    const result = await response.json();
    console.log(`✅ Admin recommendations: ${result.recommendations?.length || 0} recs for ${result.month}`);

  } catch (err) {
    console.error("❌ scheduledGetAdminRecommendations error:", err.message);
  }
});
 
/* ============================================================
 * 📊 getAdminRecommendations → Callable (للفلاتر يستدعيها)
 * ============================================================ */
exports.getAdminRecommendations = onCall(async (request) => {
  const auth = request.auth;
  if (!auth || !auth.uid) {
    throw new HttpsError("unauthenticated", "User not logged in");
  }

  const userDoc = await db.collection("users").doc(auth.uid).get();
  if (userDoc.data()?.role !== "admin") {
    throw new HttpsError("permission-denied", "Admin access required");
  }

  const currentMonth = new Date().toISOString().slice(0, 7);
  const cached = await db.collection("adminRecommendations").doc(currentMonth).get();
  
  if (cached.exists) return cached.data();
  
  return { recommendations: [], month: currentMonth };
});
 
/* ============================================================
 * 🔔 sendMaintenanceNotification → تراقب config/maintenance
 * لما isActive يصير true ترسل إشعار لكل المستخدمين
 * ============================================================ */
exports.onMaintenanceActivated = functions
  .region("us-central1")
  .firestore.document("config/maintenance")
  .onWrite(async (change, context) => {
    const before = change.before.data() || {};
    const after = change.after.data() || {};

    // فقط لما isActive يتغير من false لـ true
    if (before.isActive === after.isActive) return null;
    if (!after.isActive) return null;

    const message = after.message || 'التطبيق تحت الصيانة حالياً';
    const expectedEnd = after.expectedEnd || '';

    const fullMessage = `${message}${expectedEnd ? ` — الوقت المتوقع للعودة: ${expectedEnd}` : ''}`;

    try {
      // جلب كل المستخدمين العاديين
      const usersSnap = await db
        .collection('users')
        .where('role', '==', 'regular')
        .get();

      if (usersSnap.empty) {
        console.log('⚠️ No users found');
        return null;
      }

      // إرسال إشعار لكل مستخدم
      const batch = db.batch();

      usersSnap.docs.forEach((userDoc) => {
        const notifRef = db.collection('notifications').doc();
        batch.set(notifRef, {
          userId: userDoc.id,
          type: 'maintenance',
          title: '🔧 التطبيق تحت الصيانة',
          body: fullMessage,
          message: fullMessage,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          seen: false,
        });
      });

      await batch.commit();
      console.log(`✅ Maintenance notifications sent to ${usersSnap.docs.length} users`);

    } catch (err) {
      console.error('❌ onMaintenanceActivated error:', err);
    }

    return null;
  });