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
});

const { DateTime } = require("luxon");

/* ============================================================
 * ✅ suggestBonusTask → Callable Function
 * تستقبل: pressedAt (ISO string) و userLocation (GeoPoint اختياري)
 * ترجع: مهمة إضافية مقترحة من Gemini بناءً على الوقت والموقع وتاريخ المستخدم
 * ============================================================ */
exports.suggestBonusTask = onCall(async (request) => {const auth = request.auth;
if (!auth || !auth.uid) {
  throw new HttpsError("unauthenticated", "User not logged in");
}

const userId = auth.uid;
const pressedAt = request.data?.pressedAt || new Date().toISOString();

// ✅ استقبال الموقع من الـ request (اختياري)
const userLocation = request.data?.userLocation || null;

const apiKey = GEMINI_API_KEY.value();
if (!apiKey) {
  throw new HttpsError("failed-precondition", "GEMINI_API_KEY_MISSING");
}

const pressedDate = new Date(pressedAt);
const hour = pressedDate.getHours();

// ====================================================
// ⏰ تحضير سياق الوقت
// ====================================================
let timeContext = "";
if (hour >= 5 && hour < 12) {
  timeContext = "الصباح الباكر — المستخدم نشيط وعنده طاقة";
} else if (hour >= 12 && hour < 15) {
  timeContext = "وقت الظهيرة — المستخدم في منتصف يومه";
} else if (hour >= 15 && hour < 18) {
  timeContext = "بعد الظهر — المستخدم يتحضر لنهاية اليوم";
} else if (hour >= 18 && hour < 21) {
  timeContext = "المساء — المستخدم في وقت الراحة";
} else {
  timeContext = "الليل — المستخدم في آخر يومه";
}

// ====================================================
// 📍 تحضير سياق الموقع
// ====================================================
let locationContext = "";
let nearbyPlaces = [];
let userLocationFromDb = null;

// دالة مساعدة لحساب المسافة
function calculateDistance(lat1, lon1, lat2, lon2) {
  const R = 6371; // Radius of the earth in km
  const dLat = deg2rad(lat2 - lat1);
  const dLon = deg2rad(lon2 - lon1);
  const a = 
    Math.sin(dLat/2) * Math.sin(dLat/2) +
    Math.cos(deg2rad(lat1)) * Math.cos(deg2rad(lat2)) * 
    Math.sin(dLon/2) * Math.sin(dLon/2); 
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a)); 
  const d = R * c; // Distance in km
  return d;
}

function deg2rad(deg) {
  return deg * (Math.PI/180);
}

try {
  // نجيب موقع المستخدم (من الـ request أو من قاعدة البيانات)
  let locationToUse = userLocation;
  
  // إذا ما أرسل موقع مع الـ request، نحاول نجيب آخر موقع من قاعدة البيانات
  if (!locationToUse) {
    const userDoc = await db.collection("users").doc(userId).get();
    const userData = userDoc.data();
    locationToUse = userData?.lastLocation;
    userLocationFromDb = locationToUse;
  }
  
  if (locationToUse) {
    console.log("📍 User location found:", locationToUse);
    
    // نجيب الحاويات القريبة (ضمن 2 كم)
    const containersSnapshot = await db
      .collection("recyclingCenters")
      .where("type", "==", "container")
      .get();
    
    // فلترة الحاويات القريبة
    containersSnapshot.forEach((doc) => {
      const center = doc.data();
      if (center.location) {
        const distance = calculateDistance(
          locationToUse.latitude,
          locationToUse.longitude,
          center.location.latitude,
          center.location.longitude
        );
        
        if (distance <= 2) { // ضمن 2 كم
          nearbyPlaces.push({
            id: doc.id,
            name: center.name,
            type: center.type,
            distance: Math.round(distance * 100) / 100,
            category: "recycling"
          });
        }
      }
    });
    
    // نجيب محطات النقل القريبة
    const stationsSnapshot = await db
      .collection("recyclingCenters")
      .where("type", "in", ["station", "center"])
      .get();
      
    stationsSnapshot.forEach((doc) => {
      const center = doc.data();
      if (center.location) {
        const distance = calculateDistance(
          locationToUse.latitude,
          locationToUse.longitude,
          center.location.latitude,
          center.location.longitude
        );
        
        if (distance <= 3) { // ضمن 3 كم للمحطات
          nearbyPlaces.push({
            id: doc.id,
            name: center.name,
            type: center.type,
            distance: Math.round(distance * 100) / 100,
            category: "recycling_station"
          });
        }
      }
    });
    
    console.log(`📍 Found ${nearbyPlaces.length} nearby places`);
  } else {
    console.log("📍 No user location found");
  }
} catch (e) {
  console.log("⚠️ Error processing location:", e.message);
}

// بناء سياق الموقع
if (userLocation || userLocationFromDb) {
  if (nearbyPlaces.length > 0) {
    const nearbyContainers = nearbyPlaces.filter(p => p.category === "recycling");
    const nearbyStations = nearbyPlaces.filter(p => p.category === "recycling_station");
    
    locationContext = "\n📍 بناءً على موقع المستخدم:";
    
    if (nearbyContainers.length > 0) {
      locationContext += `\n   • ${nearbyContainers.length} حاوية تدوير قريبة (أقربها بمسافة ${nearbyContainers[0].distance} كم)`;
    }
    
    if (nearbyStations.length > 0) {
      locationContext += `\n   • ${nearbyStations.length} محطة تدوير قريبة (أقربها بمسافة ${nearbyStations[0].distance} كم)`;
    }
  } else {
    locationContext = "\n📍 لا توجد حاويات أو محطات قريبة من المستخدم حالياً";
  }
} else {
  locationContext = "\n📍 موقع المستخدم غير معروف";
}

