import functions_framework
import firebase_admin
from firebase_admin import firestore
import time
import json
import math
import os
import urllib.request
from datetime import datetime, timezone

# ============================================================
# تهيئة Firebase
# ============================================================
if not firebase_admin._apps:
    firebase_admin.initialize_app()

db = firestore.client()

# ============================================================
# تحميل المحطات من ملفات JSON (تُحمّل مرة واحدة عند بدء التشغيل)
# ============================================================
BUS_STATIONS = []
METRO_STATIONS = []

def load_stations_from_json():
    """تحميل محطات الباص والمترو من ملفات JSON"""
    global BUS_STATIONS, METRO_STATIONS
    
    # المسار النسبي للملفات - عدل حسب موقع deployment
    base_path = os.path.join(os.path.dirname(__file__), "..", "assets", "data")
    
    # تحميل محطات الباص
    bus_path = os.path.join(base_path, "bus_stations.json")
    if os.path.exists(bus_path):
        try:
            with open(bus_path, "r", encoding="utf-8") as f:
                data = json.load(f)
                if isinstance(data, list):
                    BUS_STATIONS = data
                elif isinstance(data, dict) and "stations" in data:
                    BUS_STATIONS = data["stations"]
                elif isinstance(data, dict) and "features" in data:
                    BUS_STATIONS = data["features"]
                print(f"🚌 Loaded {len(BUS_STATIONS)} bus stations")
        except Exception as e:
            print(f"⚠️ Failed to load bus_stations.json: {e}")
    else:
        print(f"⚠️ bus_stations.json not found at {bus_path}")
    
    # تحميل محطات المترو
    metro_path = os.path.join(base_path, "metro_stations.json")
    if os.path.exists(metro_path):
        try:
            with open(metro_path, "r", encoding="utf-8") as f:
                data = json.load(f)
                if isinstance(data, list):
                    METRO_STATIONS = data
                elif isinstance(data, dict) and "stations" in data:
                    METRO_STATIONS = data["stations"]
                elif isinstance(data, dict) and "features" in data:
                    METRO_STATIONS = data["features"]
                print(f"🚇 Loaded {len(METRO_STATIONS)} metro stations")
        except Exception as e:
            print(f"⚠️ Failed to load metro_stations.json: {e}")
    else:
        print(f"⚠️ metro_stations.json not found at {metro_path}")

# تحميل عند بدء التشغيل
load_stations_from_json()

def get_coords_from_station(station) -> tuple:
    """استخراج الإحداثيات من station (تدعم صيغ JSON مختلفة)"""
    if isinstance(station, dict):
        # صيغة {lat, lng} أو {latitude, longitude}
        lat = station.get("lat") or station.get("latitude")
        lng = station.get("lng") or station.get("longitude") or station.get("lon")
        
        # صيغة GeoJSON Point
        if not lat and station.get("geometry"):
            geom = station.get("geometry", {})
            if geom.get("type") == "Point":
                coords = geom.get("coordinates", [])
                if len(coords) >= 2:
                    lng, lat = coords[0], coords[1]
        
        if lat and lng:
            return float(lat), float(lng)
    return None, None

# ============================================================
# حساب المسافة (Haversine)
# ============================================================
def calculate_distance(lat1, lon1, lat2, lon2):
    R = 6371
    d_lat = math.radians(lat2 - lat1)
    d_lon = math.radians(lon2 - lon1)
    a = (math.sin(d_lat / 2) ** 2 +
         math.cos(math.radians(lat1)) *
         math.cos(math.radians(lat2)) *
         math.sin(d_lon / 2) ** 2)
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

# ============================================================
# استدعاء Gemini API
# ============================================================
def call_gemini(prompt: str, temperature: float = 0.4, max_tokens: int = 800):
    api_key = os.environ.get("GEMINI_API_KEY", "")
    if not api_key:
        print("❌ GEMINI_API_KEY is missing!")
        return None

    url = f"https://generativelanguage.googleapis.com/v1/models/gemini-2.0-flash:generateContent?key={api_key}"

    body = json.dumps({
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {
            "temperature": temperature,
            "maxOutputTokens": max_tokens
        }
    }).encode("utf-8")

    for attempt in range(3):
        try:
            req = urllib.request.Request(
                url,
                data=body,
                headers={"Content-Type": "application/json"},
                method="POST"
            )
            with urllib.request.urlopen(req, timeout=30) as resp:
                result = json.loads(resp.read().decode("utf-8"))
                
                # ✅ اطبع الخطأ الكامل من Gemini
                if result.get("error"):
                    print(f"❌ Gemini error response: {result['error']}")
                    return None
                
                text = (result
                        .get("candidates", [{}])[0]
                        .get("content", {})
                        .get("parts", [{}])[0]
                        .get("text", ""))
                if text.strip():
                    print(f"✅ Gemini success on attempt {attempt + 1}")
                    return text.strip()
                else:
                    print(f"⚠️ Gemini attempt {attempt + 1}: empty response")
                    
        except urllib.error.HTTPError as e:
            # ✅ اقرأ تفاصيل الخطأ من الـ response body
            error_body = e.read().decode("utf-8")
            print(f"⚠️ Gemini attempt {attempt + 1} HTTP {e.code}: {error_body}")
            
        except Exception as e:
            print(f"⚠️ Gemini attempt {attempt + 1} failed: {e}")

    return None

# ============================================================
# استخراج JSON
# ============================================================
def extract_json(text: str):
    try:
        clean = text.replace("```json", "").replace("```", "").strip()
        first = clean.index("{")
        last  = clean.rindex("}") + 1
        return json.loads(clean[first:last])
    except Exception as e:
        print(f"⚠️ JSON extract failed: {e}")
        return None

# ============================================================
# تصنيف نوع المكان (محدث ليشمل النقل)
# ============================================================
def classify_place(place_type: str) -> str:
    t = place_type.lower()
    if "طعام" in t or "عضوي" in t:
        return "food_recycling"
    if "ملابس" in t or "منسوجات" in t:
        return "clothes_recycling"
    if "إلكتروني" in t or "كهربائي" in t:
        return "electronic_recycling"
    if "بلاستيك" in t or "زجاج" in t or "ورق" in t:
        return "general_recycling"
    if "rvm" in t:
        return "rvm"
    if "باص" in t or "مترو" in t or "bus" in t or "metro" in t:
        return "transport"
    return "recycling"

# ============================================================
# جلب بروفايل المستخدم الكامل
# ============================================================
def get_user_profile(user_id: str) -> dict:
    try:
        doc = db.collection("users").document(user_id).get()
        if not doc.exists:
            return {}
        data = doc.to_dict()

        # المستوى
        level_id = data.get("userLevelId", "beginner")
        if level_id == "beginner":
            level_label = "مبتدئ"
            level_tone  = "تشجيعي — هذا مستخدم جديد يحتاج تحفيز وتشجيع لبدء رحلته"
        elif level_id == "medium":
            level_label = "متوسط"
            level_tone  = "إيجابي — مستخدم نشيط يستحق الإشادة بتقدمه"
        else:
            level_label = "متقدم"
            level_tone  = "احترافي — مستخدم ملتزم يقدّر التحدي والأهداف الكبيرة"

        # الجنس للمخاطبة
        gender = data.get("gender", "")
        if gender == "female":
            pronoun = "أنتِ"
            suffix  = "ي"
        else:
            pronoun = "أنت"
            suffix  = ""

        return {
            "level_id":      level_id,
            "level_label":   level_label,
            "level_tone":    level_tone,
            "pronoun":       pronoun,
            "suffix":        suffix,
            "gender":        gender,
            "completed":     data.get("completedTask", 0),
            "streak":        data.get("currentStreak", 0),
            "points":        data.get("points", 0),
            "carbon_saved":  round(data.get("totalCarbonSaved", 0), 2),
            "username":      data.get("username", ""),
        }
    except Exception as e:
        print(f"⚠️ get_user_profile error: {e}")
        return {}

# ============================================================
# جلب تفضيلات المستخدم
# ============================================================
def get_user_preferences(user_id: str, context: dict) -> dict:
    try:
        doc = db.collection("userTaskPreferences").document(user_id).get()
        if not doc.exists:
            return {"found": False}

        data  = doc.to_dict()
        prefs = data.get("taskPreferences", {})

        top_tasks     = []
        ignored_tasks = []
        task_scores   = {}

        for tid, stats in prefs.items():
            score     = stats.get("score", 1)      # ← Wilson Score
            view_count = stats.get("viewCount", 0) # ← من الأيجنت
            task_scores[tid] = score

            entry = {
                "task_id":   tid,
                "title":     stats.get("title", ""),
                "category":  stats.get("category", ""),
                "score":     score,
                "viewCount": view_count,
                # ❌ حذفنا completed و ignored
            }

            if score > 3:
                top_tasks.append(entry)

            # المتجاهلة: score منخفض + viewCount عالي
            if score < 2 and view_count > 3:
                ignored_tasks.append(entry)

        top_tasks.sort(key=lambda x: x["score"], reverse=True)
        ignored_tasks.sort(key=lambda x: x["viewCount"], reverse=True)

        context["task_scores"]  = task_scores
        context["ignored_ids"]  = [t["task_id"] for t in ignored_tasks[:15]]
        context["top_task_ids"] = [t["task_id"] for t in top_tasks[:5]]

        return {
            "found":          True,
            "top_tasks":      top_tasks[:5],
            "ignored_tasks":  ignored_tasks[:3],
            "top_task_title": data.get("topTaskTitle", ""),
        }
    except Exception as e:
        print(f"⚠️ get_user_preferences error: {e}")
        return {"found": False, "error": str(e)}

