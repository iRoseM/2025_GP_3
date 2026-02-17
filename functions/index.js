const functions = require("firebase-functions/v1"); // ✅ v1 (عشان auth.user().onCreate & region)
const { onCall, HttpsError } = require("firebase-functions/v2/https"); // ✅ v2 callable
const { setGlobalOptions } = require("firebase-functions/v2/options");
const admin = require("firebase-admin");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { defineString } = require("firebase-functions/params"); // ✅ للـ params الجديدة

admin.initializeApp();
const db = admin.firestore();

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
// ============================================================
// ✅ 1. دالة توليد المهام اليومية [v2] - مع تحسين الـ logs
// ============================================================
exports.generateDailyTasks = onSchedule(
  {
    schedule: "59 23 * * *", // 11:59 pm كل يوم
    timeZone: "Asia/Riyadh",
  },
  async () => {
    console.log("⏰ Generating AI daily tasks...");

    const apiKey = GEMINI_API_KEY.value();

    if (!apiKey) {
      console.error("❌ GEMINI_API_KEY missing");
      return;
    }

    const usersSnapshot = await db.collection("users").get();
    console.log(`👥 Total users: ${usersSnapshot.size}`);
    
    const { DateTime } = require("luxon");

const today = DateTime.now()
  .setZone("Asia/Riyadh")
  .toFormat("yyyy-LL-dd");
    console.log(`📅 Today: ${today}`);
    
    // ====================================================
    // 📦 نجيب كل المهام الفعالة
    // ====================================================
    const currentMonth = new Date().toISOString().slice(0, 7);
    console.log(`📦 Current month: ${currentMonth}`);

    // مصفوفة احتياطية للمهام (إذا فشل الجلب)
    const fallbackTasks = [
      { title: "وفر الطاقة", description: "افصل الأجهزة الكهربائية غير المستخدمة", category: "الكهرباء" },
      { title: "دور المخلفات", description: "افصل البلاستيك عن الورق", category: "التدوير" },
      { title: "امشي للجامعة", description: "امشي إذا كانت المسافة قريبة", category: "النقل" },
      { title: "وفر الماء", description: "أغلق الصنبور أثناء تنظيف الأسنان", category: "الماء" }
    ];

    let availableTasks = [];
    
    try {
      // نجيب كل المهام الفعالة
      const activeTasksSnapshot = await db
        .collection("tasks")
        .where("status", "==", "active")
        .get();

      console.log(`📦 Found ${activeTasksSnapshot.size} active tasks`);

      if (activeTasksSnapshot.size > 0) {
        activeTasksSnapshot.forEach((doc) => {
          const task = doc.data();
          
          // نفحص visible_from (إذا موجود)
          const visibleFrom = task.visible_from;
          if (visibleFrom && visibleFrom > currentMonth) {
            console.log(`   ⏰ Task "${task.title}" not visible yet (${visibleFrom} > ${currentMonth})`);
            return;
          }
          
          // نفحص expiry_month (إذا موجود)
          const expiry = task.expiry_month;
          if (expiry && expiry < currentMonth) {
            console.log(`   ⏰ Task "${task.title}" expired (${expiry} < ${currentMonth})`);
            return;
          }
          
          // المهمة صالحة ✅
          console.log(`   ✅ Task available: ${task.title} (${task.category})`);
       availableTasks.push({
  id: doc.id,
  ...task // 👈 هذا أهم شيء
});
        });
      }
      
      // إذا مافيه مهام، نستخدم الاحتياطية
      if (availableTasks.length === 0) {
        console.log("⚠️ No tasks found, using fallback tasks");
        availableTasks = fallbackTasks;
      }

      console.log(`📦 Available tasks: ${availableTasks.length}`);
      console.log(`📋 Tasks list:`, availableTasks.map(t => t.title).join(", "));
      
    } catch (e) {
      console.error(`❌ Error fetching tasks:`, e.message);
      console.log("⚠️ Using fallback tasks due to error");
      availableTasks = fallbackTasks;
    }

    // ====================================================
    // 👥 نبدأ مع المستخدمين
    // ====================================================
    let tasksCreated = 0;
    
for (const doc of usersSnapshot.docs) {
  const userId = doc.id;
const user = doc.data();
 let personalizedDescription = null;
  let userPrefs = null;
  let preferredCategory = null;
  let preferencesData = null;
  let availableCategories = [];
  
// ====================================================
// 📊 نجيب تفضيلات المهام المحفوظة
// ====================================================
let userTaskPrefs = null;
let topTaskIds = [];
let taskPreferencesData = null;

try {
  const prefsDoc = await db.collection("userTaskPreferences").doc(userId).get();
  if (prefsDoc.exists) {
    userTaskPrefs = prefsDoc.data(); // ✅ الآن userTaskPrefs له قيمة
    topTaskIds = userTaskPrefs.topTasks || [];
    taskPreferencesData = userTaskPrefs.taskPreferences;
    
    console.log(`   📊 User task preferences loaded...`);
  }
} catch (e) {
  console.log(`   ⚠️ Could not load preferences:`, e.message);
}

// ✅ الآن نستخدم userTaskPrefs بعد ما تأكدنا إنه موجود
const userProfile = {
  level: user.userLevelId || "beginner",
  points: user.points || 0,
  topTaskId: userTaskPrefs?.topTaskId || null, // <-- هنا تمام ✅
};
  // ====================================================
  // 📊 نجيب تفضيلات المستخدم من التاريخ
  // ====================================================
  let completedCategories = [];
  let ignoredCategories = [];
  let yesterdayCategory = null;
  
  try {
    // المهام المكتملة
    const completedSnapshot = await db
      .collection("userTasks")
      .where("userId", "==", userId)
      .where("status", "==", "completed")
      .orderBy("completedAt", "desc")
      .limit(10)
      .get();
    console.log(`   ✅ Completed query success: ${completedSnapshot.size}`);
    
    completedSnapshot.forEach((t) => {
      const cat = t.data().category;
      if (cat) completedCategories.push(cat);
    });

    // المهام المتجاهلة
    const ignoredSnapshot = await db
      .collection("userTasks")
      .where("userId", "==", userId)
      .where("ignored", "==", true)
      .orderBy("ignoredAt", "desc")
      .limit(10)
      .get();

    ignoredSnapshot.forEach((t) => {
      const cat = t.data().category;
      if (cat) ignoredCategories.push(cat);
    });

    // مهمة أمس
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    const yesterdayStart = new Date(yesterday);
    yesterdayStart.setHours(0, 0, 0, 0);
    const yesterdayEnd = new Date(yesterday);
    yesterdayEnd.setHours(23, 59, 59, 999);

    const yesterdaySnapshot = await db
      .collection("userTasks")
      .where("userId", "==", userId)
      .where("selectedAt", ">=", admin.firestore.Timestamp.fromDate(yesterdayStart))
      .where("selectedAt", "<=", admin.firestore.Timestamp.fromDate(yesterdayEnd))
      .limit(1)
      .get();

    yesterdayCategory = yesterdaySnapshot.docs[0]?.data().category;
    
  } catch (e) {
    console.error(`   ❌ Error fetching user history:`, e.message);
  }

  console.log(`   ✅ Completed: ${completedCategories.length} (${completedCategories.join(", ")})`);
  console.log(`   ✅ Ignored: ${ignoredCategories.length} (${ignoredCategories.join(", ")})`);
  console.log(`   ✅ Yesterday: ${yesterdayCategory || "None"}`);

  // ====================================================
  // 🤖 بناء الـ prompt البسيط
  // ====================================================
  const prompt = `
اختر مهمة واحدة من هذه القائمة:

${availableTasks.map((t, i) => `${i+1}. ${t.title}`)}).join('\n')}

معلومات عن المستخدم:
- المهام المكتملة سابقاً: ${completedCategories.join(", ") || "لا يوجد"}
- المهام المتجاهلة سابقاً: ${ignoredCategories.join(", ") || "لا يوجد"}
- مهمة الأمس: ${yesterdayCategory || "لا يوجد"}

اختر مهمة مناسبة وخصص وصفاً قصيراً محفزاً يناسب هذا المستخدم.

الوصف لازم يكون قصير جداً (سطرين كحد أقصى).لا يتجاوز 20 كلمة.

أرجع JSON فقط:
{
 "index": رقم,
 "personalizedDescription": "وصف قصير جداً"
}
`;

  try {
    console.log(`   🤖 Starting Gemini attempts for user ${userId}`);
    
    // ====================================================
    // 🔄 آلية إعادة المحاولة (3 محاولات كحد أقصى)
    // ====================================================
    let geminiText = null;
    let geminiSuccess = false;
    let taskData = null;
    
    // تجربة حتى 3 مرات
    for (let attempt = 1; attempt <= 3; attempt++) {
      console.log(`   🔄 Gemini attempt ${attempt}/3...`);
      
      const modelName = "gemini-2.0-flash";
      const url = `https://generativelanguage.googleapis.com/v1/models/${modelName}:generateContent?key=${apiKey}`;
      
      try {
        const response = await fetch(url, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            contents: [
              {
                parts: [{ text: prompt }],
              },
            ],
            generationConfig: {
              temperature: 0.2,
              maxOutputTokens: 60            },
          }),
        });

        console.log(`   📡 Gemini response status: ${response.status}`);
        
        if (!response.ok) {
          console.log(`   ⚠️ Attempt ${attempt} failed with status ${response.status}`);
          if (attempt < 3) {
            console.log(`   ⏳ Waiting 1 second before retry...`);
            await new Promise(resolve => setTimeout(resolve, 1000));
          }
          continue;
        }
        if (!response.ok) {
  const errorText = await response.text();
  console.log(`❌ Gemini error body: ${errorText}`);
  console.log(`⚠️ Attempt ${attempt} failed with status ${response.status}`);
  continue;
}

const result = await response.json();
        console.log(JSON.stringify(result, null, 2));
        const text = result?.candidates?.[0]?.content?.parts?.[0]?.text;
        
        if (text && text.trim().length > 0) {
          geminiText = text;
          geminiSuccess = true;
          console.log(`   ✅ Gemini success on attempt ${attempt}`);
          break; // نجحنا، نخرج من الحلقة
        } else {
          console.log(`   ⚠️ Attempt ${attempt} returned empty text`);
        }
        
      } catch (fetchError) {
        console.log(`   ⚠️ Attempt ${attempt} fetch error:`, fetchError.message);
      }
      
      if (attempt < 3) {
        console.log(`   ⏳ Waiting 1 second before retry...`);
        await new Promise(resolve => setTimeout(resolve, 1000));
      }
    }
// ====================================================
// 📝 معالجة نتيجة Gemini (مقاومة للـ Markdown)
// ====================================================
if (geminiSuccess && geminiText) {
  console.log(`   📝 Response: ${geminiText}`);

  try {
    // تنظيف النص من markdown
    let cleanText = geminiText
      .replace(/```json/g, '')  // إزالة ```json
      .replace(/```/g, '')       // إزالة ```
      .replace(/`/g, '')         // إزالة ` الفردية
      .trim();

    // البحث عن أول { وآخر }
    const firstBrace = cleanText.indexOf('{');
    const lastBrace = cleanText.lastIndexOf('}');
    
    if (firstBrace === -1 || lastBrace === -1) {
      throw new Error("No JSON object found");
    }

    // استخراج JSON فقط
    const jsonString = cleanText.substring(firstBrace, lastBrace + 1);
    console.log(`   📦 Extracted JSON: ${jsonString}`);
    
    const parsed = JSON.parse(jsonString);

    const index = parsed.index - 1;

    if (index >= 0 && index < availableTasks.length) {
      taskData = availableTasks[index];
      personalizedDescription = parsed.personalizedDescription;
      console.log(`   ✨ Personalized description: "${personalizedDescription}"`);
    } else {
      console.log(`   ⚠️ Invalid index: ${parsed.index}`);
    }

  } catch (e) {
    console.log(`⚠️ Failed to parse Gemini JSON: ${e.message}`);
    console.log(`   Raw text: ${geminiText}`);
  }
}
    // ====================================================
    // 🧠 FALLBACK الذكي (إذا فشلت كل محاولات Gemini)
    // ====================================================
    if (!taskData) {
      console.log("   ⚠️ All Gemini attempts failed or invalid response, using intelligent fallback...");
      
      if (availableTasks.length > 0) {
        // ابدأ بكل المهام المتاحة
        let suitableTasks = [...availableTasks];
        
        console.log(`   📊 Total tasks available: ${suitableTasks.length}`);
        
        // استبعد مهمة الأمس إذا موجودة وكان في مهام أخرى
        if (yesterdayCategory && suitableTasks.length > 1) {
          const withoutYesterday = suitableTasks.filter(t => t.category !== yesterdayCategory);
          if (withoutYesterday.length > 0) {
            suitableTasks = withoutYesterday;
            console.log(`   🚫 Excluded yesterday's category: ${yesterdayCategory}`);
          }
        }
        
        // استبعد المهام المتجاهلة إذا موجودة وكان في مهام أخرى
        if (ignoredCategories.length > 0 && suitableTasks.length > 1) {
          const withoutIgnored = suitableTasks.filter(t => !ignoredCategories.includes(t.category));
          if (withoutIgnored.length > 0) {
            suitableTasks = withoutIgnored;
            console.log(`   🚫 Excluded ignored categories: ${ignoredCategories.join(', ')}`);
          }
        }
        
        // إذا عندنا تفضيلات، نستخدمها
        if (preferencesData && suitableTasks.length > 0) {
          // نعطي كل مهمة وزن بناءً على تفضيلات المستخدم
          const weightedTasks = suitableTasks.map(task => {
            let weight = 1.0;
            const catPref = preferencesData[task.category];
            
            if (catPref) {
              // كل ما زادت المهام المكتملة، زاد الوزن (لأنه يفضلها)
              weight += catPref.completed * 0.3;
              // كل ما زادت المهام المتجاهلة، قل الوزن
              weight -= catPref.ignored * 0.5;
              
              // إذا كانت هذه هي الفئة المفضلة، نزيد الوزن كثيراً
              if (task.category === preferredCategory) {
                weight += 2.0;
                console.log(`   ⭐ Preferred category bonus: ${task.category}`);
              }
            }
            
            // نضمن أن الوزن ما يقل عن 0.1
            weight = Math.max(0.1, weight);
            
            return { task, weight };
          });
          
          // نرتب حسب الوزن (الأعلى أولاً)
          weightedTasks.sort((a, b) => b.weight - a.weight);
          
          console.log(`   📊 Weighted tasks:`);
          weightedTasks.slice(0, 3).forEach((wt, i) => {
            console.log(`      ${i+1}. ${wt.task.title} (weight: ${wt.weight.toFixed(2)})`);
          });
          
          // اختيار عشوائي مع مراعاة الأوزان (الاختيار الموزون)
          const totalWeight = weightedTasks.reduce((sum, wt) => sum + wt.weight, 0);
          let random = Math.random() * totalWeight;
          
          for (const wt of weightedTasks) {
            random -= wt.weight;
            if (random <= 0) {
              taskData = wt.task;
              console.log(`   ✅ Selected based on preferences (weight: ${wt.weight.toFixed(2)})`);
              break;
            }
          }
          
          // إذا فشل الاختيار الموزون، نختار أعلى وزن
          if (!taskData && weightedTasks.length > 0) {
            taskData = weightedTasks[0].task;
            console.log(`   ✅ Selected top weighted task`);
          }
        }
        
        // إذا ما زلنا ما اخترنا مهمة، نختار عشوائياً
        if (!taskData) {
          const randomIndex = Math.floor(Math.random() * suitableTasks.length);
          taskData = suitableTasks[randomIndex];
          console.log(`   ✅ Random fallback selected: ${taskData.title} (${taskData.category})`);
        }
      } else {
        console.log(`❌ No tasks available for ${userId}`);
        continue;
      }
    }

    // ====================================================
    // ✅ إنشاء المهمة في Firestore
    // ====================================================
    if (taskData) {
      const task = {
    ...taskData, // ✅ ينسخ كل خصائص الحساب

    description: personalizedDescription || taskData.description,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    status: "pending",
  };

      await db
        .collection("dailyTasks")
        .doc(userId)
        .collection("tasks")
        .doc(today)
        .set(task);

      console.log(`✅ AI Task created for: ${userId} | ${task.title}`);
      tasksCreated++;
    } else {
      console.log(`❌ No task could be created for ${userId}`);
    }
    
  } catch (error) {
    console.error("❌ AI generation failed for:", userId, error);
    
    // استخدام fallback في حالة الخطأ غير المتوقع
    if (availableTasks.length > 0) {
      try {
        const randomIndex = Math.floor(Math.random() * availableTasks.length);
        const taskData = availableTasks[randomIndex];
 const task = {
  ...taskData, // 👈 ينسخ كل خصائص الحساب

  description: personalizedDescription || taskData.description,
  createdAt: admin.firestore.FieldValue.serverTimestamp(),
  status: "pending",
};

        await db
          .collection("dailyTasks")
          .doc(userId)
          .collection("tasks")
          .doc(today)
          .set(task);

        console.log(`✅ Emergency fallback task created for: ${userId} | ${task.title}`);
        tasksCreated++;
      } catch (fallbackError) {
        console.error(`❌ Emergency fallback also failed for ${userId}:`, fallbackError);
      }
    }
  }
}

    console.log(`\n🎉 Daily AI tasks generated - Created ${tasksCreated} tasks`);
  }
);