// ====================================================
// 📋 جلب بيانات المستخدم والمهام
// ====================================================
const currentMonth = new Date().toISOString().slice(0, 7);
const { DateTime } = require("luxon");
const today = DateTime.now().setZone("Asia/Riyadh").toFormat("yyyyLLdd");
const todayDocId = `${userId}_${today}`;

let todayTaskId = null;
try {
  const todaySnap = await db.collection("userTasks").doc(todayDocId).get();
  todayTaskId = todaySnap.data()?.taskId || null;
} catch (e) {
  console.log("⚠️ Could not fetch today's task:", e.message);
}

// ✅ جلب تفضيلات المستخدم من userTaskPreferences
let userTaskPrefs = null;
let topTaskIds = [];
let taskPreferencesData = {};
let preferredCategories = [];
let taskScores = {};

try {
  const prefsDoc = await db.collection("userTaskPreferences").doc(userId).get();
  if (prefsDoc.exists) {
    userTaskPrefs = prefsDoc.data();
    console.log("✅ Found userTaskPreferences");
    console.log("   Last updated:", userTaskPrefs.lastUpdated?.toDate?.() || userTaskPrefs.lastUpdated);
    console.log("   Period:", userTaskPrefs.period);
    
    // استخراج أفضل المهام
    topTaskIds = userTaskPrefs.topTasks || [];
    
    // استخراج بيانات التفضيلات الكاملة
    taskPreferencesData = userTaskPrefs.taskPreferences || {};
    
    // بناء خريطة Scores للمهام
    Object.entries(taskPreferencesData).forEach(([taskId, data]) => {
      taskScores[taskId] = data.score || 1;
    });
    
    // استخراج التصنيفات المفضلة (اللي فيها مهام بدرجة عالية)
    const categoryStats = {};
    Object.values(taskPreferencesData).forEach(task => {
      if (!categoryStats[task.category]) {
        categoryStats[task.category] = {
          completed: 0,
          ignored: 0,
          totalScore: 0,
          tasks: []
        };
      }
      categoryStats[task.category].completed += task.completed || 0;
      categoryStats[task.category].ignored += task.ignored || 0;
      categoryStats[task.category].totalScore += task.score || 1;
      categoryStats[task.category].tasks.push({
        id: task.taskId,
        title: task.title,
        score: task.score || 1
      });
    });
    
    // التصنيفات ذات الأولوية العالية (معدل score > 3)
    Object.entries(categoryStats).forEach(([category, stats]) => {
      const avgScore = stats.totalScore / (stats.tasks.length || 1);
      if (avgScore > 3 && stats.completed > stats.ignored) {
        preferredCategories.push(category);
      }
    });
    
    console.log("   Top task:", userTaskPrefs.topTaskTitle);
    console.log("   Preferred categories:", preferredCategories);
    console.log("   Top task IDs:", topTaskIds);
  } else {
    console.log("⚠️ No userTaskPreferences found");
  }
} catch (e) {
  console.log("⚠️ Could not fetch userTaskPreferences:", e.message);
}

// جلب المهام النشطة
const activeTasksSnapshot = await db
  .collection("tasks")
  .where("status", "==", "active")
  .get();

const availableTasks = [];
activeTasksSnapshot.forEach((doc) => {
  if (doc.id === todayTaskId) return;
  const task = doc.data();
  if (task.visible_from && task.visible_from > currentMonth) return;
  if (task.expiry_month && task.expiry_month < currentMonth) return;
  
  // إضافة score من التفضيلات إذا كان موجود
  const taskWithScore = { 
    id: doc.id, 
    ...task,
    preferenceScore: taskScores[doc.id] || 1
  };
  availableTasks.push(taskWithScore);
});

if (availableTasks.length === 0) {
  throw new HttpsError("not-found", "NO_TASKS_AVAILABLE");
}

// ترتيب المهام حسب الـ score من التفضيلات
availableTasks.sort((a, b) => (b.preferenceScore || 1) - (a.preferenceScore || 1));

let completedTaskIds = [];
let ignoredTaskIds = [];

try {
  const completedSnap = await db
    .collection("userTasks")
    .where("userId", "==", userId)
    .where("status", "==", "completed")
    .orderBy("completedAt", "desc")
    .limit(20)
    .get();
  completedSnap.forEach((d) => {
    const tid = d.data().taskId;
    if (tid) completedTaskIds.push(tid);
  });

  const ignoredSnap = await db
    .collection("userTasks")
    .where("userId", "==", userId)
    .where("ignored", "==", true)
    .orderBy("ignoredAt", "desc")
    .limit(20)
    .get();
  ignoredSnap.forEach((d) => {
    const tid = d.data().taskId;
    if (tid) ignoredTaskIds.push(tid);
  });
} catch (e) {
  console.log("⚠️ Could not load user history:", e.message);
}

// بناء نص التفضيلات المحسّن
let preferencesText = "";

if (topTaskIds.length > 0) {
  preferencesText += "\n🏆 **المهام المفضلة (أعلى تقييم):**";
  topTaskIds.slice(0, 5).forEach((taskId, index) => {
    const taskPref = taskPreferencesData[taskId];
    if (taskPref) {
      preferencesText += `\n   ${index+1}. ${taskPref.title} (أكملها ${taskPref.completed} مرات، درجة ${taskPref.score})`;
    }
  });
}

if (preferredCategories.length > 0) {
  preferencesText += `\n⭐ **التصنيفات المفضلة:** ${preferredCategories.join('، ')}`;
}

// إضافة المهام المتجاهلة
if (ignoredTaskIds.length > 0) {
  preferencesText += "\n🚫 **المهام المتجاهلة (تجنبها):**";
  ignoredTaskIds.slice(0, 3).forEach((taskId) => {
    const taskPref = taskPreferencesData[taskId];
    if (taskPref) {
      preferencesText += `\n   • ${taskPref.title}`;
    }
  });
}