# ============================================================
# جلب الأماكن القريبة (حاويات + محطات باص + محطات مترو)
# ============================================================
def get_nearby_places(lat: float, lng: float, context: dict, radius: float = 2.0) -> dict:
    nearby = []
    
    # ============================================================
    # 1. الحاويات من facilities
    # ============================================================
    try:
        for doc in db.collection("facilities").stream():
            d = doc.to_dict()
            place_lat = d.get("lat")
            place_lng = d.get("lng")
            if place_lat is None or place_lng is None:
                continue
            if d.get("status") == "متوقف":
                continue
            
            dist = calculate_distance(lat, lng, place_lat, place_lng)
            if dist <= radius:
                place_type = d.get("type", "مكان")
                nearby.append({
                    "id":       doc.id,
                    "name":     place_type,
                    "address":  d.get("address", ""),
                    "provider": d.get("provider", ""),
                    "type":     place_type,
                    "distance": round(dist, 2),
                    "category": classify_place(place_type),
                    "source":   "facility",
                    "priority": 1
                })
    except Exception as e:
        print(f"⚠️ facilities error: {e}")
    
    # ============================================================
    # 2. محطات الباص من JSON
    # ============================================================
    for station in BUS_STATIONS:
        station_lat, station_lng = get_coords_from_station(station)
        if station_lat is None or station_lng is None:
            continue
        
        dist = calculate_distance(lat, lng, station_lat, station_lng)
        if dist <= radius:
            station_name = station.get("name") or station.get("station_name") or "محطة باص"
            nearby.append({
                "id":       f"bus_{station.get('id', hash(str(station)))}",
                "name":     station_name,
                "address":  station.get("address") or station.get("location_description") or "",
                "provider": "هيئة النقل العام",
                "type":     "محطة باص",
                "distance": round(dist, 2),
                "category": "transport",
                "source":   "bus_station",
                "priority": 2
            })
    
    # ============================================================
    # 3. محطات المترو من JSON
    # ============================================================
    for station in METRO_STATIONS:
        station_lat, station_lng = get_coords_from_station(station)
        if station_lat is None or station_lng is None:
            continue
        
        dist = calculate_distance(lat, lng, station_lat, station_lng)
        if dist <= radius:
            station_name = station.get("name") or station.get("station_name") or "محطة مترو"
            line_info = station.get("line") or station.get("metro_line") or ""
            address = f"{station_name} ({line_info})" if line_info else station_name
            
            nearby.append({
                "id":       f"metro_{station.get('id', hash(str(station)))}",
                "name":     station_name,
                "address":  station.get("address") or address,
                "provider": "هيئة النقل العام",
                "type":     "محطة مترو",
                "distance": round(dist, 2),
                "category": "transport",
                "source":   "metro_station",
                "priority": 2
            })
    
    # ============================================================
    # ترتيب حسب المسافة ثم الأولوية
    # ============================================================
    nearby.sort(key=lambda x: (x["distance"], -x["priority"]))
    
    context["nearby_places"] = nearby
    print(f"📍 Found {len(nearby)} nearby places (facilities: {len([p for p in nearby if p['source']=='facility'])}, bus: {len([p for p in nearby if p['source']=='bus_station'])}, metro: {len([p for p in nearby if p['source']=='metro_station'])})")
    
    summary = []
    for p in nearby[:5]:
        summary.append(f"{p['type']} على بعد {p['distance']} كم")
    
    return {
        "count":   len(nearby),
        "places":  nearby[:5],
        "insight": " | ".join(summary) if summary else "لا توجد أماكن قريبة → اقترح مهام منزلية"
    }

# ============================================================
# جلب المهام المتاحة
# ============================================================
def get_available_tasks(exclude_ids: list, context: dict) -> dict:
    exclude       = set(exclude_ids or [])
    ignored_ids   = set(context.get("ignored_ids", []))
    task_scores   = context.get("task_scores", {})
    current_month = datetime.now().strftime("%Y-%m")

    tasks = []
    try:
        for doc in db.collection("tasks").where("status", "==", "active").stream():
            if doc.id in exclude or doc.id in ignored_ids:
                continue
            t = doc.to_dict()
            if t.get("visible_from", "") > current_month:
                continue
            if t.get("expiry_month") and t["expiry_month"] < current_month:
                continue
            tasks.append({
                "id":               doc.id,
                "title":            t.get("title", ""),
                "description":      t.get("description", ""),
                "category":         t.get("category", ""),
                "points":           t.get("points", 0),
                "preference_score": task_scores.get(doc.id, 1),
                "validation":       t.get("validationStrategy", ""),
                "calc_mode":        t.get("calcMode", ""),
                "ef_ref":           t.get("ef_ref", "")
            })
    except Exception as e:
        print(f"⚠️ get_available_tasks error: {e}")
        return {"count": 0, "tasks": [], "error": str(e)}

    tasks.sort(key=lambda x: x["preference_score"], reverse=True)
    context["available_tasks"] = tasks
    print(f"📋 Found {len(tasks)} available tasks")
    return {"count": len(tasks), "tasks": tasks}

# ============================================================
# جلب تاريخ المستخدم
# ============================================================
def get_user_task_history(user_id: str, context: dict, limit: int = 20) -> dict:
    completed_ids = []
    ignored_ids   = []

    try:
        for d in (db.collection("userTasks")
                    .where("userId",  "==", user_id)
                    .where("status",  "==", "completed")
                    .order_by("completedAt", direction=firestore.Query.DESCENDING)
                    .limit(limit)
                    .stream()):
            tid = d.to_dict().get("taskId")
            if tid:
                completed_ids.append(tid)

        for d in (db.collection("userTasks")
                    .where("userId",  "==", user_id)
                    .where("ignored", "==", True)
                    .order_by("ignoredAt", direction=firestore.Query.DESCENDING)
                    .limit(limit)
                    .stream()):
            tid = d.to_dict().get("taskId")
            if tid:
                ignored_ids.append(tid)

    except Exception as e:
        print(f"⚠️ get_user_task_history error: {e}")

    existing = set(context.get("ignored_ids", []))
    context["ignored_ids"] = list(existing | set(ignored_ids))

    return {
        "completed_count":    len(completed_ids),
        "ignored_count":      len(ignored_ids),
        "recently_completed": completed_ids[:5],
        "recently_ignored":   ignored_ids[:5]
    }