// ============================================================
// ✅ 2. دالة تجاهل المهام غير المكتملة
// ============================================================
exports.markIncompleteTasksAsIgnored = onSchedule(
  {
    schedule: "0 23 * * *", // 11:00 pm كل يوم
    timeZone: "Asia/Riyadh",
  },
  async () => {
    console.log("⏰ بدأ تجاهل المهام غير المكتملة...");

    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    
    const startOfDay = new Date(yesterday);
    startOfDay.setHours(0, 0, 0, 0);
    const endOfDay = new Date(yesterday);
    endOfDay.setHours(23, 59, 59, 999);

    console.log(`📅 Processing date: ${yesterday.toISOString().split('T')[0]}`);

    try {
      const snapshot = await db
        .collection("userTasks")
        .where("selectedAt", ">=", admin.firestore.Timestamp.fromDate(startOfDay))
        .where("selectedAt", "<=", admin.firestore.Timestamp.fromDate(endOfDay))
        .where("status", "==", "pending")
        .get();

      console.log(`📊 عدد المهام غير المكتملة: ${snapshot.size}`);

      if (snapshot.size === 0) {
        console.log("✨ لا توجد مهام غير مكتملة");
        return;
      }

      const batch = db.batch();
      let count = 0;

      snapshot.docs.forEach((doc) => {
        console.log(`   ⏰ Marking as ignored: ${doc.id}`);
        batch.update(doc.ref, {
          ignored: true,
          ignoredAt: admin.firestore.FieldValue.serverTimestamp(),
          ignoredReason: "expired",
          status: "ignored",
        });
        count++;
      });

      await batch.commit();
      console.log(`✅ تم تجاهل ${count} مهمة غير مكتملة`);
      
    } catch (error) {
      console.error("❌ فشل تجاهل المهام:", error);
    }
  }
);