const taskListText = availableTasks
  .map((t, i) => `${i + 1}. [${t.id}] ${t.title} — ${t.description || ""} (${t.category || ""}) [الدرجة: ${t.preferenceScore}]`)
  .join("\n");

// تحضير توصيات الموقع
let locationRecommendation = "";
if (nearbyPlaces.length > 0) {
  const nearbyRVM = nearbyPlaces.filter(p => p.name?.toLowerCase().includes('rvm'));
  const nearbyFoodContainers = nearbyPlaces.filter(p => p.name?.includes('طعام') || p.name?.includes('عضوي'));
  const nearbyContainers = nearbyPlaces.filter(p => p.category === "recycling");
  
  if (nearbyRVM.length > 0) {
    locationRecommendation = `\n📍 المستخدم قريب من آلة RVM (${nearbyRVM[0].distance} كم) → اقترح مهمة تدوير`;
  } else if (nearbyFoodContainers.length > 0) {
    locationRecommendation = `\n📍 المستخدم قريب من حاوية طعام (${nearbyFoodContainers[0].distance} كم) → اقترح مهمة تدوير عضوي`;
  } else if (nearbyContainers.length > 0) {
    locationRecommendation = `\n📍 المستخدم قريب من ${nearbyContainers.length} حاوية تدوير (أقربها ${nearbyContainers[0].distance} كم) → اقترح مهمة تدوير`;
  }
} else {
  locationRecommendation = `\n📍 لا توجد حاويات أو محطات قريبة من المستخدم → اقترح مهام منزلية`;
}

// توصيات الوقت المحسّنة
let timeRecommendation = "";
if (hour >= 5 && hour < 12) {
  timeRecommendation = "\n🌅 الصباح: وقت نشاط وحيوية → مناسب للمهام الحركية (نقل، تدوير، مشي)";
} else if (hour >= 12 && hour < 16) {
  timeRecommendation = "\n☀️ الظهيرة: وقت الراحة → مناسب للمهام السريعة";
} else if (hour >= 16 && hour < 20) {
  timeRecommendation = "\n🌆 العصر/المساء: وقت مناسب جداً لمهام التدوير وإعادة التدوير ♻️";
} else {
  timeRecommendation = "\n🌙 الليل: وقت هادئ → مناسب لمهام التوعية والقراءة";
}

const prompt = `
أنت مساعد بيئي ذكي متخصص في تخصيص المهام. مهمتك: اختر مهمة واحدة فقط من القائمة تناسب هذا المستخدم تحديداً.

📊 **ملف المستخدم الشخصي (من userTaskPreferences - آخر تحديث: ${userTaskPrefs?.lastUpdated?.toDate?.() || 'غير معروف'}):**
${preferencesText || "   لا توجد بيانات كافية عن تفضيلات المستخدم"}

⏰ **الوقت الحالي:**
${timeContext} (الساعة ${hour}:00)${timeRecommendation}

📍 **الموقع:**
${locationContext}${locationRecommendation}

📋 **قائمة المهام المتاحة (مرتبة حسب تفضيلات المستخدم):**
${taskListText}

🎯 **قرارك يجب أن يراعي بدقة:**
1. **الأولوية القصوى**: اختر من المهام المفضلة (topTaskIds) إن أمكن - الدرجة العالية تعني تفضيل قوي
2. **التصنيفات المفضلة**: فضّل المهام من التصنيفات: ${preferredCategories.join('، ') || 'لا توجد'}
3. **تجنب تماماً**: المهام المتجاهلة (🚫) في القائمة أعلاه
4. **الموقع**: ${nearbyPlaces.length > 0 ? "استغل قرب المستخدم من مواقع التدوير" : "المستخدم في المنزل → فضّل مهام توفير الطاقة/الماء"}
5. **الوقت**: اختر مهمة مناسبة للوقت الحالي

⚠️ **تنبيه مهم**: 
- المهام ذات الدرجة (preferenceScore) العالية > 5 هي الأكثر تفضيلاً
- إذا المستخدم عنده مهام مفضلة بدرجة عالية، اختر منها حتماً
- استخدم بيانات completed و ignored من التفضيلات
- المهام ذات completed عالي و ignored منخفض هي الأفضل

📝 **الوصف المحفز (الأهم)**:
اكتب وصفاً **جديداً ومختلفاً تماماً** عن الوصف الأصلي للمهمة. 
الوصف الأصلي للمهمة هو: "${pickedTask?.description || ''}"

**ممنوع نسخ الوصف الأصلي**. اكتب وصفاً جديداً كلياً:
- شخصي: خاطب المستخدم بلطف (أنت/لك/معك)
- عملي: اربطه بسياقه الحالي (الوقت/الموقع/الوصف الأصلي)
- محفز: استخدم كلمات تشجيعية ودودة
- قصير: ١٥-٢٠ كلمة فقط
- مختلف: لا يشبه الوصف الأصلي أبداً

أمثلة على أوصاف مقنعة (اكتب زي كذا بأسلوبك):
- "لقمتك الباقية ممكن تتحول إلى سماد! حاوية الطعام قريبة منك، شارك في دورة الحياة الجميلة 🌱"
- "فيه حاوية بلاستيك قريبة، حتى الزجاجة الوحيدة إذا وصلت لها تصنع فرق! جرب تجمع اللي عندك ♻️"
- "RVM قريب منك! كل زجاجة بتدويرها تعني ريال في جيبك ونقاط في رصيدك، مكسب مزدوج تستحقه 💚"
- "الصباح المنعش يدعوك للمشي! وش رأيك توصل على رجليك، تنشط جسمك وتجمع نقاط 🌅"
- "المسافة لمحطة الباص ٥ دقائق مشي، جرب تستغلها بدل الزحمة، نوفر معاً كربون ووقت 🚌"

**أرجع JSON فقط بهذا الشكل:**
{
  "taskId": "ID المهمة من القائمة",
  "personalizedDescription": "وصف جديد كلياً يختلف عن الوصف الأصلي"
}
`;