# ============================================================
# الأيجنت الرئيسي
# ============================================================
def run_task_agent(data: dict) -> dict:
    user_id         = data.get("userId")
    pressed_at      = data.get("pressedAt", datetime.now(timezone.utc).isoformat())
    user_location   = data.get("userLocation")
    exclude_task_id = data.get("excludeTaskId")
    today_task_id   = data.get("todayTaskId")

    if not user_id:
        return {"error": "userId مطلوب"}

    try:
        dt   = datetime.fromisoformat(pressed_at.replace("Z", "+00:00"))
        hour = dt.hour
    except Exception:
        hour = datetime.now().hour

    # تحديد نوع الوقت والأولوية
    if 5 <= hour < 12:
        time_label = "الصباح — وقت النشاط والحركة"
        time_type = "morning"
    elif 12 <= hour < 16:
        time_label = "الظهيرة — وقت المهام السريعة"
        time_type = "afternoon"
    elif 16 <= hour < 21:
        time_label = "المساء — وقت ممتاز للتدوير"
        time_type = "evening"
    else:
        time_label = "الليل — وقت مناسب للتوعية"
        time_type = "night"

    exclude_ids = [i for i in [exclude_task_id, today_task_id] if i]
    context     = {}

    # ── Step 1: بروفايل المستخدم ────────────────────────────
    print("👤 Step 1: Getting user profile...")
    profile = get_user_profile(user_id)
    print(f"   Level: {profile.get('level_id')} | Gender: {profile.get('gender')} | Streak: {profile.get('streak')}")

    # ── Step 2: تفضيلات المستخدم ───────────────────────────
    print("📊 Step 2: Getting user preferences...")
    prefs = get_user_preferences(user_id, context)

    # ── Step 3: الأماكن القريبة ─────────────────────────────
    nearby_result = {"count": 0, "places": [], "insight": "موقع غير متاح"}
    if user_location:
        print("📍 Step 3: Getting nearby places...")
        nearby_result = get_nearby_places(
            user_location["latitude"],
            user_location["longitude"],
            context
        )

    # ── Step 4: المهام المتاحة ──────────────────────────────
    print("📋 Step 4: Getting available tasks...")
    tasks_result = get_available_tasks(exclude_ids, context)

    if tasks_result["count"] == 0:
        return {"error": "NO_TASKS_AVAILABLE"}

    # ── Step 5: تاريخ المستخدم ──────────────────────────────
    print("📜 Step 5: Getting user history...")
    history = get_user_task_history(user_id, context)

    # ── Step 6: بناء الـ Prompt ─────────────────────────────
    available_tasks = context.get("available_tasks", [])
    top_task_ids    = context.get("top_task_ids", [])
    nearby_places_all = context.get("nearby_places", [])
    
    # فصل الأماكن حسب النوع
    recycling_places = [p for p in nearby_places_all if p['category'] != 'transport']
    transport_places = [p for p in nearby_places_all if p['category'] == 'transport']

    top_tasks_text = ""
    if prefs.get("top_tasks"):
        top_tasks_text = "\n".join([
            f"   • {t['title']} (score: {t['score']}, completed: {t['completed']})"
            for t in prefs["top_tasks"]
        ])

    ignored_text = ""
    if prefs.get("ignored_tasks"):
        ignored_text = "\n".join([
            f"   • {t['title']} (ignored: {t['ignored']})"
            for t in prefs["ignored_tasks"]
        ])

    nearby_details = ""
    if nearby_result["count"] > 0:
        nearby_details = "\n".join([
            f"   • {p['type']} — بعد {p['distance']} كم — {p['address']} [نوع: {p['category']}]"
            for p in nearby_result["places"][:5]
        ])

    task_list_text = "\n".join([
        f"{i+1}. [{t['id']}] {t['title']} - {t['category']} [score: {t['preference_score']}]"
        for i, t in enumerate(available_tasks)
    ])

    # بيانات المستخدم للتخصيص
    pronoun      = profile.get("pronoun", "أنت")
    suffix       = profile.get("suffix", "")
    level_label  = profile.get("level_label", "مبتدئ")
    level_tone   = profile.get("level_tone", "تشجيعي")
    streak       = profile.get("streak", 0)
    points       = profile.get("points", 0)
    carbon_saved = profile.get("carbon_saved", 0)
    completed    = profile.get("completed", 0)

    streak_text = f"لديه{suffix if profile.get('gender') == 'female' else ''} {streak} يوم متتالي 🔥" if streak > 1 else ""

    # بناء قواعد الأولوية حسب الوقت
    if time_type == "morning":
        priority_rules = """🎯 قواعد الاختيار (بالأولوية - الصباح: أولوية للنقل المستدام):
1. 🚌 الأولى: إذا يوجد محطة باص أو مترو قريبة → اختر مهمة النقل العام (استخدم الباص/المترو بدل السيارة)
2. ♻️ الثانية: إذا يوجد مكان تدوير قريب (حاوية طعام/ملابس/بلاستيك/RVM) → اختر مهمة تدوير مناسبة
3. ⭐ الثالثة: إذا لا يوجد أماكن → اختر من المفضلة (score > 5)
4. 🚫 الرابعة: تجنب المتجاهلة تماماً
⚠️ ملاحظة: الصباح وقت مثالي لتشجيع استخدام النقل العام"""
    elif time_type == "evening":
        priority_rules = """🎯 قواعد الاختيار (بالأولوية - المساء: أولوية للتدوير):
1. ♻️ الأولى: إذا يوجد مكان تدوير قريب (حاوية طعام/ملابس/بلاستيك/RVM) → اختر مهمة تدوير مناسبة
2. 🚌 الثانية: إذا يوجد محطة باص أو مترو قريبة → اختر مهمة النقل العام
3. ⭐ الثالثة: إذا لا يوجد أماكن → اختر من المفضلة (score > 5)
4. 🚫 الرابعة: تجنب المتجاهلة تماماً
⚠️ ملاحظة: المساء وقت مناسب للتخلص من النفايات بعد يوم طويل"""
    elif time_type == "afternoon":
        priority_rules = """🎯 قواعد الاختيار (بالأولوية - الظهيرة: مهام سريعة):
1. 🏆 الأولى: أقرب مكان من أي نوع (تدوير أو نقل) → اختر مهمة سريعة مناسبة
2. ⭐ الثانية: إذا لا يوجد أماكن قريبة → اختر من المفضلة (score > 5)
3. 🚫 الثالثة: تجنب المتجاهلة تماماً
⚠️ ملاحظة: الظهيرة مناسبة للمهام التي لا تستغرق وقتاً طويلاً"""
    else:  # night
        priority_rules = """🎯 قواعد الاختيار (بالأولوية - الليل: توعية):
1. 📚 الأولى: مهام توعوية وتعليمية (لا تحتاج حركة خارج المنزل)
2. ♻️ الثانية: إذا كان هناك مكان تدوير قريب جداً (اقل من 1 كم) → يمكن اقتراحه
3. ⭐ الثالثة: اختر من المفضلة (score > 5)
4. 🚫 الرابعة: تجنب المتجاهلة تماماً
⚠️ ملاحظة: الليل مناسب للقراءة والتعلم والتخطيط"""

    prompt = f"""أنت مساعد بيئي ذكي ومحفز. اختر مهمة واحدة وصِغ وصفاً شخصياً يحفز المستخدم.

⏰ الوقت: {time_label} (الساعة {hour})

📍 الأماكن القريبة:
{nearby_details if nearby_details else "لا توجد أماكن قريبة → اقترح مهام منزلية"}

📊 إحصاءات الأماكن:
- أماكن التدوير: {len(recycling_places)}
- محطات النقل: {len(transport_places)}

👤 شخصية المستخدم:
- المستوى: {level_label} ({level_tone})
- الجنس: {profile.get('gender', 'غير محدد')} — خاطب{suffix}ه بـ "{pronoun}"
- المهام المكتملة: {completed} مهمة
- النقاط: {points} نقطة
- الكربون الموفَّر: {carbon_saved} كغ
{f"- {streak_text}" if streak_text else ""}

📊 تفضيلاته:
{f"المفضلة:{chr(10)}{top_tasks_text}" if top_tasks_text else "لا توجد تفضيلات واضحة"}
{f"المتجاهلة:{chr(10)}{ignored_text}" if ignored_text else ""}

📋 المهام المتاحة:
{task_list_text}

{priority_rules}

✍️ قواعد كتابة الوصف (مهم جداً):
- خاطب{suffix}ه دائماً بـ "{pronoun}" بأسلوب دافئ وودود
- إذا المستوى "مبتدئ" → حفزه للبداية: "{pronoun} في بداية رحلتك..."
- إذا المستوى "متوسط" → أشِد بتقدمه: "واصل{suffix} مسيرتك الرائعة..."
- إذا المستوى "متقدم" → تحدّه: "بطل{suffix} البيئة، الآن تحدٍّ جديد..."
- اذكر المكان القريب إن وجد مع المسافة ونوعه
- إذا عنده streak أكثر من 1 → اذكره: "حافظ{suffix} على سلسلتك!"
- 20-30 كلمة فقط، مختلف تماماً عن الوصف الأصلي للمهمة

أرجع JSON فقط:
{{
  "taskId": "معرف المهمة من القائمة",
  "reasoning": "سبب الاختيار مع ذكر المكان القريب ونوعه والوقت",
  "personalizedDescription": "وصف مخصص دافئ يراعي مستوى المستخدم وجنسه والوقت"
}}"""

    # ── Step 7: استدعاء Gemini ──────────────────────────────
    print("🤖 Step 7: Calling Gemini...")
    gemini_response = call_gemini(prompt, temperature=0.5, max_tokens=600)

    final_task        = None
    final_description = ""
    agent_reasoning   = ""

    if gemini_response:
        parsed = extract_json(gemini_response)
        if parsed and parsed.get("taskId"):
            task_id    = parsed["taskId"].replace("[", "").replace("]", "").strip()
            final_task = next((t for t in available_tasks if t["id"] == task_id), None)
            if final_task:
                final_description = parsed.get("personalizedDescription", "")
                agent_reasoning   = parsed.get("reasoning", "")
                print(f"✅ Gemini selected: {final_task['title']}")
            else:
                print(f"⚠️ Task ID not found: {task_id}")

    # ── Fallback محسّن حسب الوقت والأماكن ────────────────────
    if not final_task:
        print("⚠️ Using fallback...")
        ignored    = set(context.get("ignored_ids", []))
        candidates = [t for t in available_tasks if t["id"] not in ignored]
        
        # فلترة حسب الوقت والأماكن
        transport_tasks = [t for t in candidates if t.get("category") == "transport"]
        recycling_tasks = [t for t in candidates if t.get("category") in ["recycling", "food_recycling", "clothes_recycling", "general_recycling"]]
        awareness_tasks = [t for t in candidates if t.get("category") == "awareness"]
        
        selected_candidates = []
        
        if time_type == "morning" and transport_places:
            selected_candidates = transport_tasks
        elif time_type == "evening" and recycling_places:
            selected_candidates = recycling_tasks
        elif time_type == "afternoon" and (recycling_places or transport_places):
            selected_candidates = candidates
        elif time_type == "night":
            selected_candidates = awareness_tasks or candidates
        
        if not selected_candidates:
            selected_candidates = candidates
        
        # تطبيق التفضيلات
        preferred = [t for t in selected_candidates if t["id"] in top_task_ids]
        
        if preferred:
            final_task = preferred[0]
        elif selected_candidates:
            final_task = selected_candidates[0]
        elif candidates:
            final_task = candidates[0]
        elif available_tasks:
            final_task = available_tasks[0]

        if final_task:
            nearby_places = context.get("nearby_places", [])
            suffix = profile.get("suffix", "")
            
            # بناء وصف مخصص حسب الوقت والمكان
            if time_type == "morning" and transport_places:
                nearest = transport_places[0]
                final_description = f"🌅 صباح الخير {pronoun}! محطة {nearest['type']} قريبة منك ({nearest['distance']} كم). استغل{suffix} الفرصة وجرب{suffix} {final_task['title']} اليوم 🚌✨"
            elif time_type == "evening" and recycling_places:
                nearest = recycling_places[0]
                final_description = f"🌙 مساء الخير {pronoun}! {nearest['type']} قريبة منك ({nearest['distance']} كم). وقت مثالي لـ {final_task['title']} ♻️💚"
            elif nearby_places:
                nearest = nearby_places[0]
                final_description = f"📍 {nearest['type']} قريبة منك ({nearest['distance']} كم)! جرب{suffix} {final_task['title']} الآن ✨"
            elif level_label == "مبتدئ":
                final_description = f"🌱 {pronoun} في بداية رحلتك! {final_task['title']} خطوة رائعة للانطلاق 🚀"
            elif level_label == "متوسط":
                final_description = f"⭐ واصل{suffix} تقدمك! {final_task['title']} تضيف نقاطاً لرصيدك البيئي 💚"
            else:
                final_description = f"🏆 تحدٍّ جديد يا بطل{suffix} البيئة! {final_task['title']} تستحق{suffix} منك ✨"
            
            agent_reasoning = f"fallback: gemini لم يصل لقرار (الوقت: {time_type}, الأماكن: {len(nearby_places)})"

    if not final_task:
        return {"error": "NO_SUITABLE_TASK_FOUND"}

    # ── النتيجة ─────────────────────────────────────────────
    task_scores   = context.get("task_scores", {})
    nearby_places = context.get("nearby_places", [])

    return {
        "id":                         final_task["id"],
        "taskId":                     final_task["id"],
        "title":                      final_task.get("title", ""),
        "description":                final_description or final_task.get("description", ""),
        "originalDescription":        final_task.get("description", ""),
        "points":                     final_task.get("points", 0),
        "category":                   final_task.get("category", ""),
        "validationStrategy":         final_task.get("validation", ""),
        "calcMode":                   final_task.get("calc_mode", ""),
        "ef_ref":                     final_task.get("ef_ref", ""),
        "status":                     "pending",
        "agentReasoning":             agent_reasoning,
        "nearbyPlacesCount":          len(nearby_places),
        "nearbyPlaces":               nearby_places[:3],
        "nearbyRecyclingPlaces":      len([p for p in nearby_places if p['category'] != 'transport']),
        "nearbyTransportPlaces":      len([p for p in nearby_places if p['category'] == 'transport']),
        "userLocationDetected":       user_location is not None,
        "timeContext": {
            "hour": hour,
            "timeLabel": time_label,
            "timeType": time_type
        },
        "preferenceScore":            task_scores.get(final_task["id"], 1),
        "suggestedBasedOnLocation":   len(nearby_places) > 0,
        "suggestedBasedOnPreference": (
            final_task["id"] in top_task_ids or
            task_scores.get(final_task["id"], 1) > 5
        ),
        "userProfile": {
            "level":    profile.get("level_id", ""),
            "streak":   profile.get("streak", 0),
            "points":   profile.get("points", 0),
            "carbon":   profile.get("carbon_saved", 0),
        }
    }

# ============================================================
# HTTP Entry Point
# ============================================================
@functions_framework.http
def suggest_task_agent(request):
    if request.method == "OPTIONS":
        return ("", 204, {
            "Access-Control-Allow-Origin":  "*",
            "Access-Control-Allow-Methods": "POST, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type, Authorization"
        })

    if request.method != "POST":
        return (json.dumps({"error": "POST only"}), 405,
                {"Content-Type": "application/json"})

    try:
        data   = request.get_json(silent=True) or {}
        result = run_task_agent(data)
        status = 200 if "error" not in result else 404

        return (
            json.dumps(result, ensure_ascii=False, default=str),
            status,
            {
                "Content-Type":                "application/json; charset=utf-8",
                "Access-Control-Allow-Origin": "*"
            }
        )
    except Exception as e:
        import traceback
        traceback.print_exc()
        return (
            json.dumps({"error": str(e)}, ensure_ascii=False),
            500,
            {"Content-Type": "application/json"}
        )
###########################################################


import math
from datetime import datetime, timezone, timedelta
 
# ============================================================
# توليد المهام اليومية لجميع المستخدمين
# ============================================================
def run_daily_task_agent(data: dict) -> dict:
    print("⏰ Daily Task Agent Starting...")
 
    tomorrow = (datetime.now() + timedelta(days=1)).strftime("%Y-%m-%d")
    current_month = datetime.now().strftime("%Y-%m")
 
    print(f"📅 Generating tasks for: {tomorrow}")
 
    # ── Step 1: جلب المهام المتاحة ──────────────────────────
    print("📋 Step 1: Loading available tasks...")
    available_tasks = _get_available_tasks(current_month)
    if not available_tasks:
        return {"error": "NO_TASKS_AVAILABLE", "created": 0}
 
    print(f"   ✅ Found {len(available_tasks)} available tasks")
 
    # ── Step 2: جلب جميع المستخدمين ────────────────────────
    print("👥 Step 2: Loading users...")
    users = []
    try:
        for doc in db.collection("users").stream():
            d = doc.to_dict()
            if d.get("role") == "admin":
                continue
            users.append({"id": doc.id, **d})
    except Exception as e:
        print(f"⚠️ Error loading users: {e}")
        return {"error": str(e), "created": 0}
 
    print(f"   ✅ Found {len(users)} users")
 
    tasks_created = 0
 
    # ── Step 3: توليد مهمة لكل مستخدم ──────────────────────
    for user in users:
        user_id = user["id"]
        print(f"\n👤 Processing user: {user_id}")
 
        try:
            result = _generate_task_for_user(
                user_id=user_id,
                user_data=user,
                available_tasks=available_tasks,
                tomorrow=tomorrow,
            )
            if result:
                tasks_created += 1
        except Exception as e:
            print(f"   ❌ Failed for {user_id}: {e}")

        time.sleep(4)
 
    print(f"\n🎉 Daily tasks generated: {tasks_created}/{len(users)}")
    return {"created": tasks_created, "total_users": len(users), "date": tomorrow}
 
 
