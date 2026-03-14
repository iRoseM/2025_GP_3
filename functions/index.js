const functions = require("firebase-functions/v1");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2/options");
const admin = require("firebase-admin");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { defineString } = require("firebase-functions/params");
const { DateTime } = require("luxon");

admin.initializeApp();
const db = admin.firestore();

setGlobalOptions({
  region: "us-central1",
  maxInstances: 10,
});

// ✅ مفاتيح الـ params
const GEMINI_API_KEY = defineString("GEMINI_API_KEY");
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
 * ✅ suggestBonusTask → Callable Function
 * ============================================================ */
exports.suggestBonusTask = onCall(async (request) => {
  const auth = request.auth;
  if (!auth || !auth.uid) {
    throw new HttpsError("unauthenticated", "User not logged in");
  }

  const userId = auth.uid;
  const pressedAt = request.data?.pressedAt || new Date().toISOString();
  const userLocation = request.data?.userLocation || null;

  const apiKey = GEMINI_API_KEY.value();
  if (!apiKey) {
    throw new HttpsError("failed-precondition", "GEMINI_API_KEY_MISSING");
  }

  const pressedDate = new Date(pressedAt);
  const hour = pressedDate.getHours();

  // ⏰ تحضير سياق الوقت
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

  // 📍 تحضير سياق الموقع
  let locationContext = "";
  let nearbyPlaces = [];
  let userLocationFromDb = null;

  function calculateDistance(lat1, lon1, lat2, lon2) {
    const R = 6371;
    const dLat = deg2rad(lat2 - lat1);
    const dLon = deg2rad(lon2 - lon1);
    const a = 
      Math.sin(dLat/2) * Math.sin(dLat/2) +
      Math.cos(deg2rad(lat1)) * Math.cos(deg2rad(lat2)) * 
      Math.sin(dLon/2) * Math.sin(dLon/2); 
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a)); 
    const d = R * c;
    return d;
  }

  function deg2rad(deg) {
    return deg * (Math.PI/180);
  }

  try {
    let locationToUse = userLocation;
    
    if (!locationToUse) {
      const userDoc = await db.collection("users").doc(userId).get();
      const userData = userDoc.data();
      locationToUse = userData?.lastLocation;
      userLocationFromDb = locationToUse;
    }
    
    if (locationToUse) {
      console.log("📍 User location found:", locationToUse);
      
      const containersSnapshot = await db
        .collection("recyclingCenters")
        .where("type", "==", "container")
        .get();
      
      containersSnapshot.forEach((doc) => {
        const center = doc.data();
        if (center.location) {
          const distance = calculateDistance(
            locationToUse.latitude,
            locationToUse.longitude,
            center.location.latitude,
            center.location.longitude
          );
          
          if (distance <= 2) {
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
          
          if (distance <= 3) {
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
  const today = DateTime.now().setZone("Asia/Riyadh").toFormat("yyyyLLdd");
  const todayDocId = `${userId}_${today}`;

  let todayTaskId = null;
  try {
    const todaySnap = await db.collection("userTasks").doc(todayDocId).get();
    todayTaskId = todaySnap.data()?.taskId || null;
  } catch (e) {
    console.log("⚠️ Could not fetch today's task:", e.message);
  }

  // ✅ جلب تفضيلات المستخدم
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
      
      topTaskIds = userTaskPrefs.topTasks || [];
      taskPreferencesData = userTaskPrefs.taskPreferences || {};
      
      Object.entries(taskPreferencesData).forEach(([taskId, data]) => {
        taskScores[taskId] = data.score || 1;
      });
      
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
      
      Object.entries(categoryStats).forEach(([category, stats]) => {
        const avgScore = stats.totalScore / (stats.tasks.length || 1);
        if (avgScore > 3 && stats.completed > stats.ignored) {
          preferredCategories.push(category);
        }
      });
      
      console.log("   Top task:", userTaskPrefs.topTaskTitle);
      console.log("   Preferred categories:", preferredCategories);
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

**ممنوع نسخ الوصف الأصلي**. اكتب وصفاً جديداً كلياً:
- شخصي: خاطب المستخدم بلطف (أنت/لك/معك)
- عملي: اربطه بسياقه الحالي (الوقت/الموقع/الوصف الأصلي)
- محفز: استخدم كلمات تشجيعية ودودة
- قصير: ١٥-٢٠ كلمة فقط
- مختلف: لا يشبه الوصف الأصلي أبداً

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
          generationConfig: { temperature: 0.4, maxOutputTokens: 800 },
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
      // تنظيف النص من علامات Markdown
let clean = text.replace(/```json/g, "").replace(/```/g, "").replace(/`/g, "").trim();

// محاولة إصلاح JSON إذا كان فيه أخطاء
try {
  // البحث عن أول { وآخر }
  const first = clean.indexOf("{");
  const last = clean.lastIndexOf("}");
  
  if (first !== -1 && last !== -1 && last > first) {
    let jsonStr = clean.substring(first, last + 1);
    
    // محاولة إصلاح الأخطاء الشائعة في JSON
    jsonStr = jsonStr
      .replace(/,(\s*[}\]])/g, '$1') // إزالة الفواصل الزائدة قبل ] أو }
      .replace(/([{,]\s*)(\w+)(\s*:)/g, '$1"$2"$3'); // إضافة علامات اقتباس للمفاتيح
    
    try {
      const parsed = JSON.parse(jsonStr);
      aiRecommendations = parsed.recommendations || [];
      console.log(`✅ [Gemini API] - Generated ${aiRecommendations.length} recommendations`);
      geminiSuccess = true;
    } catch (e) {
      console.error("❌ [Gemini API] - JSON parse error after cleanup:", e.message);
      console.log("📝 Problematic JSON:", jsonStr.substring(0, 200) + "...");
    }
  } else {
    console.error("❌ [Gemini API] - No valid JSON object found");
  }
} catch (e) {
  console.error("❌ [Gemini API] - Error processing response:", e.message);
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
    
    const nonIgnoredTasks = availableTasks.filter(t => !ignoredTaskIds.includes(t.id));
    
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
    
    if (!pickedTask) {
      const highScoreTasks = nonIgnoredTasks.filter(t => (t.preferenceScore || 1) > 5);
      if (highScoreTasks.length > 0) {
        highScoreTasks.sort((a, b) => (b.preferenceScore || 1) - (a.preferenceScore || 1));
        pickedTask = highScoreTasks[0];
        console.log(`✅ Selected high score task: ${pickedTask.title} (score: ${pickedTask.preferenceScore})`);
      }
    }
    
    if (!pickedTask && preferredCategories.length > 0) {
      const categoryTasks = nonIgnoredTasks.filter(t => 
        preferredCategories.includes(t.category)
      );
      
      if (categoryTasks.length > 0) {
        categoryTasks.sort((a, b) => (b.preferenceScore || 1) - (a.preferenceScore || 1));
        pickedTask = categoryTasks[0];
        console.log(`✅ Selected from preferred categories: ${pickedTask.title}`);
      }
    }
    
    if (!pickedTask && completedTaskIds.length > 0) {
      const completedTasks = nonIgnoredTasks.filter(t => completedTaskIds.includes(t.id));
      if (completedTasks.length > 0) {
        completedTasks.sort((a, b) => (b.preferenceScore || 1) - (a.preferenceScore || 1));
        pickedTask = completedTasks[0];
        console.log(`✅ Selected from previously completed: ${pickedTask.title}`);
      }
    }
    
    if (!pickedTask && nonIgnoredTasks.length > 0) {
      nonIgnoredTasks.sort((a, b) => (b.preferenceScore || 1) - (a.preferenceScore || 1));
      pickedTask = nonIgnoredTasks[0];
      console.log(`✅ Selected top scored non-ignored task: ${pickedTask.title}`);
    }
    
    if (!pickedTask && availableTasks.length > 0) {
      pickedTask = availableTasks[0];
      console.log(`✅ Selected first available task: ${pickedTask.title}`);
    }
    
    if (!personalizedDescription && pickedTask) {
      const taskPref = taskPreferencesData[pickedTask.id];
      const recyclingCats = ["إعادة التدوير", "recycling"];
      const transportCats = ["وسائل النقل المستدامة", "النقل", "وسائل النقل"];
      const awarenessCats = ["التوعية والاستدامة", "الوعي"];
      const energyCats = ["الكهرباء", "الطاقة"];
      const waterCats = ["الماء", "ترشيد الماء"];
      
      if (nearbyPlaces.length > 0) {
        const nearest = nearbyPlaces[0];
        
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
            personalizedDescription = `🚏 محطة باص قريبة منك (${nearest.distance} كم)! فرصة ذهبية تجرب التنقل المستدام وتجمع نقاط إضافية ✨`;
          }
        }
        else if (nearest.name?.includes('طعام') || nearest.name?.includes('عضوي')) {
          if (recyclingCats.includes(pickedTask.category)) {
            if (nearest.distance < 0.5) {
              personalizedDescription = `🥗 حاوية طعام على بعد خطوات منك (${nearest.distance} كم)! بقايا غدائك تتحول لسماد يغذي الأرض، شارك في دورة الحياة الجميلة 🌱`;
            } else {
              personalizedDescription = `🍽️ حاوية طعام قريبة منك (${nearest.distance} كم)! لقمتك الباقية ممكن تتحول إلى سماد، لا ترميها ✨`;
            }
          }
        }
        else if (nearest.name?.toLowerCase().includes('rvm')) {
          if (recyclingCats.includes(pickedTask.category)) {
            if (nearest.distance < 0.5) {
              personalizedDescription = `💰 RVM قريب جداً منك! كل زجاجة بتدويرها تعني ريال في محفظتك ونقاط في رصيدك، مكسب مزدوج ✨`;
            } else {
              personalizedDescription = `🔄 آلة RVM على بعد ${nearest.distance} كم! كل قارورة تدخلها تزيد رصيدك ريال، جرب تجمع اللي عندك ♻️`;
            }
          }
        }
        else if (recyclingCats.includes(pickedTask.category)) {
          if (nearest.distance < 0.3) {
            personalizedDescription = `♻️ حاوية تدوير قريبة جداً (${nearest.distance} كم)! حتى العلبة الوحيدة تصنع فرق، جرب تمشي لها الحين 🌍`;
          } else {
            personalizedDescription = `🌍 حاوية تدوير على بعد ${nearest.distance} كم منك! البلاستيك والورق اللي عندك ممكن يبدأ حياة جديدة، شارك ♻️`;
          }
        }
      }
      
      else {
        if (hour >= 5 && hour < 9) {
          if (transportCats.includes(pickedTask.category)) {
            personalizedDescription = `🌅 الصباح المنعش يدعوك للمشي أو ركوب الباص! جرب تستغل محطة الباص القريبة وتنقل بشكل مستدام ✨`;
          } else if (recyclingCats.includes(pickedTask.category)) {
            personalizedDescription = `☀️ بداية يومك بوعي! جرب تفرز المخلفات اللي عندك، خطوة بسيطة وأثرها كبير على بيئتك 🌱`;
          } else {
            personalizedDescription = `🌅 صباح الخير! ${pickedTask.title} ممكن تكون أجمل بداية ليومك، جربها ☕`;
          }
        }
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
        else if (hour >= 16 && hour < 20) {
          if (recyclingCats.includes(pickedTask.category)) {
            personalizedDescription = `🌆 المساء وقت مناسب لترتيب المخلفات! جرب تفرز البلاستيك والورق اليوم ♻️`;
          } else if (transportCats.includes(pickedTask.category)) {
            personalizedDescription = `🚶‍♀️ الجو بدأ يلطف! جرب تمشي لأقرب محطة باص وتنقل مستدام، صحتك والبيئة تستاهل 🌆`;
          } else {
            personalizedDescription = `🌇 مساء جميل لمهمة ${pickedTask.title}، دقيقتين بس وتأثيرها يدوم 💚`;
          }
        }
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
      
      if (!personalizedDescription && taskPref && taskPref.completed > 0) {
        if (taskPref.completed >= 5) {
          personalizedDescription = `🏆 أنت بطلة في ${pickedTask.title}! أكملتها ${taskPref.completed} مرات، استمري بنفس الروعة والبيئة بتشكرك 🌟`;
        } else {
          personalizedDescription = `⭐ واضح إنك تحب ${pickedTask.title}! أكملتها ${taskPref.completed} مرات، جربها مرة ثانية تضيف نقاطك ✨`;
        }
      }
      
      if (!personalizedDescription && preferredCategories.includes(pickedTask.category)) {
        personalizedDescription = `💚 ${pickedTask.category} من اهتماماتك! جرب هالمهمة الحلوة، راح تعجبك أكيد 🌱`;
      }
      
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
  };
});

/* ============================================================
 * 🔔 Immediate Trigger: "بكره" reminder
 * ============================================================ */
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

// ============================================================
// ✅ 1. دالة توليد المهام اليومية [v2]
// ============================================================
exports.generateDailyTasks = onSchedule(
  {
    schedule: "0 23 * * *",
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

    const tomorrow = DateTime.now()
      .setZone("Asia/Riyadh")
      .plus({ days: 1 })
      .toFormat("yyyy-LL-dd");

    const currentMonth = new Date().toISOString().slice(0, 7);
    console.log(`📦 Current month: ${currentMonth}`);

    const fallbackTasks = [
      { title: "وفر الطاقة", description: "افصل الأجهزة الكهربائية غير المستخدمة", category: "الكهرباء" },
      { title: "دور المخلفات", description: "افصل البلاستيك عن الورق", category: "التدوير" },
      { title: "امشي للجامعة", description: "امشي إذا كانت المسافة قريبة", category: "النقل" },
      { title: "وفر الماء", description: "أغلق الصنبور أثناء تنظيف الأسنان", category: "الماء" }
    ];

    let availableTasks = [];
    
    try {
      const activeTasksSnapshot = await db
        .collection("tasks")
        .where("status", "==", "active")
        .get();

      console.log(`📦 Found ${activeTasksSnapshot.size} active tasks`);

      if (activeTasksSnapshot.size > 0) {
        activeTasksSnapshot.forEach((doc) => {
          const task = doc.data();
          
          const visibleFrom = task.visible_from;
          if (visibleFrom && visibleFrom > currentMonth) {
            return;
          }
          
          const expiry = task.expiry_month;
          if (expiry && expiry < currentMonth) {
            return;
          }
          
          availableTasks.push({
            id: doc.id,
            ...task
          });
        });
      }
      
      if (availableTasks.length === 0) {
        console.log("⚠️ No tasks found, using fallback tasks");
        availableTasks = fallbackTasks;
      }

      console.log(`📦 Available tasks: ${availableTasks.length}`);
      
    } catch (e) {
      console.error(`❌ Error fetching tasks:`, e.message);
      console.log("⚠️ Using fallback tasks due to error");
      availableTasks = fallbackTasks;
    }

    let tasksCreated = 0;
    
    for (const doc of usersSnapshot.docs) {
      const userId = doc.id;
      const user = doc.data();
      let personalizedDescription = null;
      let userPrefs = null;
      let preferredCategory = null;
      let preferencesData = null;
      let availableCategories = [];
      
      let userTaskPrefs = null;
      let topTaskIds = [];
      let taskPreferencesData = null;

      try {
        const prefsDoc = await db.collection("userTaskPreferences").doc(userId).get();
        if (prefsDoc.exists) {
          userTaskPrefs = prefsDoc.data();
          topTaskIds = userTaskPrefs.topTasks || [];
          taskPreferencesData = userTaskPrefs.taskPreferences;
          
          console.log(`   📊 User task preferences loaded...`);
        }
      } catch (e) {
        console.log(`   ⚠️ Could not load preferences:`, e.message);
      }

      const userProfile = {
        level: user.userLevelId || "beginner",
        points: user.points || 0,
        topTaskId: userTaskPrefs?.topTaskId || null,
      };
      
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

      const taskListWithIds = availableTasks
        .map((t, i) => `${i + 1}. [${t.id}] ${t.title} - ${t.category || 'عام'}`)
        .join('\n');

      const favoriteTasksText = completedTasksWithCount
        .filter(t => t.count >= 2)
        .map(t => `   • ${t.title} (أكملها ${t.count} مرات)`)
        .join('\n');

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
        
        let geminiText = null;
        let geminiSuccess = false;
        let taskData = null;
        
        for (let attempt = 1; attempt <= 3; attempt++) {
          console.log(`   🔄 Gemini attempt ${attempt}/3...`);
          // استخدم أحد هذه النماذج المتاحة والمستقرة:
// const modelName = "gemini-1.5-pro";
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
                  maxOutputTokens: 500            },
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

            const result = await response.json();
            const text = result?.candidates?.[0]?.content?.parts?.[0]?.text;
            
            if (text && text.trim().length > 0) {
              geminiText = text;
              geminiSuccess = true;
              console.log(`   ✅ Gemini success on attempt ${attempt}`);
              break;
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

        if (geminiSuccess && geminiText) {
          console.log(`   📝 Response: ${geminiText}`);

          try {
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

            if (parsed.taskId) {
              let taskId = parsed.taskId.replace(/[\[\]']/g, '').trim();
              taskData = availableTasks.find(t => t.id === taskId);
              
              if (taskData) {
                personalizedDescription = parsed.personalizedDescription;
                console.log(`   ✅ Found task by ID: ${taskData.title}`);
              } else {
                console.log(`   ⚠️ Task ID not found: ${taskId}`);
              }
            }
            
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

        if (!taskData) {
          console.log("   ⚠️ All Gemini attempts failed or invalid response, using enhanced fallback...");
          
          if (availableTasks.length > 0) {
            let suitableTasks = [...availableTasks];
            
            console.log(`   📊 Total tasks available: ${suitableTasks.length}`);
            
            if (ignoredTaskIds.length > 0) {
              const beforeCount = suitableTasks.length;
              const withoutIgnored = suitableTasks.filter(t => !ignoredTaskIds.includes(t.id));
              if (withoutIgnored.length > 0) {
                suitableTasks = withoutIgnored;
                console.log(`   🚫 Excluded ${beforeCount - suitableTasks.length} ignored tasks by ID`);
              }
            }
            
            if (yesterdayTask?.id && suitableTasks.length > 1) {
              const beforeCount = suitableTasks.length;
              const withoutYesterday = suitableTasks.filter(t => t.id !== yesterdayTask.id);
              if (withoutYesterday.length > 0) {
                suitableTasks = withoutYesterday;
                console.log(`   🚫 Excluded yesterday's task: ${yesterdayTask.title} (${yesterdayTask.id})`);
              }
            }
            
            const preferredTaskIds = completedTasksWithCount
              .filter(t => t.count >= 2)
              .map(t => t.id);
            
            const preferredAvailable = suitableTasks.filter(t => preferredTaskIds.includes(t.id));
            console.log(`   ⭐ Preferred tasks available: ${preferredAvailable.length}`);
            
            if (preferencesData && suitableTasks.length > 0) {
              console.log(`   📊 Using weighted preference system...`);
              
              const weightedTasks = suitableTasks.map(task => {
                let weight = 1.0;
                
                if (preferredTaskIds.includes(task.id)) {
                  weight += 5.0;
                  console.log(`      ⭐ ${task.title} is preferred (+5)`);
                }
                
                const catPref = preferencesData[task.category];
                if (catPref) {
                  if (catPref.completed > 0) {
                    weight += catPref.completed * 0.5;
                    console.log(`      📈 ${task.category} completed ${catPref.completed} times (+${catPref.completed * 0.5})`);
                  }
                  if (catPref.ignored > 0) {
                    weight -= catPref.ignored * 0.8;
                    console.log(`      📉 ${task.category} ignored ${catPref.ignored} times (-${catPref.ignored * 0.8})`);
                  }
                }
                
                weight = Math.max(0.1, weight);
                
                return { task, weight };
              });
              
              weightedTasks.sort((a, b) => b.weight - a.weight);
              
              console.log(`   📊 Weighted tasks (top 3):`);
              weightedTasks.slice(0, 3).forEach((wt, i) => {
                console.log(`      ${i+1}. ${wt.task.title} (weight: ${wt.weight.toFixed(2)})`);
              });
              
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
              
              if (!selectedTask && weightedTasks.length > 0) {
                selectedTask = weightedTasks[0].task;
                console.log(`   ✅ Selected top weighted task: ${selectedTask.title}`);
              }
              
              taskData = selectedTask;
            }
            
            if (!taskData) {
              if (preferredAvailable.length > 0) {
                taskData = preferredAvailable[Math.floor(Math.random() * preferredAvailable.length)];
                console.log(`   ✅ Selected from preferred tasks: ${taskData.title}`);
              } else if (suitableTasks.length > 0) {
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

        if (taskData) {
          const task = {
            ...taskData,
            description: personalizedDescription || taskData.description,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            status: "pending",
          };

          await db
            .collection("dailyTasks")
            .doc(userId)
            .collection("tasks")
            .doc(tomorrow)
            .set(task);

          console.log(`✅ AI Task created for: ${userId} | ${task.title}`);
          tasksCreated++;
        } else {
          console.log(`❌ No task could be created for ${userId}`);
        }
        
      } catch (error) {
        console.error("❌ AI generation failed for:", userId, error);
        
        if (availableTasks.length > 0) {
          try {
            const randomIndex = Math.floor(Math.random() * availableTasks.length);
            const taskData = availableTasks[randomIndex];
            const task = {
              ...taskData,
              description: personalizedDescription || taskData.description,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
              status: "pending",
            };

            await db
              .collection("dailyTasks")
              .doc(userId)
              .collection("tasks")
              .doc(tomorrow)
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
    schedule: "0 22 * * *",
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
// ✅ 3. دالة تحديث تفضيلات المستخدم
// ============================================================
exports.updateUserPreferences = onSchedule(
  {
    schedule: "0 22 * * *",
    timeZone: "Asia/Riyadh",
  },
  async () => {
    console.log("⏰ بدأ تحديث تفضيلات المستخدمين (على مستوى المهام)...");
    
    try {
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
        
        const thirtyDaysAgo = new Date();
        thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
        const thirtyDaysAgoTimestamp = admin.firestore.Timestamp.fromDate(thirtyDaysAgo);
        
        const submissionsSnapshot = await db
          .collection("submissions")
          .where("userId", "==", userId)
          .where("status", "==", "approved")
          .where("createdAt", ">=", thirtyDaysAgoTimestamp)
          .get();
        
        console.log(`   📊 Approved submissions (last 30d): ${submissionsSnapshot.size}`);
        
        const completedTasksSnapshot = await db
          .collection("userTasks")
          .where("userId", "==", userId)
          .where("status", "==", "completed")
          .where("completedAt", ">=", thirtyDaysAgoTimestamp)
          .get();
        
        console.log(`   📊 Completed userTasks (last 30d): ${completedTasksSnapshot.size}`);
        
        const ignoredTasksSnapshot = await db
          .collection("userTasks")
          .where("userId", "==", userId)
          .where("ignored", "==", true)
          .where("ignoredAt", ">=", thirtyDaysAgoTimestamp)
          .get();
        
        console.log(`   📊 Ignored tasks (last 30d): ${ignoredTasksSnapshot.size}`);
        
        const taskPreferences = {};
        
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
        
        submissionsSnapshot.docs.forEach((doc) => {
          const sub = doc.data();
          const taskId = sub.taskId;
          
          if (taskPreferences[taskId]) {
            taskPreferences[taskId].completed++;
            taskPreferences[taskId].lastCompletedAt = sub.createdAt;
          }
        });
        
        completedTasksSnapshot.docs.forEach((doc) => {
          const task = doc.data();
          const taskId = task.taskId;
          
          if (taskPreferences[taskId]) {
            taskPreferences[taskId].completed++;
            taskPreferences[taskId].lastCompletedAt = task.completedAt;
          }
        });
        
        ignoredTasksSnapshot.docs.forEach((doc) => {
          const task = doc.data();
          const taskId = task.taskId;
          
          if (taskPreferences[taskId]) {
            taskPreferences[taskId].ignored++;
            taskPreferences[taskId].lastIgnoredAt = task.ignoredAt;
          }
        });
        
        const taskScores = {};
        let topTaskId = null;
        let topScore = -100;
        
        for (const taskId in taskPreferences) {
          const stats = taskPreferences[taskId];
          
          let score = 1.0;
          score += stats.completed * 2;
          score -= stats.ignored * 3;
          
          if (stats.lastCompletedAt) {
            const daysSinceLastComplete = (Date.now() - stats.lastCompletedAt.toDate()) / (1000 * 60 * 60 * 24);
            if (daysSinceLastComplete < 7) {
              score -= 2;
            }
          }
          
          if (stats.lastIgnoredAt) {
            const daysSinceLastIgnored = (Date.now() - stats.lastIgnoredAt.toDate()) / (1000 * 60 * 60 * 24);
            if (daysSinceLastIgnored < 14) {
              score -= 5;
            }
          }
          
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
        
        const sortedTasks = Object.values(taskScores)
          .sort((a, b) => b.score - a.score)
          .slice(0, 5);
        
        console.log(`   🏆 Top task: ${sortedTasks[0]?.title} (score: ${sortedTasks[0]?.score.toFixed(2)})`);
        
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
/* ============================================================
 * 📊 getAdminRecommendations → Callable Function
 * توصيات ديناميكية بالكامل باستخدام AI
 * ============================================================ */

// دالة تحويل التاريخ الميلادي لهجري
function getHijriDate(date) {
  const formatter = new Intl.DateTimeFormat('ar-SA-u-ca-islamic', {
    day: 'numeric',
    month: 'numeric',
    year: 'numeric',
    timeZone: 'Asia/Riyadh'
  });
  
  const parts = formatter.formatToParts(date);
  let year = '', month = '', day = '';
  
  parts.forEach(part => {
    if (part.type === 'year') year = part.value;
    if (part.type === 'month') month = part.value;
    if (part.type === 'day') day = part.value;
  });
  
  return {
    year: parseInt(year),
    month: parseInt(month),
    day: parseInt(day),
    monthName: getHijriMonthName(parseInt(month))
  };
}

function getHijriMonthName(month) {
  const months = [
    'محرم', 'صفر', 'ربيع الأول', 'ربيع الآخر', 
    'جمادى الأولى', 'جمادى الآخرة', 'رجب', 'شعبان', 
    'رمضان', 'شوال', 'ذو القعدة', 'ذو الحجة'
  ];
  return months[month - 1] || '';
}

// دالة لجلب جميع التصنيفات من قاعدة البيانات
async function getAllCategories() {
  const categoriesSnapshot = await db
    .collection("categories")
    .where("status", "==", "active")
    .get();
  
  const categories = [];
  categoriesSnapshot.docs.forEach(doc => {
    const data = doc.data();
    categories.push({
      id: doc.id,
      name: data.name,
      parent: data.parent,
      description: data.description
    });
  });
  
  return categories;
}

// دالة للتحقق من وجود مهمة مكررة
async function isTaskDuplicate(title, daysBack = 90) {
  const normalizedTitle = title.trim().replace(/\s+/g, ' ').toLowerCase();
  
  const cutoffDate = new Date();
  cutoffDate.setDate(cutoffDate.getDate() - daysBack);
  
  const pastRecommendations = await db
    .collection("adminRecommendations")
    .where("generatedAt", ">=", cutoffDate)
    .get();
  
  for (const doc of pastRecommendations.docs) {
    const recs = doc.data().recommendations || [];
    for (const rec of recs) {
      const recTitle = (rec.title || '').trim().replace(/\s+/g, ' ').toLowerCase();
      
      if (recTitle.includes(normalizedTitle) || normalizedTitle.includes(recTitle)) {
        return true;
      }
      
      const words = normalizedTitle.split(' ');
      const recWords = recTitle.split(' ');
      const commonWords = words.filter(w => recWords.includes(w) && w.length > 2);
      
      if (commonWords.length >= 2) {
        return true;
      }
    }
  }
  
  return false;
}

// دالة لجلب تحليلات متقدمة عن أداء المهام
async function getTaskAnalytics() {
  const thirtyDaysAgo = new Date();
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
  
  const submissions = await db
    .collection("submissions")
    .where("createdAt", ">=", thirtyDaysAgo)
    .get();
  
  const taskStats = {};
  const categoryStats = {};
  
  submissions.docs.forEach(doc => {
    const data = doc.data();
    const taskId = data.taskId;
    const category = data.category || 'غير مصنف';
    
    if (!taskStats[taskId]) {
      taskStats[taskId] = {
        count: 0,
        totalPoints: 0,
        category: category
      };
    }
    taskStats[taskId].count++;
    taskStats[taskId].totalPoints += data.taskPoints || 0;
    
    if (!categoryStats[category]) {
      categoryStats[category] = { completed: 0, points: 0 };
    }
    categoryStats[category].completed++;
    categoryStats[category].points += data.taskPoints || 0;
  });
  
  return { taskStats, categoryStats };
}

// دالة لجلب المهام الأكثر تجاهلاً
async function getMostIgnoredTasks(limit = 10) {
  const thirtyDaysAgo = new Date();
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
  
  const ignoredTasks = await db
    .collection("userTasks")
    .where("ignored", "==", true)
    .where("ignoredAt", ">=", thirtyDaysAgo)
    .get();
  
  const ignoreCount = {};
  
  ignoredTasks.docs.forEach(doc => {
    const taskId = doc.data().taskId;
    ignoreCount[taskId] = (ignoreCount[taskId] || 0) + 1;
  });
  
  const ignoredTasksWithDetails = [];
  for (const [taskId, count] of Object.entries(ignoreCount).sort((a, b) => b[1] - a[1]).slice(0, limit)) {
    const taskDoc = await db.collection("tasks").doc(taskId).get();
    if (taskDoc.exists) {
      const taskData = taskDoc.data();
      ignoredTasksWithDetails.push({
        id: taskId,
        title: taskData.title || 'مهمة غير معروفة',
        category: taskData.category || 'غير مصنف',
        description: taskData.description || '',
        validationStrategy: taskData.validationStrategy || 'غير محدد',
        points: taskData.points || 0,
        ignoreCount: count,
        completionRate: taskData.completionRate || 0
      });
    }
  }
  
  return ignoredTasksWithDetails;
}

// دالة لجلب المهام الأكثر نجاحاً
async function getMostSuccessfulTasks(limit = 10) {
  const thirtyDaysAgo = new Date();
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
  
  const completedTasks = await db
    .collection("submissions")
    .where("createdAt", ">=", thirtyDaysAgo)
    .get();
  
  const successCount = {};
  
  completedTasks.docs.forEach(doc => {
    const taskId = doc.data().taskId;
    successCount[taskId] = (successCount[taskId] || 0) + 1;
  });
  
  const successfulTasksWithDetails = [];
  for (const [taskId, count] of Object.entries(successCount).sort((a, b) => b[1] - a[1]).slice(0, limit)) {
    const taskDoc = await db.collection("tasks").doc(taskId).get();
    if (taskDoc.exists) {
      const taskData = taskDoc.data();
      successfulTasksWithDetails.push({
        id: taskId,
        title: taskData.title || 'مهمة غير معروفة',
        category: taskData.category || 'غير مصنف',
        description: taskData.description || '',
        successCount: count
      });
    }
  }
  
  return successfulTasksWithDetails;
}

// دالة لجلب المهام ذات الأداء المنخفض جداً (صفر إنجازات)
async function getZeroCompletionTasks() {
  const thirtyDaysAgo = new Date();
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
  
  const activeTasks = await db
    .collection("tasks")
    .where("status", "==", "active")
    .get();
  
  const completedTasks = await db
    .collection("submissions")
    .where("createdAt", ">=", thirtyDaysAgo)
    .get();
  
  const completedTaskIds = new Set();
  completedTasks.docs.forEach(doc => {
    completedTaskIds.add(doc.data().taskId);
  });
  
  const zeroCompletionTasks = [];
  for (const doc of activeTasks.docs) {
    const taskId = doc.id;
    if (!completedTaskIds.has(taskId)) {
      const taskData = doc.data();
      zeroCompletionTasks.push({
        id: taskId,
        title: taskData.title || 'مهمة غير معروفة',
        category: taskData.category || 'غير مصنف',
        description: taskData.description || '',
        points: taskData.points || 0
      });
    }
  }
  
  return zeroCompletionTasks;
}

// دالة لجلب البلاغات المتكررة مع التفاصيل الكاملة
async function getProblematicReports(minReports = 5) {
  const pendingTaskReports = await db
    .collection("taskReports")
    .where("decision", "==", "pending")
    .get();

  const pendingContainerReports = await db
    .collection("facilityReports")
    .where("status", "==", "pending")
    .get();

  const taskReportIssues = {};
  pendingTaskReports.docs.forEach(doc => {
    const data = doc.data();
    const taskId = data.taskId;
    if (taskId) {
      if (!taskReportIssues[taskId]) {
        taskReportIssues[taskId] = {
          count: 0,
          reasons: [],
          reports: []
        };
      }
      taskReportIssues[taskId].count++;
      if (data.reason) {
        taskReportIssues[taskId].reasons.push(data.reason);
      }
      taskReportIssues[taskId].reports.push({
        id: doc.id,
        reason: data.reason,
        createdAt: data.createdAt
      });
    }
  });

  const problematicTasks = [];
  for (const [taskId, data] of Object.entries(taskReportIssues)) {
    if (data.count >= minReports) {
      const taskDoc = await db.collection("tasks").doc(taskId).get();
      if (taskDoc.exists) {
        const taskData = taskDoc.data();
        problematicTasks.push({
          type: 'task',
          id: taskId,
          title: taskData.title || 'مهمة غير معروفة',
          category: taskData.category || 'غير مصنف',
          reportCount: data.count,
          reasons: [...new Set(data.reasons)].slice(0, 3),
          reports: data.reports.slice(0, 5)
        });
      }
    }
  }

  const containerIssues = {};
  pendingContainerReports.docs.forEach(doc => {
    const data = doc.data();
    const facilityId = data.facilityID;
    if (facilityId) {
      if (!containerIssues[facilityId]) {
        containerIssues[facilityId] = {
          count: 0,
          types: [],
          reports: []
        };
      }
      containerIssues[facilityId].count++;
      if (data.type) {
        containerIssues[facilityId].types.push(data.type);
      }
      containerIssues[facilityId].reports.push({
        id: doc.id,
        type: data.type,
        description: data.description,
        createdAt: data.createdAt
      });
    }
  });

  const problematicContainers = [];
  for (const [facilityId, data] of Object.entries(containerIssues)) {
    if (data.count >= minReports) {
      const facilityDoc = await db.collection("facilities").doc(facilityId).get();
      if (facilityDoc.exists) {
        const facilityData = facilityDoc.data();
        problematicContainers.push({
          type: 'container',
          id: facilityId,
          name: facilityData.name || facilityData.type || 'حاوية غير معروفة',
          address: facilityData.address || 'عنوان غير معروف',
          location: facilityData.location || 'موقع غير معروف',
          reportCount: data.count,
          types: [...new Set(data.types)].slice(0, 3),
          reports: data.reports.slice(0, 5)
        });
      }
    }
  }

  return { problematicTasks, problematicContainers };
}

// الدالة الرئيسية
/* ============================================================
 * 📊 getAdminRecommendations → Callable Function
 * توصيات ديناميكية بالكامل باستخدام AI
 * ============================================================ */
exports.getAdminRecommendations = onCall(async (request) => {
  const auth = request.auth;
    if (request.httpMethod && request.httpMethod !== 'POST') {
    console.log(`🚫 Rejected ${request.httpMethod} request`);
    throw new HttpsError('failed-precondition', 'Method not allowed. Use POST.');
  }
  if (!auth || !auth.uid) {
    throw new HttpsError("unauthenticated", "User not logged in");
  }

  const userDoc = await db.collection("users").doc(auth.uid).get();
  if (userDoc.data()?.role !== "admin") {
    throw new HttpsError("permission-denied", "Admin access required");
  }

  const apiKey = GEMINI_API_KEY.value();
  if (!apiKey) {
    throw new HttpsError("failed-precondition", "GEMINI_API_KEY_MISSING");
  }

  // ✅ Rate Limiting
  const lastCallKey = `lastGeminiCall_${auth.uid}`;
  const lastCall = await db.collection("adminSettings").doc(lastCallKey).get();
  const now = Date.now();

  if (lastCall.exists) {
    const lastCallTime = lastCall.data().timestamp;
    if (now - lastCallTime < 60000) { // دقيقة واحدة
      console.log("⚠️ Rate limit: using cached recommendations");
      const lastMonth = new Date().toISOString().slice(0, 7);
      const lastRecs = await db.collection("adminRecommendations").doc(lastMonth).get();
      if (lastRecs.exists) {
        console.log("✅ Returning cached recommendations");
        return lastRecs.data();
      }
    }
  }

  // سجل وقت الاستدعاء
  await db.collection("adminSettings").doc(lastCallKey).set({
    timestamp: now,
    uid: auth.uid
  });

  try {
    const now = new Date();
    const currentMonth = now.toISOString().slice(0, 7);

    // ====================================================
    // 📊 جمع كل البيانات اللازمة للتحليل
    // ====================================================
    
    const pendingTaskReports = await db
      .collection("taskReports")
      .where("decision", "==", "pending")
      .get();

    const pendingContainerReports = await db
      .collection("facilityReports")
      .where("status", "==", "pending")
      .get();

    const activeTasks = await db
      .collection("tasks")
      .where("status", "==", "active")
      .get();

    // جلب التصنيفات من قاعدة البيانات
    const allCategories = await getAllCategories();
    const categoryNames = allCategories.map(c => c.name);

    const analytics = await getTaskAnalytics();
    const mostIgnored = await getMostIgnoredTasks(5);
    const mostSuccessful = await getMostSuccessfulTasks(5);
    const zeroCompletionTasks = await getZeroCompletionTasks();
    const { problematicTasks, problematicContainers } = await getProblematicReports(5);

    const ignoredTasksWithDetails = [];
    for (const ignored of mostIgnored) {
      ignoredTasksWithDetails.push({
        id: ignored.id,
        title: ignored.title,
        category: ignored.category,
        ignoreCount: ignored.ignoreCount
      });
    }

    const successfulTasksWithDetails = [];
    for (const success of mostSuccessful) {
      successfulTasksWithDetails.push({
        id: success.id,
        title: success.title,
        category: success.category,
        successCount: success.successCount
      });
    }

    const reportIssues = problematicTasks;

    const today = DateTime.now().setZone("Asia/Riyadh");
    
    function getSeason(today) {
      const hijriDate = getHijriDate(today.toJSDate());
      const hijriMonth = hijriDate.month;
      const hijriDay = hijriDate.day;
      
      if ((hijriMonth === 9 && hijriDay >= 1) || (hijriMonth === 10 && hijriDay <= 5)) {
        return { 
          season: "رمضان", 
          hijriMonth: hijriDate.monthName,
          description: "شهر رمضان المبارك"
        };
      }
      if (hijriMonth === 10 && hijriDay >= 1 && hijriDay <= 7) {
        return { 
          season: "شوال", 
          event: "عيد الفطر",
          hijriMonth: hijriDate.monthName
        };
      }
      if (hijriMonth === 12 && hijriDay >= 8 && hijriDay <= 15) {
        return { 
          season: "ذو الحجة", 
          event: "عيد الأضحى",
          hijriMonth: hijriDate.monthName
        };
      }
      
      const month = today.month;
      if (month >= 3 && month <= 5) return { season: "الربيع" };
      if (month >= 6 && month <= 8) return { season: "الصيف" };
      if (month >= 9 && month <= 11) return { season: "الخريف" };
      return { season: "الشتاء" };
    }
    
    const season = getSeason(today);

    // بناء قائمة التصنيفات المتاحة
    const availableCategories = categoryNames.length > 0 
      ? categoryNames.join('، ')
      : 'النقل المستدام، إعادة التدوير، تدوير الطعام، المشي، النقل العام';

    // ====================================================
    // 🤖 بناء الـ Prompt الديناميكي للـ AI
    // ====================================================
    const prompt = `
أنت مستشار متخصص في مجال **النقل المستدام وإعادة التدوير**. بناءً على البيانات التالية، قدم 5 توصيات متنوعة للإدمن تشمل:
- إضافة مهام جديدة (add)
- تعديل مهام حالية (modify)
- حذف مهام ضعيفة (delete)
- مراجعة بلاغات (review_reports)

📊 **البيانات الحالية:**

1. **الموسم الحالي:** ${season.season} ${season.event || ''} ${season.hijriMonth || ''}

2. **إحصائيات البلاغات:**
   - بلاغات مهام معلقة: ${pendingTaskReports.size}
   - بلاغات حاويات معلقة: ${pendingContainerReports.size}
   ${problematicTasks.length > 0 ? '- مهام بها بلاغات متكررة:\n' + problematicTasks.map(t => `     * ${t.title}: ${t.reportCount} بلاغ - الأسباب: ${t.reasons.join('، ')}`).join('\n') : ''}
   ${problematicContainers.length > 0 ? '- حاويات بها بلاغات متكررة:\n' + problematicContainers.map(c => `     * ${c.name} (${c.address}): ${c.reportCount} بلاغ`).join('\n') : ''}

3. **أداء المهام (آخر 30 يوم):**
   - إجمالي المهام النشطة: ${activeTasks.size}
   - مهام بدون إنجازات: ${zeroCompletionTasks.length}
   ${zeroCompletionTasks.slice(0, 5).map(t => `   * ${t.title}`).join('\n')}
   
   **المهام الأكثر تجاهلاً:**
   ${ignoredTasksWithDetails.map(t => `   * ${t.title} (تم تجاهلها ${t.ignoreCount} مرة)`).join('\n') || '   لا توجد بيانات كافية'}
   
   **المهام الأكثر نجاحاً:**
   ${successfulTasksWithDetails.map(t => `   * ${t.title} (تم إنجازها ${t.successCount} مرة)`).join('\n') || '   لا توجد بيانات كافية'}

4. **التصنيفات المتاحة:**
   ${availableCategories}

⚠️ **تعليمات مهمة جداً:**

1. **للمهام التي ليس لها إنجازات** - اقترح حذفها (delete) مع ذكر اسم المهمة
2. **للمهام الأكثر تجاهلاً** - اقترح تعديلها (modify) مع ذكر اسم المهمة
3. **للمهام ذات البلاغات المتكررة** - اقترح مراجعتها (review_reports) مع ذكر اسم المهمة
4. **للحاويات ذات البلاغات المتكررة** - اقترح مراجعتها (review_reports) مع ذكر اسم الحاوية والعنوان
5. **للموسم الحالي** - اقترح مهام جديدة مناسبة (add)

6. **صياغة دقيقة**: 
   - ✅ **صحيح**: "أضف مهمة: تدوير البلاستيك - التحقق عبر الصور" (لا تذكر الوقت)
   - ✅ **صحيح**: "مهمة 'فرز الورق' لم يحققها أحد - يُقترح حذفها"
   - ✅ **صحيح**: "حاوية الملز (حي الملز) - 7 بلاغات معلقة"
   - ❌ **خطأ**: "امشِ لمدة 15 دقيقة" (لا يوجد تحقق بالوقت)
   - ❌ **خطأ**: "استخدم الباص لمدة ساعة" (لا يوجد تحقق بالوقت)

7. **التصنيفات**: استخدم التصنيفات الموجودة في القائمة أعلاه فقط

أرجع JSON فقط بهذا الهيكل:
{
  "recommendations": [
    {
      "type": "add/modify/delete/review_reports",
      "category": "اسم التصنيف من القائمة أعلاه",
      "title": "عنوان التوصية",
      "description": "شرح مفصل للمشكلة أو الفرصة (موجه للإدمن)",
      "userDescription": "وصف المهمة للمستخدم النهائي فقط إذا type=add",
      "suggestion": "الاقتراح العملي (موجه للإدمن)",
      "basedOn": "السبب (تحليل البيانات)",
      "validationStrategy": "التحقق عبر معالجة الصور أو التحقق عبر اجراء اختبار قصير",
      "calcMode": "deltaPerItem",
      "askCount": true,
      "askDistanceKm": false,
      "autoDistance": false,
      "reportCount": 0,
      "taskId": "معرف المهمة إذا موجود",
      "facilityId": "معرف الحاوية إذا موجود",
      "facilityName": "اسم الحاوية إذا موجود",
      "facilityAddress": "عنوان الحاوية إذا موجود"
    }
  ],
  "summary": {
    "totalTasks": ${activeTasks.size},
    "pendingReports": ${pendingTaskReports.size + pendingContainerReports.size},
    "zeroCompletionTasks": ${zeroCompletionTasks.length},
    "ignoredTasksCount": ${ignoredTasksWithDetails.length},
    "problematicTasks": ${problematicTasks.length},
    "problematicContainers": ${problematicContainers.length}
  }
}
`;

    console.log("🔵 [Gemini API] - إرسال الطلب إلى Gemini...");
    console.log("🔵 [Gemini API] - طول الـ Prompt:", prompt.length);
// استخدم أحد هذه النماذج المتاحة والمستقرة:
// const modelName = "gemini-1.5-pro"; 
   const modelName = "gemini-2.0-flash";
const url = `https://generativelanguage.googleapis.com/v1beta/models/${modelName}:generateContent?key=${apiKey}`;

    let aiRecommendations = [];
    let geminiSuccess = false;
    let retryCount = 0;
    const maxRetries = 3;

    while (!geminiSuccess && retryCount < maxRetries) {
      try {
        const response = await fetch(url, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            contents: [{ parts: [{ text: prompt }] }],
            generationConfig: { temperature: 0.8, maxOutputTokens: 2000 }
          })
        });

        console.log(`🔵 [Gemini API] - Attempt ${retryCount + 1} status:`, response.status);

        if (response.status === 429) {
          console.log(`⚠️ [Gemini API] - Rate limited (429), retry ${retryCount + 1}/${maxRetries}`);
          retryCount++;
          if (retryCount < maxRetries) {
            // انتظر 2 ثانية قبل إعادة المحاولة
            await new Promise(resolve => setTimeout(resolve, 2000));
            continue;
          } else {
            console.error("❌ [Gemini API] - Max retries reached, using fallback");
            break;
          }
        }

        if (!response.ok) {
          const errorText = await response.text();
          console.error("❌ Gemini Error:", errorText);
          break;
        }

        const result = await response.json();
        const text = result?.candidates?.[0]?.content?.parts?.[0]?.text || "";
        
        console.log("✅ [Gemini API] - Received response from Gemini");
        
        const clean = text.replace(/```json/g, "").replace(/```/g, "").trim();
        const first = clean.indexOf("{");
        const last = clean.lastIndexOf("}");
        
        if (first !== -1 && last !== -1) {
          try {
            const parsed = JSON.parse(clean.substring(first, last + 1));
            aiRecommendations = parsed.recommendations || [];
            console.log(`✅ [Gemini API] - Generated ${aiRecommendations.length} recommendations`);
            geminiSuccess = true;
          } catch (e) {
            console.error("❌ [Gemini API] - JSON parse error:", e.message);
          }
        } else {
          console.error("❌ [Gemini API] - No valid JSON found in response");
        }
        
      } catch (e) {
        console.error("❌ [Gemini API] - Fetch error:", e.message);
        retryCount++;
        if (retryCount < maxRetries) {
          console.log(`⚠️ [Gemini API] - Retrying in 2 seconds...`);
          await new Promise(resolve => setTimeout(resolve, 2000));
        }
      }
    }

    // ====================================================
    // 🔴 توصيات الحذف الديناميكية (للمهام الضعيفة)
    // ====================================================

    // 1. المهام اللي معندهاش أي إنجازات خالص (صفر)
    const zeroCompletionTasksList = zeroCompletionTasks;

    // 2. المهام ذات الأداء الضعيف (أقل من 3 إنجازات + تجاهل عالي)
// 2. المهام ذات الأداء الضعيف (أقل من 3 إنجازات + تجاهل عالي)
const taskPerformanceData = {};
const usersPrefs = await db
  .collection("userTaskPreferences")
  .limit(100)
  .get();

console.log("📊 usersPrefs size:", usersPrefs.size);
if (!usersPrefs.empty) { // 👈 تحقق من وجود بيانات
  usersPrefs.docs.forEach(doc => {
    const prefs = doc.data().taskPreferences || {};
    Object.entries(prefs).forEach(([taskId, stats]) => {
      if (!taskPerformanceData[taskId]) {
        taskPerformanceData[taskId] = {
          completed: 0,
          ignored: 0
        };
      }
      taskPerformanceData[taskId].completed += stats.completed || 0;
      taskPerformanceData[taskId].ignored += stats.ignored || 0;
    });
  });
}

let weakPerformanceTasks = [];
if (Object.keys(taskPerformanceData).length > 0) { // 👈 تحقق إضافي
  weakPerformanceTasks = Object.entries(taskPerformanceData)
    .filter(([_, stats]) => 
      stats.completed < 3 || 
      stats.ignored > stats.completed * 2 || 
      stats.ignored >= 10
    )
    .map(([id, stats]) => ({ id, ...stats }))
    .sort((a, b) => (b.ignored - b.completed) - (a.ignored - a.completed));
}

// التأكد من أن weakPerformanceTasks مصفوفة قبل التكرار
if (Array.isArray(weakPerformanceTasks) && weakPerformanceTasks.length > 0) {
  for (const item of weakPerformanceTasks) {
    // التأكد من أن item يحتوي على id
    if (!item || !item.id) continue;
    
    const taskId = item.id;
    const stats = { 
      completed: item.completed || 0, 
      ignored: item.ignored || 0 
    };
    
    try {
      const taskDoc = await db.collection("tasks").doc(taskId).get();
      if (taskDoc.exists && !tasksToDelete.some(t => t.id === taskId)) {
        const taskData = taskDoc.data();
        tasksToDelete.push({
          id: taskId,
          title: taskData.title || 'مهمة غير معروفة',
          category: taskData.category || 'غير محدد',
          reason: 'poor_performance',
          priority: 2,
          ignoreCount: stats.ignored,
          completionCount: stats.completed,
          description: `تم تجاهلها ${stats.ignored} مرة مقابل ${stats.completed} إنجاز فقط`
        });
      }
    } catch (e) {
      console.log(`⚠️ Error fetching task ${taskId}:`, e.message);
    }
  }
}
    tasksToDelete.sort((a, b) => a.priority - b.priority);

    // إضافة توصيات الحذف (أول 5 مهام)
    for (const task of tasksToDelete.slice(0, 5)) {
      if (!await isTaskDuplicate(`delete_${task.title}`, 60)) {
        
        let descriptionText = '';
        let basedOnText = '';
        
        switch(task.reason) {
          case 'zero_completion':
            descriptionText = `مهمة "${task.title}" لم يحققها أي مستخدم منذ إضافتها`;
            basedOnText = 'لا يوجد أي إنجازات للمهمة';
            break;
          case 'poor_performance':
            descriptionText = `مهمة "${task.title}" تم تجاهلها ${task.ignoreCount} مرة مقابل ${task.completionCount} إنجاز فقط`;
            basedOnText = 'نسبة تجاهل عالية جداً مقارنة بالإنجازات';
            break;
        }
        
        aiRecommendations.push({
          type: "delete",
          category: task.category || 'غير محدد',
          title: `حذف مهمة "${task.title}"`,
          description: descriptionText,
          suggestion: "يُقترح حذف هذه المهمة أو تطويرها لتصبح أكثر جاذبية للمستخدمين",
          basedOn: basedOnText,
          taskId: task.id,
          metadata: {
            reason: task.reason,
            ignoreCount: task.ignoreCount || 0,
            completionCount: task.completionCount || 0
          }
        });
      }
    }

    // منع التكرار مع التوصيات السابقة للمهام المضافة فقط
    const uniqueRecommendations = [];
    for (const rec of aiRecommendations) {
      if (rec.type === 'add') {
        if (!await isTaskDuplicate(rec.title)) {
          uniqueRecommendations.push(rec);
        }
      } else {
        uniqueRecommendations.push(rec);
      }
    }

    // ====================================================
    // 💾 حفظ في Firestore
    // ====================================================
    await db.collection("adminRecommendations").doc(currentMonth).set({
      month: currentMonth,
      season: season,
      recommendations: uniqueRecommendations.slice(0, 12),
      summary: {
        totalTasks: activeTasks.size,
        transportTasks: activeTasks.docs.filter(d => d.data().category?.includes("نقل")).length,
        recyclingTasks: activeTasks.docs.filter(d => d.data().category?.includes("تدوير")).length,
        pendingReports: pendingTaskReports.size + pendingContainerReports.size,
        zeroCompletionTasks: zeroCompletionTasks.length,
        ignoredTasksCount: ignoredTasksWithDetails.length,
        problematicTasks: problematicTasks.length,
        problematicContainers: problematicContainers.length
      },
      generatedAt: admin.firestore.FieldValue.serverTimestamp(),
      analytics: {
        mostIgnoredTasks: ignoredTasksWithDetails,
        mostSuccessfulTasks: successfulTasksWithDetails,
        zeroCompletionTasks: zeroCompletionTasks.slice(0, 5),
        problematicTasks: problematicTasks,
        problematicContainers: problematicContainers
      }
    });

    return {
      month: currentMonth,
      season: season,
      recommendations: uniqueRecommendations.slice(0, 12),
      summary: {
        totalTasks: activeTasks.size,
        transportTasks: activeTasks.docs.filter(d => d.data().category?.includes("نقل")).length,
        recyclingTasks: activeTasks.docs.filter(d => d.data().category?.includes("تدوير")).length,
        pendingReports: pendingTaskReports.size + pendingContainerReports.size,
        zeroCompletionTasks: zeroCompletionTasks.length,
        ignoredTasksCount: ignoredTasksWithDetails.length,
        problematicTasks: problematicTasks.length,
        problematicContainers: problematicContainers.length
      }
    };

  } catch (error) {
    console.error("❌ Error generating admin recommendations:", error);
    
    // Fallback ديناميكي بناءً على البيانات المتاحة
    try {
      const categories = await getAllCategories();
      const categoryList = categories.length > 0 ? categories : [];
      
      const fallbackRecs = [];
      
      // إضافة توصية بناءً على الموسم
      const today = DateTime.now().setZone("Asia/Riyadh");
      const month = today.month;
      let seasonName = "الربيع";
      if (month >= 6 && month <= 8) seasonName = "الصيف";
      else if (month >= 9 && month <= 11) seasonName = "الخريف";
      else if (month === 12 || month === 1 || month === 2) seasonName = "الشتاء";
      
      const defaultCategory = categoryList.find(c => c.name.includes("مشي")) || 
                              categoryList.find(c => c.name.includes("نقل")) || 
                              { name: "المشي" };
      
      fallbackRecs.push({
        type: "add",
        category: defaultCategory.name,
        title: seasonName === "الربيع" ? "المشي" : "النشاط البدني",
        userDescription: `استمتع بأجواء ${seasonName} ومارس المشي يومياً`,
        suggestion: `أضف مهمة: '${seasonName === "الربيع" ? "المشي" : "النشاط البدني"}' - تعتمد على التحقق عبر الصور`,
        basedOn: `توصية تلقائية لفصل ${seasonName}`,
        validationStrategy: "التحقق عبر معالجة الصور",
        calcMode: "deltaPerItem",
        askCount: true,
        askDistanceKm: false,
        autoDistance: false
      });
      
      // إضافة توصية بلاغات إذا وجدت
      fallbackRecs.push({
        type: "review_reports",
        category: "إعادة التدوير",
        title: "مراجعة البلاغات المعلقة",
        description: "يوجد بلاغات معلقة تحتاج إلى مراجعة",
        suggestion: "يُرجى مراجعة البلاغات والعمل على حلها",
        basedOn: "بلاغات المستخدمين",
        reportCount: 5
      });
      
      return {
        month: new Date().toISOString().slice(0, 7),
        season: { season: seasonName },
        recommendations: fallbackRecs,
        summary: {
          transportTasks: 0,
          recyclingTasks: 0,
          pendingReports: 5,
          zeroCompletionTasks: 0,
          ignoredTasksCount: 0,
          problematicTasks: 0,
          problematicContainers: 0
        }
      };
      
    } catch (fallbackError) {
      // Fallback نهائي
      return {
        month: new Date().toISOString().slice(0, 7),
        season: { season: "الربيع" },
        recommendations: [
          {
            type: "add",
            category: "المشي",
            title: "المشي",
            description: "مارس المشي يومياً واستمتع بالهواء الطلق",
            suggestion: "أضف مهمة: 'المشي' - تعتمد على التحقق عبر الصور",
            basedOn: "توصية تلقائية",
            validationStrategy: "التحقق عبر معالجة الصور",
            calcMode: "deltaPerItem",
            askCount: true,
            askDistanceKm: false,
            autoDistance: false
          },
          {
            type: "review_reports",
            category: "إعادة التدوير",
            title: "مراجعة البلاغات",
            description: "هناك بلاغات معلقة تستدعي المراجعة",
            suggestion: "يُرجى مراجعة البلاغات",
            basedOn: "بلاغات المستخدمين",
            reportCount: 5
          }
        ],
        summary: {
          transportTasks: 0,
          recyclingTasks: 0,
          pendingReports: 5,
          zeroCompletionTasks: 0,
          ignoredTasksCount: 0,
          problematicTasks: 0,
          problematicContainers: 0
        }
      };
    }
  }
});
/* ============================================================
 * ⏰ Scheduled Function: كل يوم 5:33 صباحاً
 * ============================================================ */
exports.scheduledGetAdminRecommendations = onSchedule(
  {
    schedule: "35 3 * * *",
    timeZone: "Asia/Riyadh",
  },
  async () => {
    console.log("⏰ Generating daily admin recommendations at 5:33 AM Riyadh time...");
    
    try {
      const admins = await db
        .collection("users")
        .where("role", "==", "admin")
        .get();
      
      if (admins.size > 0) {
        const mockRequest = {
          auth: { uid: admins.docs[0].id }
        };
        await exports.getAdminRecommendations(mockRequest);
        console.log("✅ Daily admin recommendations generated successfully");
      }
      
    } catch (error) {
      console.error("❌ Failed to generate daily admin recommendations:", error);
    }
  }
);