// ====================================================
// 🔄 محاولة Gemini (3 مرات كحد أقصى)
// ====================================================
let geminiText = null;
let geminiSuccess = false;

for (let attempt = 1; attempt <= 3; attempt++) {
  try {
    const url = `https://generativelanguage.googleapis.com/v1/models/gemini-2.0-flash:generateContent?key=${apiKey}`;
    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: { temperature: 0.4, maxOutputTokens: 300 },
      }),
    });

    if (!response.ok) {
      console.log(`⚠️ Gemini attempt ${attempt} failed with status ${response.status}`);
      await new Promise((r) => setTimeout(r, 1000));
      continue;
    }

    const result = await response.json();
    const text = result?.candidates?.[0]?.content?.parts?.[0]?.text;
    if (text && text.trim().length > 0) {
      geminiText = text;
      geminiSuccess = true;
      console.log(`✅ Gemini success on attempt ${attempt}`);
      break;
    }
  } catch (e) {
    console.log(`⚠️ Attempt ${attempt} error:`, e.message);
    await new Promise((r) => setTimeout(r, 1000));
  }
}

// ====================================================
// 📝 معالجة نتيجة Gemini
// ====================================================
let pickedTask = null;
let personalizedDescription = null;

if (geminiSuccess && geminiText) {
  try {
    let clean = geminiText.replace(/```json/g, "").replace(/```/g, "").replace(/`/g, "").trim();
    const first = clean.indexOf("{");
    const last = clean.lastIndexOf("}");
    if (first !== -1 && last !== -1) {
      const parsed = JSON.parse(clean.substring(first, last + 1));
      pickedTask = availableTasks.find((t) => t.id === parsed.taskId) || null;
      personalizedDescription = parsed.personalizedDescription || null;
      console.log(`✅ Gemini selected task: ${pickedTask?.title}`);
    }
  } catch (e) {
    console.log("⚠️ Failed to parse Gemini response:", e.message);
  }
}

// ====================================================
// 🧠 FALLBACK الذكي باستخدام التفضيلات
// ====================================================
if (!pickedTask) {
  console.log("⚠️ Using preference-based fallback...");
  
  // فلترة المهام المتجاهلة
  const nonIgnoredTasks = availableTasks.filter(t => !ignoredTaskIds.includes(t.id));
  
  // الخطوة 1: جرب أفضل المهام من topTasks
  if (topTaskIds.length > 0) {
    for (const taskId of topTaskIds) {
      const task = nonIgnoredTasks.find(t => t.id === taskId);
      if (task) {
        pickedTask = task;
        console.log(`✅ Selected from topTasks: ${task.title} (score: ${task.preferenceScore})`);
        break;
      }
    }
  }
  
  // الخطوة 2: جرب المهام ذات الـ score العالي (> 5)
  if (!pickedTask) {
    const highScoreTasks = nonIgnoredTasks.filter(t => (t.preferenceScore || 1) > 5);
    if (highScoreTasks.length > 0) {
      // رتب حسب الـ score
      highScoreTasks.sort((a, b) => (b.preferenceScore || 1) - (a.preferenceScore || 1));
      pickedTask = highScoreTasks[0];
      console.log(`✅ Selected high score task: ${pickedTask.title} (score: ${pickedTask.preferenceScore})`);
    }
  }
  
  // الخطوة 3: جرب المهام من التصنيفات المفضلة
  if (!pickedTask && preferredCategories.length > 0) {
    const categoryTasks = nonIgnoredTasks.filter(t => 
      preferredCategories.includes(t.category)
    );
    
    if (categoryTasks.length > 0) {
      // رتب حسب الـ score
      categoryTasks.sort((a, b) => (b.preferenceScore || 1) - (a.preferenceScore || 1));
      pickedTask = categoryTasks[0];
      console.log(`✅ Selected from preferred categories: ${pickedTask.title}`);
    }
  }
  
  // الخطوة 4: جرب المهام المكتملة سابقاً
  if (!pickedTask && completedTaskIds.length > 0) {
    const completedTasks = nonIgnoredTasks.filter(t => completedTaskIds.includes(t.id));
    if (completedTasks.length > 0) {
      completedTasks.sort((a, b) => (b.preferenceScore || 1) - (a.preferenceScore || 1));
      pickedTask = completedTasks[0];
      console.log(`✅ Selected from previously completed: ${pickedTask.title}`);
    }
  }
  
  // الخطوة 5: جرب أي مهمة غير متجاهلة
  if (!pickedTask && nonIgnoredTasks.length > 0) {
    // رتب حسب الـ score
    nonIgnoredTasks.sort((a, b) => (b.preferenceScore || 1) - (a.preferenceScore || 1));
    pickedTask = nonIgnoredTasks[0];
    console.log(`✅ Selected top scored non-ignored task: ${pickedTask.title}`);
  }
  
  // الخطوة 6: أخيراً، أي مهمة متاحة
  if (!pickedTask && availableTasks.length > 0) {
    pickedTask = availableTasks[0];
    console.log(`✅ Selected first available task: ${pickedTask.title}`);
  }
  
  // توليد وصف شخصي بسيط
// توليد وصف شخصي محسّن ومتنوع
if (!personalizedDescription && pickedTask) {
  const taskPref = taskPreferencesData[pickedTask.id];
  const recyclingCats = ["إعادة التدوير", "recycling"];
  const transportCats = ["وسائل النقل المستدامة", "النقل", "وسائل النقل"];
  const awarenessCats = ["التوعية والاستدامة", "الوعي"];
  const energyCats = ["الكهرباء", "الطاقة"];
  const waterCats = ["الماء", "ترشيد الماء"];
  
  // 1. موقع قريب جداً (أقل من 1 كم)
  if (nearbyPlaces.length > 0) {
    const nearest = nearbyPlaces[0];
    
    // 🚏 محطة باص أو مترو قريبة
    if (nearest.type === "station" || nearest.type === "center" || 
        nearest.name?.includes('باص') || nearest.name?.includes('bus') || 
        nearest.name?.includes('مترو') || nearest.name?.includes('metro')) {
      
      if (transportCats.includes(pickedTask.category)) {
        if (nearest.distance < 0.3) {
          personalizedDescription = `🚏 محطة باص على بعد خطوات منك (${nearest.distance} كم)! جرب تستخدم النقل العام بدل الزحمة، نوفر معاً كربون ووقت ✨`;
        } else if (nearest.distance < 1) {
          personalizedDescription = `🚌 محطة باص قريبة منك (${nearest.distance} كم)! مشوارك القادم جرب توصلها بالمشي وتستخدم الباص، توفير ووعي 💚`;
        } else {
          personalizedDescription = `🚍 محطة باص على بعد ${nearest.distance} كم! بديل رائع للسيارة، يوفر كربون ويجمع لك نقاط 🌿`;
        }
      } else {
        // إذا كانت المهمة مو نقل، نقترح مهمة نقل مناسبة
        personalizedDescription = `🚏 محطة باص قريبة منك (${nearest.distance} كم)! فرصة ذهبية تجرب التنقل المستدام وتجمع نقاط إضافية ✨`;
      }
    }
    // 🥗 حاوية طعام
    else if (nearest.name?.includes('طعام') || nearest.name?.includes('عضوي')) {
      if (recyclingCats.includes(pickedTask.category)) {
        if (nearest.distance < 0.5) {
          personalizedDescription = `🥗 حاوية طعام على بعد خطوات منك (${nearest.distance} كم)! بقايا غدائك تتحول لسماد يغذي الأرض، شارك في دورة الحياة الجميلة 🌱`;
        } else {
          personalizedDescription = `🍽️ حاوية طعام قريبة منك (${nearest.distance} كم)! لقمتك الباقية ممكن تتحول إلى سماد، لا ترميها ✨`;
        }
      }
    }
    // 💰 RVM (آلة تدوير)
    else if (nearest.name?.toLowerCase().includes('rvm')) {
      if (recyclingCats.includes(pickedTask.category)) {
        if (nearest.distance < 0.5) {
          personalizedDescription = `💰 RVM قريب جداً منك! كل زجاجة بتدويرها تعني ريال في محفظتك ونقاط في رصيدك، مكسب مزدوج ✨`;
        } else {
          personalizedDescription = `🔄 آلة RVM على بعد ${nearest.distance} كم! كل قارورة تدخلها تزيد رصيدك ريال، جرب تجمع اللي عندك ♻️`;
        }
      }
    }
    // ♻️ حاوية تدوير عادية
    else if (recyclingCats.includes(pickedTask.category)) {
      if (nearest.distance < 0.3) {
        personalizedDescription = `♻️ حاوية تدوير قريبة جداً (${nearest.distance} كم)! حتى العلبة الوحيدة تصنع فرق، جرب تمشي لها الحين 🌍`;
      } else {
        personalizedDescription = `🌍 حاوية تدوير على بعد ${nearest.distance} كم منك! البلاستيك والورق اللي عندك ممكن يبدأ حياة جديدة، شارك ♻️`;
      }
    }
  }
  
  // 2. إذا ما في موقع قريب، شوف الوقت
  else {
    // الصباح الباكر (٥-٩ صباحاً)
    if (hour >= 5 && hour < 9) {
      if (transportCats.includes(pickedTask.category)) {
        personalizedDescription = `🌅 الصباح المنعش يدعوك للمشي أو ركوب الباص! جرب تستغل محطة الباص القريبة وتنقل بشكل مستدام ✨`;
      } else if (recyclingCats.includes(pickedTask.category)) {
        personalizedDescription = `☀️ بداية يومك بوعي! جرب تفرز المخلفات اللي عندك، خطوة بسيطة وأثرها كبير على بيئتك 🌱`;
      } else {
        personalizedDescription = `🌅 صباح الخير! ${pickedTask.title} ممكن تكون أجمل بداية ليومك، جربها ☕`;
      }
    }
    // الظهيرة (١٢-٤ عصراً)
    else if (hour >= 12 && hour < 16) {
      if (energyCats.includes(pickedTask.category)) {
        personalizedDescription = `☀️ وقت الظهيرة حار! تأكد إن الأجهزة اللي ما تستخدمها مفصولة، فاتورتك والبيئة بيشكرونك ⚡`;
      } else if (waterCats.includes(pickedTask.category)) {
        personalizedDescription = `💧 تسرب بسيط من الصنبور يضيع مئات اللترات! لحظة تفقد اليوم توفر كثير على بيتك 🚰`;
      } else if (transportCats.includes(pickedTask.category)) {
        personalizedDescription = `🚌 الظهر وقت هدوء الشوارع! جرب تستخدم الباص بدل السيارة لمشاويرك ✨`;
      } else {
        personalizedDescription = `🌞 بعد الظهر وقت مناسب لمهمة ${pickedTask.title}، جربها تضيف نقاط لرصيدك ✨`;
      }
    }
    // المساء (٤-٨ مساءً)
    else if (hour >= 16 && hour < 20) {
      if (recyclingCats.includes(pickedTask.category)) {
        personalizedDescription = `🌆 المساء وقت مناسب لترتيب المخلفات! جرب تفرز البلاستيك والورق اليوم ♻️`;
      } else if (transportCats.includes(pickedTask.category)) {
        personalizedDescription = `🚶‍♀️ الجو بدأ يلطف! جرب تمشي لأقرب محطة باص وتنقل مستدام، صحتك والبيئة تستاهل 🌆`;
      } else {
        personalizedDescription = `🌇 مساء جميل لمهمة ${pickedTask.title}، دقيقتين بس وتأثيرها يدوم 💚`;
      }
    }
    // الليل (بعد ٨ مساءً)
    else {
      if (awarenessCats.includes(pickedTask.category)) {
        personalizedDescription = `🌙 وقت هادئ للقراءة! خبر بيئي جديد ينتظرك، دقيقتين بس تتعلم شيء جديد وتجمع نقاط 📚`;
      } else if (energyCats.includes(pickedTask.category)) {
        personalizedDescription = `💡 قبل ما تنام، تأكد إن الأجهزة اللي ما تحتاجها مفصولة. فاتورتك الأقل وبيئة أفضل ✨`;
      } else if (transportCats.includes(pickedTask.category)) {
        personalizedDescription = `🌙 فكر بكرا! محطة الباص قريبة منك، ممكن تبدأ يومك بتنقل مستدام وتجمع نقاط من بدري ✨`;
      } else {
        personalizedDescription = `🌙 ${pickedTask.title} قبل النوم؟ فكرة جميلة، إنجاز بسيط وأثره كبير 💚`;
      }
    }
  }
  
  // 3. إذا كانت المهمة مفضلة سابقة
  if (!personalizedDescription && taskPref && taskPref.completed > 0) {
    if (taskPref.completed >= 5) {
      personalizedDescription = `🏆 أنت بطلة في ${pickedTask.title}! أكملتها ${taskPref.completed} مرات، استمري بنفس الروعة والبيئة بتشكرك 🌟`;
    } else {
      personalizedDescription = `⭐ واضح إنك تحب ${pickedTask.title}! أكملتها ${taskPref.completed} مرات، جربها مرة ثانية تضيف نقاطك ✨`;
    }
  }
  
  // 4. إذا كانت من تصنيف مفضل
  if (!personalizedDescription && preferredCategories.includes(pickedTask.category)) {
    personalizedDescription = `💚 ${pickedTask.category} من اهتماماتك! جرب هالمهمة الحلوة، راح تعجبك أكيد 🌱`;
  }
  
  // 5. وصف عام (إذا ما طبقنا شيء من فوق)
  if (!personalizedDescription) {
    const generalDescriptions = [
      `🌱 ${pickedTask.title} مهمة بسيطة وأثرها كبير على بيئتك. جربها اليوم تضيف نقاط لرصيدك ✨`,
      `💚 كل خطوة صغيرة بتفرق! ${pickedTask.title} خطوة جميلة نحو استدامة أفضل 🤍`,
      `⭐ ${pickedTask.title} تستاهل تجربها! نقاط إضافية في رصيدك وأثر جميل على الأرض 🌍`,
      `✨ ${pickedTask.title} راح تزيد نقاطك وتخلي يومك أحلى، جربها الحين! 🌱`,
      `🌿 ${pickedTask.title} فرصة تتعلم شيء جديد وتفيد البيئة، ليه لا؟ 💚`,
      `🚌 محطة الباص قريبة منك! ${pickedTask.title} ممكن تكون خطوتك الأولى نحو تنقل مستدام ✨`
    ];
    const randomIndex = Math.floor(Math.random() * generalDescriptions.length);
    personalizedDescription = generalDescriptions[randomIndex];
  }
}
}

// ====================================================
// 🎯 إرجاع النتيجة مع معلومات التفضيلات
// ====================================================
if (!pickedTask) {
  throw new HttpsError("not-found", "NO_SUITABLE_TASK_FOUND");
}

return {
  id: pickedTask.id,
  taskId: pickedTask.id,
  title: pickedTask.title,
  description: personalizedDescription || pickedTask.description || "",
  originalDescription: pickedTask.description || "",
  points: pickedTask.points || 0,
  validationStrategy: pickedTask.validationStrategy || pickedTask.validation || "غير محددة",
  category: pickedTask.category || "",
  calcMode: pickedTask.calcMode || "",
  ef_ref: pickedTask.ef_ref || pickedTask.emissionFactorRef || "",
  status: "pending",
  // معلومات إضافية عن التفضيلات والموقع
  suggestedBasedOnLocation: nearbyPlaces.length > 0 && 
    (pickedTask.category === "إعادة التدوير" || pickedTask.category === "recycling"),
  suggestedBasedOnPreference: topTaskIds.includes(pickedTask.id) || 
    (taskPreferencesData[pickedTask.id]?.score > 5) ||
    preferredCategories.includes(pickedTask.category),
  preferenceScore: taskPreferencesData[pickedTask.id]?.score || 1,
  completedCount: taskPreferencesData[pickedTask.id]?.completed || 0,
  ignoredCount: taskPreferencesData[pickedTask.id]?.ignored || 0,
  nearbyPlacesCount: nearbyPlaces.length,
  userLocationDetected: !!(userLocation || userLocationFromDb),
  preferencesLastUpdated: userTaskPrefs?.lastUpdated || null,
};});

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
    schedule: "0 23 * * *", // 11:00 pm كل يوم
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

    const tomorrow = DateTime.now()
      .setZone("Asia/Riyadh")
      .plus({ days: 1 })  // نضيف يوم واحد
      .toFormat("yyyy-LL-dd");
    
    
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
  
// المهام المكتملة مع عدد المرات
const completedTasksWithCount = [];
const taskCountMap = {};

const completedSnapshot = await db
  .collection("userTasks")
  .where("userId", "==", userId)
  .where("status", "==", "completed")
  .orderBy("completedAt", "desc")
  .limit(50)
  .get();

completedSnapshot.forEach((d) => {
  const taskId = d.data().taskId;
  const taskTitle = d.data().taskTitle;
  if (taskId && taskTitle) {
    taskCountMap[taskId] = taskCountMap[taskId] || { count: 0, title: taskTitle };
    taskCountMap[taskId].count++;
  }
});

Object.entries(taskCountMap).forEach(([taskId, data]) => {
  completedTasksWithCount.push({
    id: taskId,
    title: data.title,
    count: data.count
  });
});

// المهام المتجاهلة مع IDs
const ignoredTaskIds = [];
const ignoredSnapshot = await db
  .collection("userTasks")
  .where("userId", "==", userId)
  .where("ignored", "==", true)
  .orderBy("ignoredAt", "desc")
  .limit(20)
  .get();

ignoredSnapshot.forEach((d) => {
  const tid = d.data().taskId;
  if (tid) ignoredTaskIds.push(tid);
});

// مهمة الأمس كاملة
let yesterdayTask = null;
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

if (yesterdaySnapshot.docs.length > 0) {
  const data = yesterdaySnapshot.docs[0].data();
  yesterdayTask = {
    id: data.taskId,
    title: data.taskTitle,
    category: data.category
  };
}

  // ====================================================
  // 🤖 بناء الـ prompt البسيط
  // ====================================================
  // تحضير قائمة المهام مع IDs
const taskListWithIds = availableTasks
  .map((t, i) => `${i + 1}. [${t.id}] ${t.title} - ${t.category || 'عام'}`)
  .join('\n');

// تحضير قائمة المهام المفضلة مع عدد المرات
const favoriteTasksText = completedTasksWithCount
  .filter(t => t.count >= 2)
  .map(t => `   • ${t.title} (أكملها ${t.count} مرات)`)
  .join('\n');

// تحضير قائمة المهام المتجاهلة
const ignoredTasksText = ignoredTaskIds
  .map(id => {
    const task = availableTasks.find(t => t.id === id);
    return task ? `   • ${task.title}` : null;
  })
  .filter(Boolean)
  .join('\n');

const prompt = `
أنت مساعد بيئي ذكي متخصص في اختيار المهام اليومية. مهمتك: اختر مهمة واحدة فقط من القائمة تناسب هذا المستخدم.

📊 **تاريخ المستخدم التفصيلي:**

${favoriteTasksText ? `👍 المهام المفضلة (أكملها عدة مرات):\n${favoriteTasksText}` : '👍 لا توجد مهام مفضلة واضحة'}

${ignoredTasksText ? `👎 المهام المتجاهلة سابقاً (تجنبها تماماً):\n${ignoredTasksText}` : ''}

${yesterdayTask ? `📅 مهمة الأمس: ${yesterdayTask.title}` : '📅 لا توجد مهمة للأمس'}

📋 **المهام المتاحة اليوم:**
${taskListWithIds}

🎯 **قواعد الاختيار بدقة:**
1. **الأولوية القصوى**: اختر من المهام المفضلة (اللي أكملها عدة مرات) إن وجدت
2. **تجنب تماماً**: لا تختار أي مهمة من قائمة المتجاهلة
3. **تنويع**: إذا كانت مهمة الأمس من المفضلة، اختر مهمة مفضلة مختلفة
4. **التوازن**: إذا ما في مهام مفضلة، وزع الاختيار على التصنيفات المختلفة

⚠️ **تنبيهات مهمة:**
- إذا المستخدم عنده مهام مفضلة (أكملها ٣+ مرات)، اختر منها حتماً
- لا تكرر نفس المهمة كل يوم
- تجنب المهام المتجاهلة نهائياً

📝 **الوصف المخصص:**
اكتب وصفاً قصيراً ودافئاً (١٥-٢٠ كلمة) يكون:
- شخصي: استخدم "أنت"، "لك"، "معك"
- محفز: شجع المستخدم بكلمات لطيفة
- مرتبط بالمهمة المختارة

**أرجع JSON فقط بهذا الشكل:**
{
  "taskId": "معرف المهمة من القائمة (مثل [abc123])",
  "personalizedDescription": "وصف قصير ودافئ"
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
    }// ====================================================
// 📝 معالجة نتيجة Gemini (باستخدام taskId)
// ====================================================
if (geminiSuccess && geminiText) {
  console.log(`   📝 Response: ${geminiText}`);

  try {
    // تنظيف النص من markdown
    let cleanText = geminiText
      .replace(/```json/g, '')
      .replace(/```/g, '')
      .replace(/`/g, '')
      .trim();

    const firstBrace = cleanText.indexOf('{');
    const lastBrace = cleanText.lastIndexOf('}');
    
    if (firstBrace === -1 || lastBrace === -1) {
      throw new Error("No JSON object found");
    }

    const jsonString = cleanText.substring(firstBrace, lastBrace + 1);
    console.log(`   📦 Extracted JSON: ${jsonString}`);
    
    const parsed = JSON.parse(jsonString);

    // ✅ البحث باستخدام taskId
    if (parsed.taskId) {
      // تنظيف الـ ID من الأقواس إذا كانت موجودة
      let taskId = parsed.taskId.replace(/[\[\]']/g, '').trim();
      taskData = availableTasks.find(t => t.id === taskId);
      
      if (taskData) {
        personalizedDescription = parsed.personalizedDescription;
        console.log(`   ✅ Found task by ID: ${taskData.title}`);
      } else {
        console.log(`   ⚠️ Task ID not found: ${taskId}`);
      }
    }
    
    // Fallback للـ index إذا ما لقينا بالـ ID
    if (!taskData && parsed.index) {
      const index = parsed.index - 1;
      if (index >= 0 && index < availableTasks.length) {
        taskData = availableTasks[index];
        personalizedDescription = parsed.personalizedDescription;
        console.log(`   ✅ Found task by index: ${taskData.title}`);
      }
    }

  } catch (e) {
    console.log(`⚠️ Failed to parse Gemini JSON: ${e.message}`);
    console.log(`   Raw text: ${geminiText}`);
  }
}

// ====================================================
// 🧠 FALLBACK الذكي المحسّن (إذا فشلت كل محاولات Gemini)
// ====================================================
if (!taskData) {
  console.log("   ⚠️ All Gemini attempts failed or invalid response, using enhanced fallback...");
  
  if (availableTasks.length > 0) {
    // ابدأ بكل المهام المتاحة
    let suitableTasks = [...availableTasks];
    
    console.log(`   📊 Total tasks available: ${suitableTasks.length}`);
    console.log(`   📊 Ignored task IDs: ${ignoredTaskIds.length ? ignoredTaskIds.join(', ') : 'none'}`);
    console.log(`   📊 Preferred tasks: ${completedTasksWithCount.filter(t => t.count >= 2).map(t => t.title).join(', ') || 'none'}`);
    
    // ✅ الخطوة 1: استبعد المهام المتجاهلة باستخدام IDs (الأولوية القصوى)
    if (ignoredTaskIds.length > 0) {
      const beforeCount = suitableTasks.length;
      const withoutIgnored = suitableTasks.filter(t => !ignoredTaskIds.includes(t.id));
      if (withoutIgnored.length > 0) {
        suitableTasks = withoutIgnored;
        console.log(`   🚫 Excluded ${beforeCount - suitableTasks.length} ignored tasks by ID`);
      } else {
        console.log(`   ⚠️ All tasks would be excluded by ignored IDs, keeping originals`);
      }
    }
    
    // ✅ الخطوة 2: استبعد مهمة الأمس باستخدام ID (إذا كانت مختلفة)
    if (yesterdayTask?.id && suitableTasks.length > 1) {
      const beforeCount = suitableTasks.length;
      const withoutYesterday = suitableTasks.filter(t => t.id !== yesterdayTask.id);
      if (withoutYesterday.length > 0) {
        suitableTasks = withoutYesterday;
        console.log(`   🚫 Excluded yesterday's task: ${yesterdayTask.title} (${yesterdayTask.id})`);
      }
    }
    
    // ✅ الخطوة 3: جمع المهام المفضلة
    const preferredTaskIds = completedTasksWithCount
      .filter(t => t.count >= 2)
      .map(t => t.id);
    
    const preferredAvailable = suitableTasks.filter(t => preferredTaskIds.includes(t.id));
    console.log(`   ⭐ Preferred tasks available: ${preferredAvailable.length}`);
    
    // ✅ الخطوة 4: استخدم نظام الأوزان إذا كانت التفضيلات موجودة
    if (preferencesData && suitableTasks.length > 0) {
      console.log(`   📊 Using weighted preference system...`);
      
      // نعطي كل مهمة وزن بناءً على تفضيلات المستخدم
      const weightedTasks = suitableTasks.map(task => {
        let weight = 1.0; // الوزن الأساسي
        
        // 🎯 إذا كانت المهمة من المفضلة، وزنها عالي جداً
        if (preferredTaskIds.includes(task.id)) {
          weight += 5.0;
          console.log(`      ⭐ ${task.title} is preferred (+5)`);
        }
        
        // 📊 تفضيلات التصنيف من preferencesData
        const catPref = preferencesData[task.category];
        if (catPref) {
          // كل ما زادت المهام المكتملة، زاد الوزن
          if (catPref.completed > 0) {
            weight += catPref.completed * 0.5;
            console.log(`      📈 ${task.category} completed ${catPref.completed} times (+${catPref.completed * 0.5})`);
          }
          // كل ما زادت المهام المتجاهلة، قل الوزن
          if (catPref.ignored > 0) {
            weight -= catPref.ignored * 0.8;
            console.log(`      📉 ${task.category} ignored ${catPref.ignored} times (-${catPref.ignored * 0.8})`);
          }
        }
        
        // نضمن أن الوزن ما يقل عن 0.1
        weight = Math.max(0.1, weight);
        
        return { task, weight };
      });
      
      // نرتب حسب الوزن (الأعلى أولاً)
      weightedTasks.sort((a, b) => b.weight - a.weight);
      
      console.log(`   📊 Weighted tasks (top 3):`);
      weightedTasks.slice(0, 3).forEach((wt, i) => {
        console.log(`      ${i+1}. ${wt.task.title} (weight: ${wt.weight.toFixed(2)})`);
      });
      
      // اختيار عشوائي مع مراعاة الأوزان (الاختيار الموزون)
      const totalWeight = weightedTasks.reduce((sum, wt) => sum + wt.weight, 0);
      let random = Math.random() * totalWeight;
      let selectedTask = null;
      
      for (const wt of weightedTasks) {
        random -= wt.weight;
        if (random <= 0) {
          selectedTask = wt.task;
          console.log(`   ✅ Selected by weighted random: ${selectedTask.title} (weight: ${wt.weight.toFixed(2)})`);
          break;
        }
      }
      
      // إذا فشل الاختيار الموزون، نختار أعلى وزن
      if (!selectedTask && weightedTasks.length > 0) {
        selectedTask = weightedTasks[0].task;
        console.log(`   ✅ Selected top weighted task: ${selectedTask.title}`);
      }
      
      taskData = selectedTask;
    }
    
    // ✅ الخطوة 5: إذا ما زلنا ما اخترنا مهمة، نختار من المفضلة أولاً ثم عشوائياً
    if (!taskData) {
      if (preferredAvailable.length > 0) {
        // اختر من المفضلة أولاً
        taskData = preferredAvailable[Math.floor(Math.random() * preferredAvailable.length)];
        console.log(`   ✅ Selected from preferred tasks: ${taskData.title}`);
      } else if (suitableTasks.length > 0) {
        // اختر عشوائياً من المهام المتبقية
        const randomIndex = Math.floor(Math.random() * suitableTasks.length);
        taskData = suitableTasks[randomIndex];
        console.log(`   ✅ Random fallback selected: ${taskData.title} (${taskData.category})`);
      }
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
      .doc(tomorrow)  // ✅ نحفظ تحت تاريخ بكره
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
    schedule: "0 22 * * *", // 11:00 pm كل يوم
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
    schedule: "0 22 * * *", // 11:00 PM كل يوم
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