# ============================================================
# جلب المهام المتاحة للشهر الحالي
# ============================================================
def _get_available_tasks(current_month: str) -> list:
    tasks = []
    fallback = [
        {"id": "fallback_1", "title": "وفر الطاقة",  "description": "افصل الأجهزة الكهربائية غير المستخدمة", "category": "الكهرباء", "points": 10},
        {"id": "fallback_2", "title": "دور المخلفات", "description": "افصل البلاستيك عن الورق",              "category": "إعادة التدوير", "points": 10},
        {"id": "fallback_3", "title": "امشِ اليوم",   "description": "امشِ إذا كانت المسافة قريبة",          "category": "النقل المستدام", "points": 10},
        {"id": "fallback_4", "title": "وفر الماء",    "description": "أغلق الصنبور أثناء تنظيف الأسنان",     "category": "ترشيد الماء",   "points": 10},
    ]
    try:
        for doc in db.collection("tasks").where("status", "==", "active").stream():
            t = doc.to_dict()
            if t.get("visible_from", "") > current_month:
                continue
            if t.get("expiry_month") and t["expiry_month"] < current_month:
                continue
            tasks.append({
                "id":                 doc.id,
                "title":              t.get("title", ""),
                "description":        t.get("description", ""),
                "category":           t.get("category", ""),
                "points":             t.get("points", 10),
                "validationStrategy": t.get("validationStrategy", ""),
                "calcMode":           t.get("calcMode", ""),
                "emissionFactorRef":  t.get("emissionFactorRef", ""),
            })
    except Exception as e:
        print(f"⚠️ Error loading tasks: {e}")
 
    return tasks if tasks else fallback
 
 
# ============================================================
# توليد مهمة ليوزر واحد
# ============================================================
def _generate_task_for_user(
    user_id: str,
    user_data: dict,
    available_tasks: list,
    tomorrow: str,
) -> bool:
 
    # ── جلب بيانات التفضيلات من userTaskPreferences ─────────
    prefs_data    = _get_user_preferences(user_id)
    top_task_ids  = prefs_data.get("topTasks", [])
    task_prefs    = prefs_data.get("taskPreferences", {})
 
    # ── جلب المهام المتجاهلة والمتروكة ───────────────────────
    ignored_ids  = _get_ignored_task_ids(user_id)
    pending_ids  = _get_pending_daily_task_ids(user_id)
    yesterday_id = _get_yesterday_task_id(user_id)
 
    tasks_to_avoid = ignored_ids | pending_ids
    if yesterday_id:
        tasks_to_avoid.add(yesterday_id)
 
    print(f"   🚫 Tasks to avoid: {len(tasks_to_avoid)}")
 
    # ── تصفية المهام المتاحة ──────────────────────────────────
    candidate_tasks = [
        t for t in available_tasks
        if t["id"] not in tasks_to_avoid
    ]
    if not candidate_tasks:
        candidate_tasks = available_tasks  # fallback: جميع المهام
 
    # ── بناء ملف المستخدم ─────────────────────────────────────
    user_profile = _build_user_profile(user_data, task_prefs)
 
    # ── بناء الـ Prompt ───────────────────────────────────────
    prompt = _build_daily_task_prompt(
        user_profile=user_profile,
        candidate_tasks=candidate_tasks,
        top_task_ids=top_task_ids,
        task_prefs=task_prefs,
        ignored_ids=ignored_ids,
        pending_ids=pending_ids,
        yesterday_id=yesterday_id,
    )
 
    # ── استدعاء Gemini ────────────────────────────────────────
    gemini_response = call_gemini(prompt, temperature=0.3, max_tokens=600)
 
    selected_task       = None
    personalized_desc   = ""
 
    if gemini_response:
        parsed = extract_json(gemini_response)
        if parsed and parsed.get("taskId"):
            task_id = parsed["taskId"].replace("[", "").replace("]", "").strip()
            selected_task     = next((t for t in candidate_tasks if t["id"] == task_id), None)
            personalized_desc = parsed.get("personalizedDescription", "")
            if selected_task:
                print(f"   ✅ Gemini selected: {selected_task['title']}")
            else:
                print(f"   ⚠️ Task ID not found: {task_id}")
 
    # ── Fallback ──────────────────────────────────────────────
    if not selected_task:
        print("   ⚠️ Using fallback selection...")
        selected_task, personalized_desc = _fallback_select(
            candidate_tasks=candidate_tasks,
            top_task_ids=top_task_ids,
            task_prefs=task_prefs,
            user_profile=user_profile,
        )
 
    if not selected_task:
        print(f"   ❌ No task selected for {user_id}")
        return False
 
    # ── حفظ في dailyTasks ────────────────────────────────────
    task_doc = {
        **selected_task,
        "description": personalized_desc or selected_task["description"],
        "createdAt":   firestore.SERVER_TIMESTAMP,
        "status":      "pending",
    }
 
    db.collection("dailyTasks") \
      .document(user_id) \
      .collection("tasks") \
      .document(tomorrow) \
      .set(task_doc)
 
    # ── تحديث viewCount في userTaskPreferences ───────────────
    _update_view_count(user_id, selected_task)
 
    print(f"   ✅ Task saved: {selected_task['title']}")
    return True
 
 
# ============================================================
# جلب بيانات userTaskPreferences
# ============================================================
def _get_user_preferences(user_id: str) -> dict:
    try:
        doc = db.collection("userTaskPreferences").document(user_id).get()
        if doc.exists:
            return doc.to_dict()
    except Exception as e:
        print(f"   ⚠️ Preferences error: {e}")
    return {}
 
 
# ============================================================
# جلب المهام المتجاهلة
# ============================================================
def _get_ignored_task_ids(user_id: str) -> set:
    ids = set()
    try:
        for doc in (
            db.collection("userTasks")
              .where("userId",  "==", user_id)
              .where("ignored", "==", True)
              .order_by("ignoredAt", direction=firestore.Query.DESCENDING)
              .limit(20)
              .stream()
        ):
            tid = doc.to_dict().get("taskId")
            if tid:
                ids.add(tid)
    except Exception as e:
        print(f"   ⚠️ Ignored tasks error: {e}")
    return ids
 
 
# ============================================================
# جلب المهام المتروكة من dailyTasks (عُرضت ولم تكتمل)
# ============================================================
def _get_pending_daily_task_ids(user_id: str, days_back: int = 7) -> set:
    ids = set()
    try:
        cutoff = datetime.now() - timedelta(days=days_back)
        cutoff_ts = cutoff.timestamp()
 
        for doc in (
            db.collection("dailyTasks")
              .document(user_id)
              .collection("tasks")
              .where("status", "==", "pending")
              .stream()
        ):
            d = doc.to_dict()
            # تحقق من التاريخ يدوياً
            created_at = d.get("createdAt")
            try:
                if hasattr(created_at, "_seconds"):
                    doc_ts = created_at._seconds
                elif hasattr(created_at, "timestamp"):
                    doc_ts = created_at.timestamp()
                else:
                    continue
                if doc_ts >= cutoff_ts:
                    tid = d.get("id")
                    if tid:
                        ids.add(tid)
                        print(f"   ⏳ Pending daily task: {d.get('title')} ({tid})")
            except:
                pass
    except Exception as e:
        print(f"   ⚠️ Pending tasks error: {e}")
    return ids
 
 
# ============================================================
# جلب مهمة الأمس
# ============================================================
def _get_yesterday_task_id(user_id: str) -> str | None:
    try:
        yesterday     = datetime.now() - timedelta(days=1)
        yesterday_str = yesterday.strftime("%Y-%m-%d")
 
        doc = (
            db.collection("dailyTasks")
              .document(user_id)
              .collection("tasks")
              .document(yesterday_str)
              .get()
        )
        if doc.exists:
            tid = doc.to_dict().get("id")
            print(f"   📅 Yesterday's task avoided: {doc.to_dict().get('title')} ({tid})")
            return tid
    except Exception as e:
        print(f"   ⚠️ Yesterday task error: {e}")
    return None
 
 
# ============================================================
# بناء ملف المستخدم
# ============================================================
def _build_user_profile(user_data: dict, task_prefs: dict) -> dict:
    level_id = user_data.get("userLevelId", "beginner")
    gender   = user_data.get("gender", "")
 
    if level_id == "beginner":
        level_label = "مبتدئ"
        level_tone  = "تشجيعي — مستخدم جديد يحتاج تحفيز"
    elif level_id == "medium":
        level_label = "متوسط"
        level_tone  = "إيجابي — مستخدم نشيط يستحق الإشادة"
    else:
        level_label = "متقدم"
        level_tone  = "احترافي — مستخدم ملتزم يقدّر التحدي"
 
    pronoun = "أنتِ" if gender == "female" else "أنت"
    suffix  = "ي"   if gender == "female" else ""
 
    # أفضل المهام من userTaskPreferences (score عالي)
    top_prefs = sorted(
        [{"id": k, **v} for k, v in task_prefs.items() if v.get("score", 0) > 3],
        key=lambda x: x.get("score", 0), reverse=True
    )[:5]
 
    # المهام المتجاهلة من userTaskPreferences
    ignored_prefs = [
        {"id": k, **v}
        for k, v in task_prefs.items()
        if v.get("ignored", 0) > v.get("completed", 0)
    ]
 
    # المهام المعروضة كثيراً بدون إنجاز (viewCount عالي + score منخفض)
    high_view_low_score = [
        k for k, v in task_prefs.items()
        if v.get("viewCount", 0) > 5 and v.get("score", 1) < 2
    ]
 
    streak = user_data.get("currentStreak", 0)
 
    return {
        "level_id":            level_id,
        "level_label":         level_label,
        "level_tone":          level_tone,
        "pronoun":             pronoun,
        "suffix":              suffix,
        "gender":              gender,
        "completed":           user_data.get("completedTask", 0),
        "streak":              streak,
        "points":              user_data.get("points", 0),
        "carbon_saved":        round(user_data.get("totalCarbonSaved", 0), 2),
        "top_prefs":           top_prefs,
        "ignored_prefs":       ignored_prefs[:3],
        "high_view_low_score": high_view_low_score[:5],
        "streak_text":         f"لديك {streak} يوم متتالي 🔥" if streak > 1 else "",
    }
 
 