// ============================================================
// ✅ 3. دالة تحديث تفضيلات المستخدم (ديناميكية بالكامل)
// ============================================================
exports.updateUserPreferences = onSchedule(
  {
    schedule: "0 23 * * *", // 11:00 PM كل يوم
    timeZone: "Asia/Riyadh",
  },
  async () => {
    console.log("⏰ بدأ تحديث تفضيلات المستخدمين (على مستوى المهام)...");
    
    try {
      // أولاً: نجيب كل المهام الفعالة
      const tasksSnapshot = await db
        .collection("tasks")
        .where("status", "==", "active")
        .get();
      
      const tasksMap = {};
      const allTaskIds = [];
      
tasksSnapshot.forEach(doc => {
  const task = doc.data();

  tasksMap[doc.id] = {
    title: task.title,
    category: task.category,
    points: task.points || 10
  };

  allTaskIds.push(doc.id);
});
      
      console.log(`📊 Found ${allTaskIds.length} active tasks`);
      
      const users = await db.collection("users").get();
      console.log(`👥 Total users: ${users.size}`);
      
      let updatedCount = 0;
      
      for (const userDoc of users.docs) {
        const userId = userDoc.id;
        console.log(`\n👤 Processing preferences for: ${userId}`);
        
        // تاريخ آخر 30 يوم
        const thirtyDaysAgo = new Date();
        thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
        const thirtyDaysAgoTimestamp = admin.firestore.Timestamp.fromDate(thirtyDaysAgo);
        
        // ====================================================
        // 📊 1. نجيب المهام المكتملة من submissions
        // ====================================================
        const submissionsSnapshot = await db
          .collection("submissions")
          .where("userId", "==", userId)
          .where("status", "==", "approved")
          .where("createdAt", ">=", thirtyDaysAgoTimestamp)
          .get();
        
        console.log(`   📊 Approved submissions (last 30d): ${submissionsSnapshot.size}`);
        
        // ====================================================
        // 📊 2. نجيب المهام المكتملة من userTasks
        // ====================================================
        const completedTasksSnapshot = await db
          .collection("userTasks")
          .where("userId", "==", userId)
          .where("status", "==", "completed")
          .where("completedAt", ">=", thirtyDaysAgoTimestamp)
          .get();
        
        console.log(`   📊 Completed userTasks (last 30d): ${completedTasksSnapshot.size}`);
        
        // ====================================================
        // 📊 3. نجيب المهام المتجاهلة من userTasks
        // ====================================================
        const ignoredTasksSnapshot = await db
          .collection("userTasks")
          .where("userId", "==", userId)
          .where("ignored", "==", true)
          .where("ignoredAt", ">=", thirtyDaysAgoTimestamp)
          .get();
        
        console.log(`   📊 Ignored tasks (last 30d): ${ignoredTasksSnapshot.size}`);
        
        // ====================================================
        // 🧮 نبني تفضيلات لكل مهمة على حدة
        // ====================================================
        const taskPreferences = {};
        
        // نبدأ بكل المهام الفعالة بوزن أساسي
        allTaskIds.forEach(taskId => {
          taskPreferences[taskId] = {
            taskId,
            title: tasksMap[taskId].title,
            category: tasksMap[taskId].category,
            points: tasksMap[taskId].points,
            completed: 0,
            ignored: 0,
            lastCompletedAt: null,
            lastIgnoredAt: null
          };
        });
        
        // معالجة submissions (المهام المكتملة)
        submissionsSnapshot.docs.forEach((doc) => {
          const sub = doc.data();
          const taskId = sub.taskId;
          
          if (taskPreferences[taskId]) {
            taskPreferences[taskId].completed++;
            taskPreferences[taskId].lastCompletedAt = sub.createdAt;
          }
        });
        
        // معالجة completed userTasks
        completedTasksSnapshot.docs.forEach((doc) => {
          const task = doc.data();
          const taskId = task.taskId;
          
          if (taskPreferences[taskId]) {
            taskPreferences[taskId].completed++;
            taskPreferences[taskId].lastCompletedAt = task.completedAt;
          }
        });
        
        // معالجة ignored userTasks
        ignoredTasksSnapshot.docs.forEach((doc) => {
          const task = doc.data();
          const taskId = task.taskId;
          
          if (taskPreferences[taskId]) {
            taskPreferences[taskId].ignored++;
            taskPreferences[taskId].lastIgnoredAt = task.ignoredAt;
          }
        });
        
        // حساب النقاط والترتيب
        const taskScores = {};
        let topTaskId = null;
        let topScore = -100;
        
        for (const taskId in taskPreferences) {
          const stats = taskPreferences[taskId];
          
          // معادلة محسنة للمهمة الواحدة
          let score = 1.0; // وزن أساسي
          score += stats.completed * 2; // كل إكمال +2
          score -= stats.ignored * 3;    // كل تجاهل -3
          
          // إذا تم إكمالها مؤخراً، نخفض وزنها شوي (نتجنب التكرار)
          if (stats.lastCompletedAt) {
            const daysSinceLastComplete = (Date.now() - stats.lastCompletedAt.toDate()) / (1000 * 60 * 60 * 24);
            if (daysSinceLastComplete < 7) {
              score -= 2; // خفف الوزن إذا اكتملت خلال أسبوع
            }
          }
          
          // إذا تم تجاهلها مؤخراً، نخفض وزنها كثيراً
          if (stats.lastIgnoredAt) {
            const daysSinceLastIgnored = (Date.now() - stats.lastIgnoredAt.toDate()) / (1000 * 60 * 60 * 24);
            if (daysSinceLastIgnored < 14) {
              score -= 5; // خفف الوزن كثيراً إذا تجاهلها خلال أسبوعين
            }
          }
          
          // نضمن أن الوزن ما يقل عن 0.1
          score = Math.max(0.1, score);
          
          taskScores[taskId] = {
            ...stats,
            score,
            preferenceLevel: score > 5 ? "high" : score > 2 ? "medium" : "low"
          };
          
          if (score > topScore) {
            topScore = score;
            topTaskId = taskId;
          }
        }
        
        // ترتيب أفضل المهام
        const sortedTasks = Object.values(taskScores)
          .sort((a, b) => b.score - a.score)
          .slice(0, 5); // أفضل 5 مهام
        
        console.log(`   🏆 Top task: ${sortedTasks[0]?.title} (score: ${sortedTasks[0]?.score.toFixed(2)})`);
        console.log(`   📊 Top 5 tasks:`, sortedTasks.map(t => `${t.title} (${t.score.toFixed(2)})`).join(', '));
        
        // ====================================================
        // 💾 حفظ في Firestore
        // ====================================================
        await db.collection("userTaskPreferences").doc(userId).set({
          taskPreferences: taskScores,
          topTaskId,
          topTaskTitle: sortedTasks[0]?.title,
          topTasks: sortedTasks.map(t => t.taskId),
          lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
          totalTasksAnalyzed: submissionsSnapshot.size + completedTasksSnapshot.size,
          totalIgnoredAnalyzed: ignoredTasksSnapshot.size,
          period: "last_30_days"
        }, { merge: true });
        
        console.log(`   ✅ Task preferences updated for ${userId}`);
        updatedCount++;
      }
      
      console.log(`\n✅ تم تحديث تفضيلات المهام لـ ${updatedCount} مستخدم بنجاح`);
      
    } catch (error) {
      console.error("❌ فشل تحديث تفضيلات المهام:", error);
    }
  }
);