# ============================================================
# بناء الـ Prompt
# ============================================================
def _build_daily_task_prompt(
    user_profile:    dict,
    candidate_tasks: list,
    top_task_ids:    list,
    task_prefs:      dict,
    ignored_ids:     set,
    pending_ids:     set,
    yesterday_id:    str | None,
) -> str:
 
    pronoun     = user_profile["pronoun"]
    suffix      = user_profile["suffix"]
    level_label = user_profile["level_label"]
    level_tone  = user_profile["level_tone"]
    streak_text = user_profile["streak_text"]
 
    # المفضلة من userTaskPreferences
    top_prefs_text = "\n".join([
        f"   • [{t['id']}] {t.get('title','')} (score: {t.get('score',0):.1f}, أُنجزت: {t.get('completed',0)})"
        for t in user_profile["top_prefs"]
    ]) or "   لا توجد"
 
    # المتجاهلة من userTaskPreferences
    ignored_prefs_text = "\n".join([
        f"   • [{t['id']}] {t.get('title','')} (تجاهل: {t.get('ignored',0)})"
        for t in user_profile["ignored_prefs"]
    ]) or "   لا توجد"
 
    # المعروضة كثيراً بدون إنجاز
    high_view_text = "\n".join([
        f"   • [{tid}]"
        for tid in user_profile["high_view_low_score"]
    ]) or "   لا توجد"
 
    # قائمة المهام المتاحة
    task_list_text = "\n".join([
        f"{i+1}. [{t['id']}] {t['title']} - {t['category']} "
        f"(score: {task_prefs.get(t['id'], {}).get('score', 1):.1f})"
        for i, t in enumerate(candidate_tasks)
    ])
 
    return f"""أنت مساعد بيئي ذكي. اختر مهمة يومية واحدة مناسبة لهذا المستخدم واكتب لها وصفاً شخصياً.
 
👤 ملف المستخدم:
- المستوى: {level_label} — {level_tone}
- الجنس: {user_profile['gender']} — خاطبه بـ "{pronoun}"
- المهام المكتملة: {user_profile['completed']}
- النقاط: {user_profile['points']}
- الكربون الموفَّر: {user_profile['carbon_saved']} كغ
{f"- {streak_text}" if streak_text else ""}
 
📊 تحليل userTaskPreferences:
 
⭐ المهام المفضلة (score عالي من userTaskPreferences):
{top_prefs_text}
 
🚫 المهام المتجاهلة (تجنبها):
{ignored_prefs_text}
 
👁️ مهام تُعرض كثيراً بدون إنجاز (تجنبها أيضاً):
{high_view_text}
 
📋 المهام المتاحة اليوم:
{task_list_text}
 
🎯 قواعد الاختيار (بالأولوية):
1. اختر من المهام المفضلة (score > 3 في userTaskPreferences) إن وجدت
2. تجنب المهام المتجاهلة والمعروضة كثيراً بدون إنجاز
3. لا تكرر نفس المهمة يوماً بعد يوم
4. وزّع الاختيار على تصنيفات مختلفة
 
✍️ قواعد الوصف الشخصي:
- خاطب المستخدم بـ "{pronoun}" دائماً
- إذا المستوى "مبتدئ" → حفز للبداية: "{pronoun} في بداية رحلتك..."
- إذا المستوى "متوسط" → أشِد بتقدمه: "واصل{suffix} مسيرتك..."
- إذا المستوى "متقدم" → تحدّه: "بطل{suffix} البيئة، تحدٍّ جديد..."
{f'- اذكر الـ streak: "حافظ{suffix} على سلسلتك!"' if streak_text else ""}
- 15-20 كلمة فقط، مختلف عن الوصف الأصلي
 
أرجع JSON فقط:
{{
  "taskId": "معرف المهمة من القائمة",
  "reasoning": "سبب الاختيار بإيجاز",
  "personalizedDescription": "وصف شخصي دافئ يراعي مستوى المستخدم"
}}"""
 
 
# ============================================================
# Fallback: اختيار المهمة بدون Gemini
# ============================================================
def _fallback_select(
    candidate_tasks: list,
    top_task_ids:    list,
    task_prefs:      dict,
    user_profile:    dict,
) -> tuple:
    """يرجع (task, description) أو (None, '')"""
 
    suffix      = user_profile["suffix"]
    pronoun     = user_profile["pronoun"]
    level_label = user_profile["level_label"]
 
    # 1. من topTasks في userTaskPreferences
    for tid in top_task_ids:
        task = next((t for t in candidate_tasks if t["id"] == tid), None)
        if task:
            print(f"   ✅ Fallback: selected from topTasks: {task['title']}")
            return task, _build_fallback_desc(task, user_profile)
 
    # 2. الأعلى score في userTaskPreferences
    scored = sorted(
        candidate_tasks,
        key=lambda t: task_prefs.get(t["id"], {}).get("score", 1),
        reverse=True
    )
    if scored:
        task = scored[0]
        print(f"   ✅ Fallback: selected by score: {task['title']}")
        return task, _build_fallback_desc(task, user_profile)
 
    # 3. عشوائي
    if candidate_tasks:
        import random
        task = random.choice(candidate_tasks)
        print(f"   ✅ Fallback: random: {task['title']}")
        return task, _build_fallback_desc(task, user_profile)
 
    return None, ""
 
 
def _build_fallback_desc(task: dict, profile: dict) -> str:
    pronoun     = profile["pronoun"]
    suffix      = profile["suffix"]
    level_label = profile["level_label"]
    streak_text = profile["streak_text"]
 
    if level_label == "مبتدئ":
        base = f"🌱 {pronoun} في بداية رحلتك البيئية! {task['title']} خطوة رائعة للانطلاق 🚀"
    elif level_label == "متوسط":
        base = f"⭐ واصل{suffix} تقدمك! {task['title']} تضيف نقاطاً لرصيدك البيئي 💚"
    else:
        base = f"🏆 تحدٍّ جديد يا بطل{suffix} البيئة! {task['title']} في انتظارك ✨"
 
    if streak_text:
        base += f" حافظ{suffix} على سلسلتك 🔥"
 
    return base
 
 
# ============================================================
# تحديث viewCount في userTaskPreferences
# ============================================================
def _update_view_count(user_id: str, task: dict) -> None:
    try:
        prefs_ref = db.collection("userTaskPreferences").document(user_id)
        prefs_doc = prefs_ref.get()
        if prefs_doc.exists:
            prefs_ref.update({
                f"taskPreferences.{task['id']}.viewCount":    firestore.Increment(1),
                f"taskPreferences.{task['id']}.lastViewedAt": firestore.SERVER_TIMESTAMP,
                f"taskPreferences.{task['id']}.title":        task.get("title", ""),
                f"taskPreferences.{task['id']}.category":     task.get("category", ""),
            })
            print(f"   👁️ Updated viewCount for: {task['title']}")
    except Exception as e:
        print(f"   ⚠️ viewCount update error: {e}")
 
 
# ============================================================
# HTTP Entry Point — أيجنت المهام اليومية
# ============================================================
@functions_framework.http
def generate_daily_tasks_agent(request):
    if request.method == "OPTIONS":
        return ("", 204, {
            "Access-Control-Allow-Origin":  "*",
            "Access-Control-Allow-Methods": "POST, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type, Authorization"
        })
 
    if request.method != "POST":
        return (json.dumps({"error": "POST only"}), 405,
                {"Content-Type": "application/json"})
 
    try:
        data   = request.get_json(silent=True) or {}
        result = run_daily_task_agent(data)
        status = 200 if "error" not in result else 500
 
        return (
            json.dumps(result, ensure_ascii=False, default=str),
            status,
            {
                "Content-Type":                "application/json; charset=utf-8",
                "Access-Control-Allow-Origin": "*"
            }
        )
    except Exception as e:
        import traceback
        traceback.print_exc()
        return (
            json.dumps({"error": str(e)}, ensure_ascii=False),
            500,
            {"Content-Type": "application/json"}
        )

###########################################################
# ============================================================
# أيجنت الإدمن
# ============================================================

def run_admin_agent(data: dict) -> dict:
    admin_id = data.get("adminId")
    if not admin_id:
        return {"error": "adminId مطلوب"}
 
    print("🔍 Admin Agent Starting...")
    context = {}
 
    # ── Step 1: إحصائيات المهام ─────────────────────────────
    print("📊 Step 1: Getting task analytics...")
    get_admin_task_analytics(context)
 
    # ── Step 2: البلاغات ────────────────────────────────────
    print("🚨 Step 2: Getting reports...")
    get_admin_reports(context)
 
    # ── Step 3: بيانات المستخدمين ───────────────────────────
    print("👥 Step 3: Getting user insights...")
    get_admin_user_insights(context)
 
    # ── Step 4: الأنماط الموسمية ────────────────────────────
    print("📅 Step 4: Analyzing seasonal patterns...")
    get_seasonal_patterns(context)
 
    # ── Step 5: الموسم الحالي ───────────────────────────────
    print("🌍 Step 5: Getting season context...")
    season = get_season_context()
 
    # ── Step 6: بناء الـ Prompt واستدعاء Gemini ─────────────
    print("🤖 Step 6: Building prompt and calling Gemini...")
    prompt = build_admin_prompt(context, season)
    gemini_response = call_gemini(prompt, temperature=0.7, max_tokens=2500)
 
    recommendations = []
    if gemini_response:
        parsed = extract_json(gemini_response)
        if parsed:
            if isinstance(parsed, list):
                recommendations = parsed
            elif parsed.get("recommendations"):
                recommendations = parsed["recommendations"]
        print(f"✅ Gemini generated {len(recommendations)} recommendations")
 
    # ── Fallback ────────────────────────────────────────────
    if not recommendations:
        print("⚠️ Using fallback recommendations...")
        recommendations = build_fallback_recommendations(context, season)
 
    # ── Step 7: حفظ في Firestore ────────────────────────────
    print("💾 Step 7: Saving to Firestore...")
    current_month = datetime.now().strftime("%Y-%m")
    try:
        db.collection("adminRecommendations").document(current_month).set({
            "month":           current_month,
            "season":          season,
            "recommendations": recommendations[:12],
            "summary":         context.get("summary", {}),
            "analytics":       context.get("analytics", {}),
            "generatedAt":     firestore.SERVER_TIMESTAMP,
        })
        print("✅ Saved to Firestore")
    except Exception as e:
        print(f"⚠️ Save failed: {e}")

    # ── Step 8: التطبيق التلقائي إذا autoAgentMode = true ───
    print("🔄 Step 8: Checking autoAgentMode...")
    auto_mode    = False
    auto_results = {"applied": 0, "skipped": 0}
    try:
        admin_doc = db.collection("users").document(admin_id).get()
        auto_mode = admin_doc.to_dict().get("autoAgentMode", False) if admin_doc.exists else False

        if auto_mode:
            print("🤖 Auto Agent Mode ON — تطبيق التوصيات تلقائياً...")
            auto_results = _apply_recommendations_automatically(recommendations[:12])
            print(f"✅ Auto-applied: {auto_results['applied']} | Skipped: {auto_results['skipped']}")
        else:
            print("👤 Auto Agent Mode OFF — التوصيات للمراجعة اليدوية فقط")
    except Exception as e:
        print(f"⚠️ autoAgentMode check failed: {e}")

    # ── Step 9: تحديث هدف الكربون تلقائياً ─────────────────
    print("🎯 Step 9: Updating carbon target...")
    carbon_target_result = {"updated": False}
    if auto_mode:
        try:
            carbon_target_result = _update_carbon_target(context, season)
        except Exception as e:
            print(f"⚠️ Carbon target update failed: {e}")
    else:
        print("   ⏭️ Skipped (autoAgentMode is OFF)")
 
    return {
        "month":           current_month,
        "season":          season,
        "recommendations": recommendations[:12],
        "summary":         context.get("summary", {}),
        "autoApplied":     auto_results,
        "carbonTarget":    carbon_target_result,
    }


# ============================================================
# Step 8: التطبيق التلقائي للتوصيات
# ============================================================
def _apply_recommendations_automatically(recommendations: list) -> dict:
    applied = 0
    skipped = 0
    now     = datetime.now()
    next_month_dt = datetime(now.year, now.month + 1, 1) if now.month < 12 else datetime(now.year + 1, 1, 1)
    next_month    = next_month_dt.strftime("%Y-%m")

    for rec in recommendations:
        rec_type = rec.get("type", "")

        try:
            if rec_type == "add":
                title = rec.get("title", "").strip()
                if not title:
                    print(f"   ⚠️ Skipped add: no title")
                    skipped += 1
                    continue

                existing = db.collection("tasks") \
                    .where("title", "==", title) \
                    .limit(1) \
                    .get()

                if len(list(existing)) > 0:
                    print(f"   ⚠️ Skipped add (duplicate): {title}")
                    skipped += 1
                    continue

                validation = rec.get("validationStrategy") or \
                             pick_validation_strategy(title, rec.get("userDescription", ""))

                db.collection("tasks").add({
                    "title":              title,
                    "title_normalized":   title.strip().lower(),
                    "description":        rec.get("userDescription") or rec.get("description", ""),
                    "category":           rec.get("category", ""),
                    "validationStrategy": validation,
                    "points":             rec.get("points", 10),
                    "status":             "active",
                    "visible_from":       next_month,
                    "calcMode":           "perItem",
                    "autoGenerated":      True,
                    "generatedAt":        firestore.SERVER_TIMESTAMP,
                })
                print(f"   ✅ Auto-added task: {title}")
                applied += 1

            elif rec_type == "modify":
                task_id       = rec.get("taskId", "").strip()
                improved_desc = rec.get("improvedDescription", "").strip()

                if not task_id or not improved_desc:
                    print(f"   ⚠️ Skipped modify: missing taskId or improvedDescription")
                    skipped += 1
                    continue

                task_doc = db.collection("tasks").document(task_id).get()
                if not task_doc.exists:
                    print(f"   ⚠️ Skipped modify: task {task_id} not found")
                    skipped += 1
                    continue

                db.collection("tasks").document(task_id).update({
                    "description":    improved_desc,
                    "autoModified":   True,
                    "lastModifiedAt": firestore.SERVER_TIMESTAMP,
                })
                print(f"   ✅ Auto-modified task: {task_id}")
                applied += 1

            elif rec_type in ["review_reports", "delete"]:
                print(f"   ⏭️ Skipped {rec_type} (requires human decision)")
                skipped += 1

            else:
                skipped += 1

        except Exception as e:
            print(f"   ❌ Auto-apply error for {rec_type}: {e}")
            skipped += 1

    return {"applied": applied, "skipped": skipped}

# ============================================================
# Step 9: تحديث هدف الكربون تلقائياً
# ============================================================
def _update_carbon_target(context: dict, season: dict) -> dict:
    try:
        insights = context.get("user_insights", {})
        seasonal = context.get("seasonal_patterns", {})

        total_users  = max(insights.get("totalUsers", 1), 1)

        # ── جلب كربون هذا الشهر فقط (تراكمي شهري) ──────────
        now           = datetime.now()
        current_month = now.strftime("%Y-%m")
        month_start   = datetime(now.year, now.month, 1)
        month_end     = datetime(now.year, now.month + 1, 1) if now.month < 12 else datetime(now.year + 1, 1, 1)

        monthly_carbon = 0.0
        try:
            from google.cloud.firestore_v1 import FieldFilter
            for doc in db.collection("submissions")\
                .where(filter=FieldFilter("status", "==", "approved"))\
                .where(filter=FieldFilter("createdAt", ">=", month_start))\
                .where(filter=FieldFilter("createdAt", "<", month_end))\
                .stream():
                monthly_carbon += doc.to_dict().get("carbonSaved", 0) or 0
        except Exception as e:
            print(f"   ⚠️ Could not fetch monthly carbon from submissions, using totalCarbon: {e}")
            # fallback: استخدم الإجمالي من users
            monthly_carbon = insights.get("totalCarbon", 0.0)

        monthly_carbon = round(monthly_carbon, 2)
        avg_carbon     = round(monthly_carbon / total_users, 2)

        print(f"   📅 Monthly carbon ({current_month}): {monthly_carbon} kg | Avg per user: {avg_carbon} kg")

        # ── جلب الهدف الحالي من Firestore ───────────────────
        settings_doc   = db.collection("appSettings").document("carbonTarget").get()
        current_target = 50.0

        if settings_doc.exists:
            current_target = float(settings_doc.to_dict().get("target", 50.0))

        # ── جلب كربون نفس الشهر السنة الماضية ───────────────
        last_year_month = seasonal.get("lastYearSameMonth", "")
        last_year_avg   = 0.0

        try:
            last_year_doc = db.collection("appSettings").document(
                f"carbonTarget_{last_year_month}"
            ).get()
            if last_year_doc.exists:
                last_year_avg = float(last_year_doc.to_dict().get("avgCarbon", 0.0))
                print(f"   📅 Last year same month avg: {last_year_avg} kg")
        except Exception as e:
            print(f"   ⚠️ Could not fetch last year data: {e}")

        # ── حساب الهدف الجديد ────────────────────────────────
        performance_ratio = avg_carbon / current_target if current_target > 0 else 0

        new_target = current_target
        reason     = ""
        direction  = "unchanged"

        if performance_ratio >= 0.8:
            new_target = round(current_target * 1.20, 1)
            reason     = (
                f"متوسط الكربون الشهري ({avg_carbon} كجم/مستخدم) وصل {round(performance_ratio*100)}% "
                f"من الهدف ({current_target} كجم) → رفع الهدف 20%"
            )
            direction = "up"

        elif performance_ratio < 0.4:
            new_target = round(current_target * 0.85, 1)
            reason     = (
                f"متوسط الكربون الشهري ({avg_carbon} كجم/مستخدم) فقط {round(performance_ratio*100)}% "
                f"من الهدف ({current_target} كجم) → خفض الهدف 15%"
            )
            direction = "down"

        else:
            reason    = (
                f"الأداء الشهري مقبول ({round(performance_ratio*100)}%) "
                f"— الهدف يبقى {current_target} كجم"
            )
            direction = "unchanged"

        # ── تأثير الموسم ─────────────────────────────────────
        season_name = season.get("season", "")
        if season_name == "الصيف" and direction == "unchanged":
            new_target = round(current_target * 0.92, 1)
            reason    += f" | موسم الصيف → تخفيض طفيف 8%"
            direction  = "down"
        elif season_name == "الربيع" and direction == "unchanged":
            new_target = round(current_target * 1.05, 1)
            reason    += f" | موسم الربيع → رفع طفيف 5%"
            direction  = "up"

        # ── مقارنة بالسنة الماضية ────────────────────────────
        if last_year_avg > 0:
            year_change_pct = ((avg_carbon - last_year_avg) / last_year_avg) * 100
            if year_change_pct > 30:
                bonus = round(current_target * 0.10, 1)
                new_target = round(new_target + bonus, 1)
                reason += (
                    f" | أداء أفضل {round(year_change_pct)}% من {last_year_month} "
                    f"→ إضافة {bonus} كجم للهدف"
                )
            elif year_change_pct < -30:
                penalty = round(current_target * 0.08, 1)
                new_target = round(new_target - penalty, 1)
                reason += (
                    f" | أداء أضعف {round(abs(year_change_pct))}% من {last_year_month} "
                    f"→ خفض {penalty} كجم من الهدف"
                )

        # ── حد أدنى وأقصى ────────────────────────────────────
        new_target = max(5.0, min(new_target, 500.0))

        print(f"   📊 Monthly avg: {avg_carbon} kg | Current target: {current_target} | New target: {new_target}")
        print(f"   💡 Reason: {reason}")
        print(f"   📈 Direction: {direction}")

        # ── حفظ الهدف الجديد ─────────────────────────────────
        db.collection("appSettings").document("carbonTarget").set({
            "target":           new_target,
            "prevTarget":       current_target,
            "avgCarbon":        avg_carbon,          # متوسط شهري لكل مستخدم
            "monthlyCarbon":    monthly_carbon,      # إجمالي كربون الشهر
            "totalUsers":       total_users,
            "performanceRatio": round(performance_ratio * 100, 1),
            "reason":           reason,
            "direction":        direction,
            "season":           season_name,
            "month":            current_month,
            "lastYearMonth":    last_year_month,
            "lastYearAvg":      last_year_avg,
            "updatedAt":        firestore.SERVER_TIMESTAMP,
            "updatedBy":        "autoAgent",
        })

        # ── حفظ سجل تاريخي شهري ──────────────────────────────
        db.collection("appSettings").document(f"carbonTarget_{current_month}").set({
            "target":        new_target,
            "avgCarbon":     avg_carbon,
            "monthlyCarbon": monthly_carbon,
            "month":         current_month,
            "season":        season_name,
            "savedAt":       firestore.SERVER_TIMESTAMP,
        })

        print(f"   ✅ Carbon target updated: {current_target} → {new_target} kg")

        return {
            "updated":        True,
            "prevTarget":     current_target,
            "newTarget":      new_target,
            "avgCarbon":      avg_carbon,
            "monthlyCarbon":  monthly_carbon,
            "direction":      direction,
            "reason":         reason,
            "lastYearAvg":    last_year_avg,
            "lastYearMonth":  last_year_month,
        }

    except Exception as e:
        print(f"   ❌ Carbon target update error: {e}")
        return {"updated": False, "error": str(e)}

# ============================================================
# Step 1: تحليل أداء المهام
# ============================================================
def get_admin_task_analytics(context: dict) -> dict:
    active_tasks = []
    try:
        for doc in db.collection("tasks").where("status", "==", "active").stream():
            t = doc.to_dict()
            active_tasks.append({
                "id":          doc.id,
                "title":       t.get("title", ""),
                "description": t.get("description", ""),
                "category":    t.get("category", ""),
                "points":      t.get("points", 0),
            })
    except Exception as e:
        print(f"⚠️ active tasks error: {e}")
 
    completed_count = {}
    ignored_count   = {}
    try:
        for doc in db.collection("userTasks").where("status", "==", "completed").stream():
            tid = doc.to_dict().get("taskId")
            if tid:
                completed_count[tid] = completed_count.get(tid, 0) + 1
 
        for doc in db.collection("userTasks").where("ignored", "==", True).stream():
            tid = doc.to_dict().get("taskId")
            if tid:
                ignored_count[tid] = ignored_count.get(tid, 0) + 1
    except Exception as e:
        print(f"⚠️ task stats error: {e}")
 
    most_successful = sorted(
        [{"id": k, "count": v,
          "title":       next((t["title"]       for t in active_tasks if t["id"] == k), k),
          "description": next((t["description"] for t in active_tasks if t["id"] == k), ""),
          "category":    next((t["category"]    for t in active_tasks if t["id"] == k), "")}
         for k, v in completed_count.items()],
        key=lambda x: x["count"], reverse=True
    )[:5]
 
    most_ignored = sorted(
        [{"id": k, "count": v,
          "title":       next((t["title"]       for t in active_tasks if t["id"] == k), k),
          "description": next((t["description"] for t in active_tasks if t["id"] == k), ""),
          "category":    next((t["category"]    for t in active_tasks if t["id"] == k), "")}
         for k, v in ignored_count.items()],
        key=lambda x: x["count"], reverse=True
    )[:5]
 
    completed_ids   = set(completed_count.keys())
    zero_completion = [t for t in active_tasks if t["id"] not in completed_ids]
 
    summary = {
        "totalActiveTasks":    len(active_tasks),
        "zeroCompletionTasks": len(zero_completion),
        "mostSuccessful":      most_successful,
        "mostIgnored":         most_ignored,
        "zeroTasks":           zero_completion[:5],
    }
 
    context["task_analytics"] = summary
    context["summary"] = {
        "totalTasks":          len(active_tasks),
        "zeroCompletionTasks": len(zero_completion),
    }
 
    print(f"   📋 Active: {len(active_tasks)} | Zero: {len(zero_completion)} | Ignored: {len(most_ignored)}")
    return summary
 
 
# ============================================================
# Step 2: تحليل البلاغات
# ============================================================
def get_admin_reports(context: dict) -> dict:
    task_reports      = []
    container_reports = []
 
    try:
        for doc in db.collection("taskReports").where("decision", "==", "pending").stream():
            d = doc.to_dict()
            task_reports.append({
                "taskId": d.get("taskId", ""),
                "reason": d.get("reason", ""),
            })
    except Exception as e:
        print(f"⚠️ task reports error: {e}")
 
    try:
        for doc in db.collection("facilityReports").where("status", "==", "pending").stream():
            d = doc.to_dict()
            container_reports.append({
                "facilityId": d.get("facilityID", ""),
                "type":       d.get("type", ""),
            })
    except Exception as e:
        print(f"⚠️ facility reports error: {e}")
 
    task_report_count = {}
    for r in task_reports:
        tid = r["taskId"]
        if tid:
            if tid not in task_report_count:
                task_report_count[tid] = {"count": 0, "reasons": []}
            task_report_count[tid]["count"] += 1
            if r["reason"]:
                task_report_count[tid]["reasons"].append(r["reason"])
 
    facility_report_count = {}
    for r in container_reports:
        fid = r["facilityId"]
        if fid:
            if fid not in facility_report_count:
                facility_report_count[fid] = {"count": 0, "types": []}
            facility_report_count[fid]["count"] += 1
            if r["type"]:
                facility_report_count[fid]["types"].append(r["type"])
 
    problematic_tasks = []
    for tid, data in sorted(task_report_count.items(), key=lambda x: x[1]["count"], reverse=True)[:5]:
        try:
            doc = db.collection("tasks").document(tid).get()
            if doc.exists:
                t = doc.to_dict()
                problematic_tasks.append({
                    "taskId":      tid,
                    "title":       t.get("title", ""),
                    "description": t.get("description", ""),
                    "reportCount": data["count"],
                    "reasons":     list(set(data["reasons"]))[:3],
                })
        except:
            pass
 
    problematic_facilities = []
    for fid, data in sorted(facility_report_count.items(), key=lambda x: x[1]["count"], reverse=True)[:5]:
        try:
            doc = db.collection("facilities").document(fid).get()
            if doc.exists:
                f = doc.to_dict()
                types = data["types"]
                type_count = {}
                for t in types:
                    type_count[t] = type_count.get(t, 0) + 1
                main_issue = max(type_count, key=type_count.get) if type_count else ""
                problematic_facilities.append({
                    "facilityId":  fid,
                    "name":        f.get("type", "حاوية"),
                    "address":     f.get("address", ""),
                    "reportCount": data["count"],
                    "mainIssue":   main_issue,
                })
        except:
            pass
 
    reports = {
        "pendingTaskReports":     len(task_reports),
        "pendingFacilityReports": len(container_reports),
        "problematicTasks":       problematic_tasks,
        "problematicFacilities":  problematic_facilities,
    }
 
    context["reports"] = reports
    context["summary"]["pendingReports"] = len(task_reports) + len(container_reports)
    context["analytics"] = {
        "problematicTasks":      problematic_tasks,
        "problematicFacilities": problematic_facilities,
    }
 
    print(f"   🚨 Task reports: {len(task_reports)} | Facility reports: {len(container_reports)}")
    return reports
 
 
# ============================================================
# Step 3: تحليل بيانات المستخدمين
# ============================================================
def get_admin_user_insights(context: dict) -> dict:
    total_users  = 0
    level_counts = {"beginner": 0, "medium": 0, "hard": 0}
    total_points = 0
    total_carbon = 0.0
 
    try:
        for doc in db.collection("users").stream():
            d = doc.to_dict()
            if d.get("role") == "admin":
                continue
            total_users  += 1
            level = d.get("userLevelId", "beginner")
            if level in level_counts:
                level_counts[level] += 1
            total_points += d.get("points", 0)
            total_carbon += d.get("totalCarbonSaved", 0)
    except Exception as e:
        print(f"⚠️ user insights error: {e}")
 
    insights = {
        "totalUsers":  total_users,
        "levelCounts": level_counts,
        "avgPoints":   round(total_points / max(total_users, 1), 1),
        "totalCarbon": round(total_carbon, 2),
    }
 
    context["user_insights"] = insights
    context["summary"]["totalUsers"] = total_users
    print(f"   👥 Users: {total_users} | Carbon: {total_carbon:.2f} kg")
    return insights
 
 
# ============================================================
# Step 4: الأنماط الموسمية (السنة الماضية)
# ============================================================
def get_seasonal_patterns(context: dict) -> dict:
    from datetime import timedelta
 
    now          = datetime.now()
    one_year_ago = now - timedelta(days=365)
    monthly_category_stats = {}
 
    try:
        for doc in db.collection("userTasks").where("status", "==", "completed").stream():
            d            = doc.to_dict()
            completed_at = d.get("completedAt")
            category     = d.get("category", "") or d.get("taskCategory", "")
 
            if not completed_at or not category:
                continue
 
            try:
                if hasattr(completed_at, "todate"):
                    dt = completed_at.todate()
                elif hasattr(completed_at, "_seconds"):
                    dt = datetime.fromtimestamp(completed_at._seconds)
                elif hasattr(completed_at, "timestamp"):
                    dt = datetime.fromtimestamp(completed_at.timestamp())
                else:
                    continue
            except:
                continue
 
            if dt < one_year_ago:
                continue
 
            month_key = dt.strftime("%Y-%m")
            if month_key not in monthly_category_stats:
                monthly_category_stats[month_key] = {}
            monthly_category_stats[month_key][category] = \
                monthly_category_stats[month_key].get(category, 0) + 1
 
    except Exception as e:
        print(f"⚠️ seasonal patterns error: {e}")
 
    last_year_same_month = f"{now.year - 1}-{now.month:02d}"
    current_month_key    = now.strftime("%Y-%m")
 
    last_year_data = monthly_category_stats.get(last_year_same_month, {})
    current_data   = monthly_category_stats.get(current_month_key, {})
 
    top_category_last_year = ""
    top_category_count     = 0
    if last_year_data:
        top_category_last_year = max(last_year_data, key=last_year_data.get)
        top_category_count     = last_year_data[top_category_last_year]
 
    trends = []
    all_categories = set(list(last_year_data.keys()) + list(current_data.keys()))
    for category in all_categories:
        last_year_count = last_year_data.get(category, 0)
        current_count   = current_data.get(category, 0)
 
        if last_year_count == 0:
            continue
 
        change_pct = ((current_count - last_year_count) / last_year_count) * 100
 
        if change_pct > 20:
            trends.append({
                "category": category,
                "trend":    "ارتفاع",
                "change":   f"+{change_pct:.0f}%",
                "message":  f"نشاط '{category}' ارتفع {change_pct:.0f}% مقارنة بنفس الشهر العام الماضي",
                "action":   "add"
            })
        elif change_pct < -20:
            trends.append({
                "category": category,
                "trend":    "انخفاض",
                "change":   f"{change_pct:.0f}%",
                "message":  f"نشاط '{category}' انخفض {abs(change_pct):.0f}% مقارنة العام الماضي — يحتاج مهام تنشيطية",
                "action":   "add_or_modify"
            })
 
    monthly_totals = {
        month: sum(cats.values())
        for month, cats in monthly_category_stats.items()
    }
    peak_months = sorted(monthly_totals.items(), key=lambda x: x[1], reverse=True)[:3]
 
    patterns = {
        "lastYearSameMonth":      last_year_same_month,
        "topCategoryLastYear":    top_category_last_year,
        "topCategoryCount":       top_category_count,
        "currentMonthVsLastYear": trends,
        "peakMonths":             [m[0] for m in peak_months],
        "suggestion": (
            f"في {last_year_same_month}، كان '{top_category_last_year}' الأكثر نشاطاً "
            f"({top_category_count} إنجاز) — اقترح مهام مشابهة هذا الشهر"
            if top_category_last_year else ""
        )
    }
 
    context["seasonal_patterns"] = patterns
    print(f"   📅 Top last year ({last_year_same_month}): {top_category_last_year} ({top_category_count})")
    print(f"   📈 Trends: {len(trends)} | Peak months: {[m[0] for m in peak_months]}")
    return patterns
 
 
# ============================================================
# Step 5: الموسم الحالي
# ============================================================
def get_season_context() -> dict:
    month = datetime.now().month
    if month in [3, 4, 5]:   return {"season": "الربيع",  "emoji": "🌸"}
    if month in [6, 7, 8]:   return {"season": "الصيف",   "emoji": "☀️"}
    if month in [9, 10, 11]: return {"season": "الخريف",  "emoji": "🍂"}
    return {"season": "الشتاء", "emoji": "❄️"}
 
 
# ============================================================
# Step 6: بناء الـ Prompt
# ============================================================
def build_admin_prompt(context: dict, season: dict) -> str:
    analytics = context.get("task_analytics", {})
    reports   = context.get("reports", {})
    insights  = context.get("user_insights", {})
    seasonal  = context.get("seasonal_patterns", {})
 
    successful_text = "\n".join([
        f"   • [{t['id']}] {t['title']} — أُنجزت {t['count']} مرة\n"
        f"     الوصف الحالي: {t.get('description','')[:80]}"
        for t in analytics.get("mostSuccessful", [])
    ]) or "   لا توجد بيانات"
 
    ignored_text = "\n".join([
        f"   • [{t['id']}] {t['title']} — تم تجاهلها {t['count']} مرة\n"
        f"     الوصف الحالي: {t.get('description','')[:80]}"
        for t in analytics.get("mostIgnored", [])
    ]) or "   لا توجد بيانات"
 
    zero_text = "\n".join([
        f"   • [{t['id']}] {t['title']}\n"
        f"     الوصف الحالي: {t.get('description','')[:80]}"
        for t in analytics.get("zeroTasks", [])
    ]) or "   لا توجد"
 
    task_reports_text = "\n".join([
        f"   • [{t['taskId']}] {t['title']}: {t['reportCount']} بلاغ\n"
        f"     الأسباب: {', '.join(t['reasons'][:2])}\n"
        f"     الوصف الحالي: {t.get('description','')[:80]}"
        for t in reports.get("problematicTasks", [])
    ]) or "   لا توجد بلاغات متكررة"
 
    facility_reports_text = "\n".join([
        f"   • {f['name']} ({f['address']}): {f['reportCount']} بلاغ — {f['mainIssue']}"
        for f in reports.get("problematicFacilities", [])
    ]) or "   لا توجد بلاغات متكررة"
 
    trends_text = "\n".join([
        f"   • {t['message']}"
        for t in seasonal.get("currentMonthVsLastYear", [])
    ]) or "   لا توجد أنماط واضحة بعد"
 
    top_last_year       = seasonal.get("topCategoryLastYear", "")
    last_year_month     = seasonal.get("lastYearSameMonth", "")
    peak_months         = ", ".join(seasonal.get("peakMonths", []))
    seasonal_suggestion = seasonal.get("suggestion", "")
 
    return f"""أنت مستشار بيئي ذكي ومتخصص في تحسين تجربة المستخدم. بناءً على البيانات التالية، قدم 5 توصيات عملية للإدمن.
 
🌍 الموسم الحالي: {season['season']} {season['emoji']}
 
📊 أداء المهام:
- إجمالي المهام النشطة: {analytics.get('totalActiveTasks', 0)}
- مهام بدون إنجازات: {analytics.get('zeroCompletionTasks', 0)}
 
✅ المهام الأكثر نجاحاً:
{successful_text}
 
🚫 المهام الأكثر تجاهلاً (تحتاج تحسين صياغة):
{ignored_text}
 
⚪ مهام بدون إنجازات (تحتاج إعادة صياغة كاملة):
{zero_text}
 
🚨 البلاغات المعلقة:
- بلاغات مهام: {reports.get('pendingTaskReports', 0)}
- بلاغات حاويات: {reports.get('pendingFacilityReports', 0)}
 
مهام بلاغات متكررة:
{task_reports_text}
 
حاويات بلاغات متكررة:
{facility_reports_text}
 
👥 المستخدمون:
- الإجمالي: {insights.get('totalUsers', 0)}
- مبتدئ: {insights.get('levelCounts', {}).get('beginner', 0)}
- متوسط: {insights.get('levelCounts', {}).get('medium', 0)}
- متقدم: {insights.get('levelCounts', {}).get('hard', 0)}
- متوسط النقاط: {insights.get('avgPoints', 0)}
- كربون موفَّر: {insights.get('totalCarbon', 0)} كغ
 
📅 الأنماط الموسمية (مقارنة بـ {last_year_month}):
- أكثر تصنيف نشاطاً العام الماضي في هذا الشهر: {top_last_year or 'لا توجد بيانات'}
- {seasonal_suggestion}
- أشهر الذروة العام الماضي: {peak_months or 'لا توجد بيانات'}
 
التغيرات مقارنة العام الماضي:
{trends_text}
 
🎯 قواعد التوصيات (بالأولوية):
1. مهام بدون إنجازات → اقترح إعادة صياغة وصفها (modify) مع كتابة وصف جديد محفز
2. مهام كثيرة التجاهل → اقترح تحسين صياغتها (modify) مع وصف أكثر جاذبية
3. مهام/حاويات بلاغات متكررة → اقترح مراجعتها (review_reports)
4. تصنيف كان نشطاً العام الماضي → اقترح مهام مشابهة (add)
5. تصنيف انخفض نشاطه → اقترح مهام تنشيطية (add أو modify)
6. الموسم الحالي → اقترح مهام جديدة مناسبة (add)
 
✍️ قواعد كتابة improvedDescription (للتوصيات من نوع modify):
- مختلف تماماً عن الوصف الأصلي
- محفز وشخصي — يخاطب المستخدم بـ "أنت"
- يذكر الفائدة البيئية الفعلية
- قصير: 15-20 كلمة فقط
- يستخدم لغة دافئة وإيجابية
- مثال جيد: "أنت تصنع فرقاً! ضع بقايا طعامك في الحاوية وحوّلها لسماد يغذي الأرض 🌱"
- مثال سيء: "قم بوضع بقايا الطعام في الحاوية المخصصة للتخلص منها"
 
✍️ قواعد كتابة userDescription (للتوصيات من نوع add):
- هذا وصف المهمة الجديدة كما سيراه المستخدم في التطبيق مباشرة
- يشرح بوضوح ما يجب فعله
- محفز وشخصي — يخاطب المستخدم بـ "أنت"
- يذكر الفائدة البيئية الفعلية للمهمة
- قصير: 15-25 كلمة فقط
 
🔍 قواعد اختيار validationStrategy (للتوصيات من نوع add فقط):
- "التحقق عبر معالجة الصور" → للمهام التي يمكن إثباتها بصورة
- "التحقق عبر اجراء اختبار قصير" → للمهام المعرفية والتوعوية
 
أرجع JSON فقط بهذا الشكل:
{{
  "recommendations": [
    {{
      "type": "add | modify | review_reports",
      "category": "اسم التصنيف",
      "title": "عنوان التوصية",
      "description": "شرح المشكلة وسببها للإدمن",
      "suggestion": "الإجراء المقترح",
      "basedOn": "سبب التوصية مع البيانات الفعلية",
      "taskId": "معرف المهمة إن وجد",
      "improvedDescription": "وصف محسن جاهز للنشر في التطبيق (للتوصيات من نوع modify فقط)",
      "userDescription": "وصف المهمة الجديدة جاهز لليوزر مباشرة (للتوصيات من نوع add فقط)",
      "validationStrategy": "التحقق عبر معالجة الصور أو التحقق عبر اجراء اختبار قصير (للتوصيات من نوع add فقط)",
      "facilityId": "معرف الحاوية إن وجد",
      "facilityName": "اسم الحاوية إن وجد",
      "facilityAddress": "عنوان الحاوية إن وجد",
      "reportCount": 0
    }}
  ]
}}"""
 
 
# ============================================================
# دالة مساعدة لتحديد validationStrategy تلقائياً
# ============================================================
def pick_validation_strategy(title: str, description: str = "") -> str:
    text = (title + " " + description).lower()
 
    visual_keywords = [
        "تدوير", "فرز", "حاوية", "نفايات", "قمامة", "مخلفات",
        "مشي", "دراجة", "باص", "مترو", "نقل", "سيارة",
        "زراعة", "نبات", "شجرة", "غرس",
        "طعام", "سماد", "بقايا",
        "كهرباء", "ماء", "صنبور", "إضاءة",
        "تسوق", "أكياس", "بلاستيك", "ورق", "زجاج",
        "recycl", "walk", "bus", "bike", "plant"
    ]
 
    knowledge_keywords = [
        "اقرأ", "تعلم", "اطلع", "توعية", "معلومات", "مقال",
        "ارشادات", "نصائح", "وعي", "ثقافة", "معرفة",
        "شاهد", "استمع", "بودكاست", "فيديو تعليمي",
        "read", "learn", "awareness", "quiz", "article"
    ]
 
    visual_score    = sum(1 for kw in visual_keywords    if kw in text)
    knowledge_score = sum(1 for kw in knowledge_keywords if kw in text)
 
    if knowledge_score > visual_score:
        return "التحقق عبر اجراء اختبار قصير"
    return "التحقق عبر معالجة الصور"
 
 
# ============================================================
# Fallback توصيات
# ============================================================
def build_fallback_recommendations(context: dict, season: dict) -> list:
    recs      = []
    analytics = context.get("task_analytics", {})
    reports   = context.get("reports", {})
    seasonal  = context.get("seasonal_patterns", {})
 
    for task in analytics.get("zeroTasks", [])[:2]:
        recs.append({
            "type":                "modify",
            "category":            task.get("category", "غير محدد"),
            "title":               f"تحسين صياغة: {task['title']}",
            "description":         f"مهمة '{task['title']}' لم يكملها أحد — الوصف الحالي غير محفز",
            "suggestion":          "أعد صياغة الوصف ليكون أكثر جاذبية وتحفيزاً",
            "basedOn":             "صفر إنجازات — الوصف الحالي لا يحفز المستخدم",
            "taskId":              task.get("id", ""),
            "improvedDescription": f"🌱 أنت تستطيع إحداث فرق! {task['title']} خطوة بسيطة نحو بيئة أنظف ✨",
        })
 
    for task in analytics.get("mostIgnored", [])[:2]:
        recs.append({
            "type":                "modify",
            "category":            task.get("category", "غير محدد"),
            "title":               f"تحسين صياغة: {task['title']}",
            "description":         f"مهمة '{task['title']}' تم تجاهلها {task['count']} مرة — الوصف لا يجذب المستخدم",
            "suggestion":          "أعد صياغة الوصف بأسلوب أكثر تحفيزاً وشخصية",
            "basedOn":             f"تجاهل {task['count']} مرة — يحتاج وصفاً أكثر جاذبية",
            "taskId":              task.get("id", ""),
            "improvedDescription": f"💚 {task['title']} — خطوة صغيرة منك، أثر كبير على بيئتك. جربها الآن! 🌍",
        })
 
    for f in reports.get("problematicFacilities", [])[:2]:
        recs.append({
            "type":            "review_reports",
            "category":        "إعادة التدوير",
            "title":           f"مراجعة حاوية: {f['name']}",
            "description":     f"{f['reportCount']} بلاغ معلق",
            "suggestion":      f"معاينة الحاوية وحل مشكلة: {f['mainIssue']}",
            "basedOn":         "بلاغات متكررة",
            "facilityId":      f.get("facilityId", ""),
            "facilityName":    f.get("name", ""),
            "facilityAddress": f.get("address", ""),
            "reportCount":     f.get("reportCount", 0),
        })
 
    top_category = seasonal.get("topCategoryLastYear", "")
    if top_category:
        task_title       = f"مهام {top_category} الموسمية"
        task_description = f"مهام بيئية في تصنيف {top_category}"
        recs.append({
            "type":               "add",
            "category":           top_category,
            "title":              task_title,
            "description":        seasonal.get("suggestion", ""),
            "suggestion":         f"أضف مهام في تصنيف '{top_category}'",
            "basedOn":            f"نمط موسمي من {seasonal.get('lastYearSameMonth', '')}",
            "userDescription":    f"🌱 أنت تستطيع المساهمة في بيئة أنظف! جرب مهمة {top_category} اليوم ✨",
            "validationStrategy": pick_validation_strategy(task_title, task_description),
        })
    else:
        task_title       = f"مهمة موسم {season['season']}"
        task_description = f"مهمة بيئية مناسبة لفصل {season['season']}"
        recs.append({
            "type":               "add",
            "category":           "إعادة التدوير",
            "title":              task_title,
            "description":        task_description,
            "suggestion":         "أضف مهمة تدوير مناسبة للموسم",
            "basedOn":            f"فصل {season['season']}",
            "userDescription":    f"🌿 استغل أجواء {season['season']} الجميلة وابدأ بخطوة بيئية بسيطة ✨",
            "validationStrategy": pick_validation_strategy(task_title, task_description),
        })
 
    return recs
 
 
# ============================================================
# HTTP Entry Point — أيجنت الإدمن
# ============================================================
@functions_framework.http
def admin_recommendations_agent(request):
    if request.method == "OPTIONS":
        return ("", 204, {
            "Access-Control-Allow-Origin":  "*",
            "Access-Control-Allow-Methods": "POST, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type, Authorization"
        })
 
    if request.method != "POST":
        return (json.dumps({"error": "POST only"}), 405,
                {"Content-Type": "application/json"})
 
    try:
        data   = request.get_json(silent=True) or {}
        result = run_admin_agent(data)
        status = 200 if "error" not in result else 400
 
        return (
            json.dumps(result, ensure_ascii=False, default=str),
            status,
            {
                "Content-Type":                "application/json; charset=utf-8",
                "Access-Control-Allow-Origin": "*"
            }
        )
    except Exception as e:
        import traceback
        traceback.print_exc()
        return (
            json.dumps({"error": str(e)}, ensure_ascii=False),
            500,
            {"Content-Type": "application/json"}
        )