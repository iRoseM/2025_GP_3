"""
╔══════════════════════════════════════════════════════════════╗
║          Nameer — Agent 1: Suggest Task Agent               ║
║  يقترح مهمة واحدة للمستخدم بناءً على موقعه ووقته          ║
║  Cloud Function Entry: suggest_task_agent                   ║
╚══════════════════════════════════════════════════════════════╝

Graph Nodes:
  load_profile → load_preferences → get_nearby_places
       → get_available_tasks → get_user_history
       → call_llm → parse_result → [fallback?] → finalize
"""

import os
import json
import math
import urllib.request
from datetime import datetime, timezone
from typing import TypedDict, Optional, Any

import functions_framework
import firebase_admin
from firebase_admin import firestore
from langgraph.graph import StateGraph, END
import time
import random
from datetime import datetime, timezone, timedelta
from typing import TypedDict, Optional, Any

# ─────────────────────────────────────────
# Firebase Init
# ─────────────────────────────────────────
if not firebase_admin._apps:
    firebase_admin.initialize_app()
db = firestore.client()

# ─────────────────────────────────────────
# Station Data (loaded once at startup)
# ─────────────────────────────────────────
BUS_STATIONS: list = []
METRO_STATIONS: list = []
# ─────────────────────────────────────────
# RSS Feeds
# ─────────────────────────────────────────
# RSS_FEEDS = [
#     "https://www.aljazeera.net/rss/environment.xml",
#     "https://feeds.bbcarabic.com/bbcarabic/science/rss.xml",
#     "https://www.saudigazette.com.sa/rss/environment",
# ]

def _load_stations():
    global BUS_STATIONS, METRO_STATIONS
    base = os.path.join(os.path.dirname(__file__), "assets", "data")
    for fname, target in [("bus_stations.json", "BUS"), ("metro_stations.json", "METRO")]:
        path = os.path.join(base, fname)
        if not os.path.exists(path):
            print(f"⚠️ {fname} not found")
            continue
        try:
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
            stations = (
                data if isinstance(data, list)
                else data.get("stations") or data.get("features") or []
            )
            if target == "BUS":
                BUS_STATIONS = stations
                print(f" Loaded {len(stations)} bus stations")
            else:
                METRO_STATIONS = stations
                print(f"🚇 Loaded {len(stations)} metro stations")
        except Exception as e:
            print(f"⚠️ Failed loading {fname}: {e}")


_load_stations()


# ══════════════════════════════════════════
# State — shared across all nodes
# ══════════════════════════════════════════
class SuggestTaskState(TypedDict):
    # ── Input ──────────────────────────────
    user_id: str
    pressed_at: str
    user_location: Optional[dict]        # {latitude, longitude}
    exclude_task_id: Optional[str]
    today_task_id: Optional[str]

    # ── Time context ───────────────────────
    hour: int
    time_label: str
    time_type: str                        # morning/afternoon/evening/night

    # ── Loaded data ────────────────────────
    profile: dict
    preferences: dict
    nearby_places: list
    available_tasks: list
    task_scores: dict
    top_task_ids: list
    ignored_ids: list
    exclude_ids: list

    # ── LLM ────────────────────────────────
    prompt: str
    llm_response: Optional[str]

    # ── Result ─────────────────────────────
    final_task: Optional[dict]
    final_description: str
    agent_reasoning: str
    used_fallback: bool

    # ── Final output (populated by node_finalize) ──
    result: Optional[dict]

    # ── Error ──────────────────────────────
    error: Optional[str]


# ══════════════════════════════════════════
# Helpers
# ══════════════════════════════════════════
def _haversine(lat1, lon1, lat2, lon2) -> float:
    R = 6371
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat / 2) ** 2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlon / 2) ** 2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def _station_coords(station: dict):
    lat = station.get("lat") or station.get("latitude")
    lng = station.get("lng") or station.get("longitude") or station.get("lon")
    if not lat and station.get("geometry", {}).get("type") == "Point":
        coords = station["geometry"].get("coordinates", [])
        if len(coords) >= 2:
            lng, lat = coords[0], coords[1]
    return (float(lat), float(lng)) if lat and lng else (None, None)


def _classify_place(place_type: str) -> str:
    t = place_type.lower()
    if any(k in t for k in ["طعام", "عضوي"]):         return "food_recycling"
    if any(k in t for k in ["ملابس", "منسوجات"]):     return "clothes_recycling"
    if any(k in t for k in ["إلكتروني", "كهربائي"]): return "electronic_recycling"
    if any(k in t for k in ["بلاستيك", "زجاج", "ورق"]): return "general_recycling"
    if "rvm" in t:                                     return "rvm"
    if any(k in t for k in ["باص", "مترو", "bus", "metro"]): return "transport"
    return "recycling"


def _call_gemini(prompt: str, temperature: float = 0.4, max_tokens: int = 800) -> Optional[str]:
    api_key = os.environ.get("GEMINI_API_KEY", "")
    if not api_key:
        return None
    
    url = f"https://generativelanguage.googleapis.com/v1/models/gemini-2.0-flash:generateContent?key={api_key}"
    body = json.dumps({
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {"temperature": temperature, "maxOutputTokens": max_tokens}
    }).encode()
    
    delays = [5, 15, 30] 
    
    for attempt in range(3):
        try:
            req = urllib.request.Request(
                url, data=body,
                headers={"Content-Type": "application/json"},
                method="POST"
            )
            with urllib.request.urlopen(req, timeout=30) as resp:
                result = json.loads(resp.read().decode())
                if result.get("error"):
                    return None
                text = result.get("candidates",[{}])[0].get("content",{}).get("parts",[{}])[0].get("text","")
                if text.strip():
                    return text.strip()
        except urllib.error.HTTPError as e:
            body_text = e.read().decode()
            print(f"⚠️ Gemini attempt {attempt+1} HTTP {e.code}: {body_text}")
            if e.code == 429:
                wait = delays[attempt]
                print(f"⏳ Rate limited → waiting {wait}s...")
                time.sleep(wait)  
            else:
                break
        except Exception as e:
            print(f"⚠️ Gemini attempt {attempt+1}: {e}")
            time.sleep(delays[attempt])
    
    return None


def _extract_json(text: str) -> Optional[dict]:
    try:
        clean = text.replace("```json", "").replace("```", "").strip()
        first = clean.index("{")
        last  = clean.rindex("}") + 1
        return json.loads(clean[first:last])
    except json.JSONDecodeError as e:
        print(f"⚠️ JSON extract failed: {e}")
        try:
            clean = text.replace("```json", "").replace("```", "").strip()
            first = clean.index("{")
            partial = clean[first:]
            open_braces   = partial.count("{") - partial.count("}")
            open_brackets = partial.count("[") - partial.count("]")
            partial += "]" * open_brackets + "}" * open_braces
            return json.loads(partial)
        except Exception as e2:
            print(f"⚠️ JSON fix failed: {e2}")
            return None
    except Exception as e:
        print(f"⚠️ JSON extract failed: {e}")
        return None


# ══════════════════════════════════════════
# Node 1 — Set time context
# ══════════════════════════════════════════
def node_set_time_context(state: SuggestTaskState) -> dict:
    print("⏰ Node 1: Setting time context...")
    try:
        dt = datetime.fromisoformat(state["pressed_at"].replace("Z", "+00:00"))
        hour = dt.hour
    except Exception:
        hour = datetime.now().hour

    if 5 <= hour < 12:
        label, ttype = "الصباح — وقت النشاط والحركة", "morning"
    elif 12 <= hour < 16:
        label, ttype = "الظهيرة — وقت المهام السريعة", "afternoon"
    elif 16 <= hour < 21:
        label, ttype = "المساء — وقت ممتاز للتدوير", "evening"
    else:
        label, ttype = "الليل — وقت مناسب للتوعية", "night"

    exclude = [i for i in [state.get("exclude_task_id"), state.get("today_task_id")] if i]
    return {"hour": hour, "time_label": label, "time_type": ttype, "exclude_ids": exclude}


# ══════════════════════════════════════════
# Node 2 — Load user profile
# ══════════════════════════════════════════
def node_load_profile(state: SuggestTaskState) -> dict:
    print("👤 Node 2: Loading user profile...")
    try:
        doc = db.collection("users").document(state["user_id"]).get()
        if not doc.exists:
            return {"profile": {}}
        data = doc.to_dict()


        level_id = data.get("userLevelId", "seedling")
        level_map = {
            "seedling": ("بذرة 🌱",          "تشجيعي — مستخدم جديد"),
            "sprout":   ("نبتة 🌿",          "إيجابي — بدأ رحلته"),
            "tree":     ("شجرة 🌳",          "إيجابي — مستخدم نشيط"),
            "guardian": ("حارس البيئة 🌍",   "احترافي — مستخدم ملتزم"),
            "champion": ("بطل الاستدامة 🏆", "تحدي — مستخدم متقدم"),
        }
        level_label, level_tone = level_map.get(level_id, ("بذرة 🌱", "تشجيعي"))
        gender  = data.get("gender", "")
        pronoun = "أنتِ" if gender == "female" else "أنت"
        suffix  = "ي"   if gender == "female" else ""

        profile = {
            "level_id": level_id, "level_label": level_label, "level_tone": level_tone,
            "pronoun": pronoun, "suffix": suffix, "gender": gender,
            "completed": data.get("completedTask", 0),
            "streak":    data.get("currentStreak", 0),
            "points":    data.get("points", 0),
            "carbon_saved": round(data.get("totalCarbonSaved", 0), 2),
            "username": data.get("username", ""),
        }
        print(f"   Level: {level_id} | Gender: {gender} | Streak: {profile['streak']}")
        return {"profile": profile}
    except Exception as e:
        print(f"⚠️ load_profile error: {e}")
        return {"profile": {}}


# ══════════════════════════════════════════
# Node 3 — Load preferences
# ══════════════════════════════════════════
def node_load_preferences(state: SuggestTaskState) -> dict:
    print("📊 Node 3: Loading preferences...")
    try:
        doc = db.collection("userTaskPreferences").document(state["user_id"]).get()
        if not doc.exists:
            return {"preferences": {"found": False}, "task_scores": {}, "top_task_ids": [], "ignored_ids": []}
        data  = doc.to_dict()
        prefs = data.get("taskPreferences", {})

        top_tasks, ignored_tasks, task_scores = [], [], {}
        for tid, stats in prefs.items():
            score      = stats.get("score", 1)
            view_count = stats.get("viewCount", 0)
            task_scores[tid] = score
            entry = {"task_id": tid, "title": stats.get("title", ""), "category": stats.get("category", ""), "score": score, "viewCount": view_count}
            if score > 3:
                top_tasks.append(entry)
            if score < 2 and view_count > 3:
                ignored_tasks.append(entry)

        top_tasks.sort(key=lambda x: x["score"], reverse=True)
        ignored_tasks.sort(key=lambda x: x["viewCount"], reverse=True)

        return {
            "preferences": {
                "found": True,
                "top_tasks":      top_tasks[:5],
                "ignored_tasks":  ignored_tasks[:3],
                "top_task_title": data.get("topTaskTitle", ""),
            },
            "task_scores":   task_scores,
            "top_task_ids":  [t["task_id"] for t in top_tasks[:5]],
            "ignored_ids":   [t["task_id"] for t in ignored_tasks[:15]],
        }
    except Exception as e:
        print(f"⚠️ load_preferences error: {e}")
        return {"preferences": {"found": False}, "task_scores": {}, "top_task_ids": [], "ignored_ids": []}


# ══════════════════════════════════════════
# Node 4 — Get nearby places
# ══════════════════════════════════════════
def node_get_nearby_places(state: SuggestTaskState) -> dict:
    loc = state.get("user_location")
    if not loc:
        print("📍 Node 4: No location provided — skipping")
        return {"nearby_places": []}

    print("📍 Node 4: Getting nearby places...")
    lat, lng = loc["latitude"], loc["longitude"]
    radius   = 2.0
    nearby   = []

    # Firestore facilities
    try:
        for doc in db.collection("facilities").stream():
            d = doc.to_dict()
            plat, plng = d.get("lat"), d.get("lng")
            if plat is None or plng is None or d.get("status") == "متوقف":
                continue
            dist = _haversine(lat, lng, plat, plng)
            if dist <= radius:
                ptype = d.get("type", "مكان")
                nearby.append({
                    "id": doc.id, "name": ptype, "address": d.get("address", ""),
                    "provider": d.get("provider", ""), "type": ptype,
                    "distance": round(dist, 2), "category": _classify_place(ptype),
                    "source": "facility", "priority": 1
                })
    except Exception as e:
        print(f"⚠️ facilities error: {e}")

    # Bus stations
    for station in BUS_STATIONS:
        slat, slng = _station_coords(station)
        if slat is None:
            continue
        dist = _haversine(lat, lng, slat, slng)
        if dist <= radius:
            nearby.append({
                "id": f"bus_{station.get('id', id(station))}",
                "name": station.get("name") or station.get("station_name") or "محطة باص",
                "address": station.get("address") or "", "provider": "هيئة النقل العام",
                "type": "محطة باص", "distance": round(dist, 2),
                "category": "transport", "source": "bus_station", "priority": 2
            })

    # Metro stations
    for station in METRO_STATIONS:
        slat, slng = _station_coords(station)
        if slat is None:
            continue
        dist = _haversine(lat, lng, slat, slng)
        if dist <= radius:
            name     = station.get("name") or "محطة مترو"
            line     = station.get("line") or station.get("metro_line") or ""
            address  = f"{name} ({line})" if line else name
            nearby.append({
                "id": f"metro_{station.get('id', id(station))}",
                "name": name, "address": station.get("address") or address,
                "provider": "هيئة النقل العام", "type": "محطة مترو",
                "distance": round(dist, 2), "category": "transport",
                "source": "metro_station", "priority": 2
            })

    nearby.sort(key=lambda x: (x["distance"], -x["priority"]))
    print(f"   Found {len(nearby)} nearby places")
    return {"nearby_places": nearby}


# ══════════════════════════════════════════
# Node 5 — Get available tasks
# ══════════════════════════════════════════
def node_get_available_tasks(state: SuggestTaskState) -> dict:
    print("📋 Node 5: Getting available tasks...")
    exclude    = set(state.get("exclude_ids", []))
    ignored    = set(state.get("ignored_ids", []))
    scores     = state.get("task_scores", {})
    cur_month  = datetime.now().strftime("%Y-%m")
    tasks      = []

    try:
        for doc in db.collection("tasks").where("status", "==", "active").stream():
            if doc.id in exclude or doc.id in ignored:
                continue
            t = doc.to_dict()
            if t.get("visible_from", "") > cur_month:
                continue
            if t.get("expiry_month") and t["expiry_month"] < cur_month:
                continue
            tasks.append({
                "id": doc.id, "title": t.get("title", ""),
                "description": t.get("description", ""), "category": t.get("category", ""),
                "points": t.get("points", 0), "preference_score": scores.get(doc.id, 1),
                "validation": t.get("validationStrategy", ""),
                "calc_mode":  t.get("calcMode", ""), "ef_ref": t.get("ef_ref", ""),
            })
    except Exception as e:
        print(f"⚠️ get_available_tasks error: {e}")

    tasks.sort(key=lambda x: x["preference_score"], reverse=True)
    print(f"   Found {len(tasks)} tasks")

    if not tasks:
        return {"available_tasks": [], "error": "NO_TASKS_AVAILABLE"}
    return {"available_tasks": tasks}


# ══════════════════════════════════════════
# Node 6 — Get user history (update ignored)
# ══════════════════════════════════════════
def node_get_user_history(state: SuggestTaskState) -> dict:
    print("📜 Node 6: Getting user history...")
    completed_ids, extra_ignored = [], []

    try:
        for d in (db.collection("userTasks")
                  .where("userId", "==", state["user_id"])
                  .where("status", "==", "completed")
                  .order_by("completedAt", direction=firestore.Query.DESCENDING)
                  .limit(20).stream()):
            tid = d.to_dict().get("taskId")
            if tid:
                completed_ids.append(tid)

        for d in (db.collection("userTasks")
                  .where("userId", "==", state["user_id"])
                  .where("ignored", "==", True)
                  .order_by("ignoredAt", direction=firestore.Query.DESCENDING)
                  .limit(20).stream()):
            tid = d.to_dict().get("taskId")
            if tid:
                extra_ignored.append(tid)
    except Exception as e:
        print(f"⚠️ user history error: {e}")

    merged_ignored = list(set(state.get("ignored_ids", [])) | set(extra_ignored))
    return {"ignored_ids": merged_ignored}


# ══════════════════════════════════════════
# Node 7 — Build prompt
# ══════════════════════════════════════════
def node_build_prompt(state: SuggestTaskState) -> dict:
    print("📝 Node 7: Building prompt...")
    profile   = state["profile"]
    prefs     = state["preferences"]
    tasks     = state["available_tasks"]
    nearby    = state["nearby_places"]
    time_type = state["time_type"]
    hour      = state["hour"]

    pronoun     = profile.get("pronoun", "أنت")
    suffix      = profile.get("suffix", "")
    level_label = profile.get("level_label", "بذرة 🌱")
    level_tone  = profile.get("level_tone", "تشجيعي")
    streak      = profile.get("streak", 0)
    streak_text = f"لديه{'ا' if profile.get('gender') == 'female' else ''} {streak} يوم متتالي 🔥" if streak > 1 else ""

    recycling_places = [p for p in nearby if p["category"] != "transport"]
    transport_places = [p for p in nearby if p["category"] == "transport"]

    top_tasks_text = "\n".join([f"   • {t['title']} (score: {t['score']})" for t in prefs.get("top_tasks", [])]) or "   لا توجد"
    ignored_text   = "\n".join([f"   • {t['title']} (viewCount: {t['viewCount']})" for t in prefs.get("ignored_tasks", [])]) or ""
    nearby_details = "\n".join([
        f"   • {p['type']} — بعد {p['distance']} كم — {p['address']} [نوع: {p['category']}]" 
        for p in nearby[:5]
    ]) or "   لا توجد أماكن قريبة"

    # وفي الـ prompt أضيفي:
    nearby_section = f""" الأماكن القريبة (فقط هذه الأماكن حقيقية — لا تختلق أماكن أخرى):
    {nearby_details}

تحذير مهم: إذا كانت القائمة "لا توجد أماكن قريبة" → لا تذكر أي مكان في الوصف إطلاقاً"""    
    task_list      = "\n".join([f"{i+1}. [{t['id']}] {t['title']} - {t['category']} [score: {t['preference_score']}]" for i, t in enumerate(tasks)])

    # Priority rules by time
    if time_type == "morning":
        priority = """قواعد الاختيار (الصباح: أولوية للنقل المستدام):
    1. إذا يوجد محطة باص/مترو قريبة → مهمة نقل عام
    2. إذا يوجد مكان تدوير قريب → مهمة تدوير
    3. بدون أماكن → من المفضلة (score > 5)
    4. تجنب المتجاهلة"""
    elif time_type == "evening":
        priority = """قواعد الاختيار (المساء: أولوية للتدوير):
    1. إذا يوجد مكان تدوير قريب → مهمة تدوير
    2. إذا يوجد محطة باص/مترو → مهمة نقل عام
    3. بدون أماكن → من المفضلة (score > 5)
    4. تجنب المتجاهلة"""
    elif time_type == "afternoon":
        priority = """قواعد الاختيار (الظهيرة: مهام سريعة):
    1. أقرب مكان من أي نوع → مهمة سريعة مناسبة
    2. بدون أماكن → مهمة منتج محلي أو من المفضلة (score > 5)
    3. تجنب المتجاهلة"""
    else:
        priority = """قواعد الاختيار (الليل: توعية ومنتجات محلية):
    1. مهام توعوية/تعليمية أو منتج محلي (لا تحتاج حركة)
    2. مكان تدوير أقل من 1 كم → يمكن اقتراحه
    3. من المفضلة (score > 5)
    4. تجنب المتجاهلة"""

    prompt = f"""أنت مساعد بيئي ذكي ومحفز. اختر مهمة واحدة وصِغ وصفاً شخصياً يحفز المستخدم.

الوقت: {state['time_label']} (الساعة {hour})

الأماكن القريبة:
{nearby_details}

إحصاءات الأماكن:
- أماكن التدوير: {len(recycling_places)}
- محطات النقل: {len(transport_places)}

شخصية المستخدم:
- المستوى: {level_label} ({level_tone})
- الجنس: {profile.get('gender', 'غير محدد')} — خاطب{suffix}ه بـ "{pronoun}"
- المهام المكتملة: {profile.get('completed', 0)}
- النقاط: {profile.get('points', 0)}
- الكربون الموفَّر: {profile.get('carbon_saved', 0)} كغ
{f"- {streak_text}" if streak_text else ""}

تفضيلاته:
المفضلة:
{top_tasks_text}
{f"المتجاهلة:{chr(10)}{ignored_text}" if ignored_text else ""}

 المهام المتاحة:
{task_list}

{priority}

قواعد الوصف:
- لا تستخدم إيموجيات أكثر من 1 بحد اعلى
- إذا "لا توجد أماكن قريبة" → لا تذكر أي حاوية أو محطة أو مسافة إطلاقاً
- فقط اذكر الأماكن الموجودة في القائمة أعلاه
- يتطابق مع طبيعة المهمة المختارة تماماً
- إذا المهمة تدوير بلاستيك → اذكر حاوية بلاستيك فقط، لا تذكر حاوية طعام
- إذا المهمة تدوير طعام → اذكر حاوية طعام فقط، لا تذكر حاوية بلاستيك
- إذا المهمة تدوير ورق → اذكر حاوية ورق فقط
- إذا المهمة نقل عام → اذكر محطة باص أو مترو فقط، لا تذكر حاويات
- إذا المهمة منزلية أو توعوية → لا تذكر أي مكان إطلاقاً
- تحذير: لا تذكر مكان لا يتطابق مع نوع المهمة المختارة
- إذا المهمة منتج محلي → اطلب من المستخدم شراء منتج سعودي الصنع وتصوير بلد المنشأ

أرجع JSON فقط:
{{
  "taskId": "معرف المهمة",
  "reasoning": "سبب الاختيار",
  "personalizedDescription": "وصف مخصص دافئ"
}}"""

    return {"prompt": prompt}


# ══════════════════════════════════════════
# Node 8 — Call LLM
# ══════════════════════════════════════════
def node_call_llm(state: SuggestTaskState) -> dict:
    print("🤖 Node 8: Calling Gemini...")
    response = _call_gemini(state["prompt"], temperature=0.2, max_tokens=600)
    return {"llm_response": response}


# ══════════════════════════════════════════
# Node 9 — Parse LLM response
# ══════════════════════════════════════════
def node_parse_result(state: SuggestTaskState) -> dict:
    print("🔍 Node 9: Parsing LLM response...")
    tasks    = state["available_tasks"]
    response = state.get("llm_response")

    if response:
        parsed = _extract_json(response)
        if parsed and parsed.get("taskId"):
            task_id   = parsed["taskId"].replace("[", "").replace("]", "").strip()
            task      = next((t for t in tasks if t["id"] == task_id), None)
            if task:
                print(f"   ✅ LLM selected: {task['title']}")
                return {
                    "final_task":        task,
                    "final_description": parsed.get("personalizedDescription", ""),
                    "agent_reasoning":   parsed.get("reasoning", ""),
                    "used_fallback":     False,
                }
            print(f"   ⚠️ Task ID not found: {task_id}")

    print("   ⚠️ LLM parse failed → will fallback")
    return {"final_task": None, "used_fallback": True}


# ══════════════════════════════════════════
# Node 10 — Fallback selection
# ══════════════════════════════════════════
def node_fallback(state: SuggestTaskState) -> dict:
    print("⚠️ Node 10: Running fallback selection...")
    tasks        = state["available_tasks"]
    ignored      = set(state.get("ignored_ids", []))
    top_ids      = state.get("top_task_ids", [])
    time_type    = state["time_type"]
    nearby       = state["nearby_places"]
    profile      = state["profile"]
    pronoun      = profile.get("pronoun", "أنت")
    suffix       = profile.get("suffix", "")
    level_label  = profile.get("level_label", "")

    candidates       = [t for t in tasks if t["id"] not in ignored]
    transport_tasks  = [t for t in candidates if t.get("category") == "transport"]
    recycling_tasks  = [t for t in candidates if t.get("category") in ["recycling", "food_recycling", "clothes_recycling", "general_recycling"]]
    awareness_tasks  = [t for t in candidates if t.get("category") == "awareness"]
    recycling_places = [p for p in nearby if p["category"] != "transport"]
    transport_places = [p for p in nearby if p["category"] == "transport"]

    pool = (
        transport_tasks if (time_type == "morning" and transport_places)
        else recycling_tasks if (time_type == "evening" and recycling_places)
        else awareness_tasks if time_type == "night"
        else candidates
    ) or candidates or tasks

    preferred = [t for t in pool if t["id"] in top_ids]
    task = (preferred or pool or tasks)[0] if (preferred or pool or tasks) else None

    if not task:
        return {"error": "NO_SUITABLE_TASK_FOUND"}

    # Build fallback description
    if time_type == "morning" and transport_places:
        nearest = transport_places[0]
        # فقط اذكر المحطة لو المهمة نقل
        if "نقل" in task.get("category","") or "transport" in task.get("category",""):
            desc = f" صباح الخير {pronoun}! محطة {nearest['type']} قريبة ({nearest['distance']} كم). جربي {task['title']} ✨"
        else:
            desc = f"🌱 {pronoun} في بداية يومك! {task['title']} خطوة رائعة للبيئة ✨"
    elif time_type == "evening" and recycling_places:
        nearest = recycling_places[0]
        # فقط اذكر الحاوية لو المهمة تدوير
        if "تدوير" in task.get("category","") or "recycl" in task.get("category",""):
            desc = f"🌙 مساء الخير {pronoun}! {nearest['type']} قريبة ({nearest['distance']} كم). وقت مثالي لـ {task['title']} ♻️"
        else:
            desc = f"🌙 مساء الخير {pronoun}! {task['title']} خطوة جميلة لإنهاء يومك "
    elif nearby:
        nearest = nearby[0]
        task_cat = task.get("category","")
        # اذكر المكان فقط لو يتطابق مع المهمة
        if ("تدوير" in task_cat and nearest["category"] != "transport") or \
        ("نقل" in task_cat and nearest["category"] == "transport"):
            desc = f"📍 {nearest['type']} قريبة ({nearest['distance']} كم)! جربي {task['title']} الآن ✨"
        else:
            desc = f"🌱 {pronoun} في بداية رحلتك! {task['title']} خطوة رائعة للانطلاق"
    else:
        desc = f"🌱 {pronoun} في بداية رحلتك! {task['title']} خطوة رائعة للانطلاق"
    return {
        "final_task":        task,
        "final_description": desc,
        "agent_reasoning":   f"fallback: time={time_type}, places={len(nearby)}",
        "used_fallback":     True,
    }


# ══════════════════════════════════════════
# Node 11 — Finalize output
# ══════════════════════════════════════════
def node_finalize(state: SuggestTaskState) -> dict:
    print("✅ Node 11: Finalizing output...")
    task    = state.get("final_task")
    nearby  = state.get("nearby_places", [])
    scores  = state.get("task_scores", {})
    top_ids = state.get("top_task_ids", [])

    if not task:
        return {"error": "NO_SUITABLE_TASK_FOUND"}

    # ── تنظيف الوصف لو ذكر أماكن وهمية ──
    final_desc = state.get("final_description") or task.get("description", "")
    if final_desc:
        suspicious_words = ["كم", "قريب", "حاوية", "محطة", "متر", "بعد"]
        has_suspicious   = any(w in final_desc for w in suspicious_words)

        if not nearby and has_suspicious:
            # ما في أماكن قريبة حقيقية → استخدم الوصف الأصلي
            print("   ⚠️ Desc mentions location but no nearby places → using original")
            final_desc = task.get("description", "")
        elif nearby and has_suspicious:
            # في أماكن قريبة → تحقق إن المكان المذكور موجود فعلاً
            nearby_types = [p["type"] for p in nearby]
            nearby_names = [p.get("name", "") for p in nearby]
            all_known    = nearby_types + nearby_names
            # لو الوصف يذكر نوع مكان مو موجود في القائمة الحقيقية → استخدم الأصلي
            mentioned_fake = False
            for fake_word in ["حاوية طعام", "حاوية بلاستيك", "حاوية ورق", "محطة باص", "محطة مترو"]:
                if fake_word in final_desc:
                    if not any(fake_word in k for k in all_known):
                        mentioned_fake = True
                        break
            if mentioned_fake:
                print("   ⚠️ Desc mentions fake location → using original")
                final_desc = task.get("description", "")

    # ── ربط مقال إذا المهمة تحتاج اختبار قصير ──
    article_id = None
    if task.get("validation") == "التحقق عبر اجراء اختبار قصير":
        try:
            articles = list(db.collection("articles")
                            .order_by("createdAt", direction=firestore.Query.DESCENDING)
                            .limit(10).stream())
            if articles:
                article_id = random.choice(articles).id
        except Exception as e:
            print(f"   ⚠️ Article fetch error: {e}")

    result = {
        "id":                         task["id"],
        "taskId":                     task["id"],
        "title":                      task.get("title", ""),
        "description":                final_desc,
        "originalDescription":        task.get("description", ""),
        "points":                     task.get("points", 0),
        "category":                   task.get("category", ""),
        "validationStrategy":         task.get("validation", ""),
        "calcMode":                   task.get("calc_mode", ""),
        "ef_ref":                     task.get("ef_ref", ""),
        "status":                     "pending",
        "agentReasoning":             state.get("agent_reasoning", ""),
        "usedFallback":               state.get("used_fallback", False),
        "nearbyPlacesCount":          len(nearby),
        "nearbyPlaces":               nearby[:3],
        "nearbyRecyclingPlaces":      len([p for p in nearby if p["category"] != "transport"]),
        "nearbyTransportPlaces":      len([p for p in nearby if p["category"] == "transport"]),
        "userLocationDetected":       state.get("user_location") is not None,
        "timeContext":                {"hour": state["hour"], "timeLabel": state["time_label"], "timeType": state["time_type"]},
        "preferenceScore":            scores.get(task["id"], 1),
        "suggestedBasedOnLocation":   len(nearby) > 0,
        "suggestedBasedOnPreference": task["id"] in top_ids or scores.get(task["id"], 1) > 5,
        "userProfile": {
            "level":  state["profile"].get("level_id", ""),
            "streak": state["profile"].get("streak", 0),
            "points": state["profile"].get("points", 0),
            "carbon": state["profile"].get("carbon_saved", 0),
        },
    }

    if article_id:
        result["articleId"] = article_id

    return {"result": result}

# ══════════════════════════════════════════
# Conditional edges
# ══════════════════════════════════════════
def should_fallback(state: SuggestTaskState) -> str:
    if state.get("error") == "NO_TASKS_AVAILABLE":
        return "end_error"
    return "fallback" if state.get("final_task") is None else "finalize"


def after_parse(state: SuggestTaskState) -> str:
    return "fallback" if state.get("used_fallback") else "finalize"


# ══════════════════════════════════════════
# Build the graph
# ══════════════════════════════════════════
def build_suggest_task_graph() -> Any:
    g = StateGraph(SuggestTaskState)

    g.add_node("set_time_context",    node_set_time_context)
    g.add_node("load_profile",        node_load_profile)
    g.add_node("load_preferences",    node_load_preferences)
    g.add_node("get_nearby_places",   node_get_nearby_places)
    g.add_node("get_available_tasks", node_get_available_tasks)
    g.add_node("get_user_history",    node_get_user_history)
    g.add_node("build_prompt",        node_build_prompt)
    g.add_node("call_llm",            node_call_llm)
    g.add_node("parse_result",        node_parse_result)
    g.add_node("fallback",            node_fallback)
    g.add_node("finalize",            node_finalize)

    g.set_entry_point("set_time_context")
    g.add_edge("set_time_context",    "load_profile")
    g.add_edge("load_profile",        "load_preferences")
    g.add_edge("load_preferences",    "get_nearby_places")
    g.add_edge("get_nearby_places",   "get_available_tasks")

    g.add_conditional_edges(
        "get_available_tasks",
        lambda s: "end_error" if s.get("error") == "NO_TASKS_AVAILABLE" else "get_user_history",
        {"end_error": END, "get_user_history": "get_user_history"},
    )

    g.add_edge("get_user_history",    "build_prompt")
    g.add_edge("build_prompt",        "call_llm")
    g.add_edge("call_llm",            "parse_result")

    g.add_conditional_edges(
        "parse_result",
        after_parse,
        {"fallback": "fallback", "finalize": "finalize"},
    )

    g.add_edge("fallback",  "finalize")
    g.add_edge("finalize",  END)

    return g.compile()


# ══════════════════════════════════════════
# HTTP Entry Point
# ══════════════════════════════════════════
_suggest_task_graph = build_suggest_task_graph()


@functions_framework.http
def suggest_task_agent(request):
    if request.method == "OPTIONS":
        return ("", 204, {"Access-Control-Allow-Origin": "*",
                          "Access-Control-Allow-Methods": "POST, OPTIONS",
                          "Access-Control-Allow-Headers": "Content-Type, Authorization"})
    if request.method != "POST":
        return (json.dumps({"error": "POST only"}), 405, {"Content-Type": "application/json"})

    try:
        data = request.get_json(silent=True) or {}
        if not data.get("userId"):
            return (json.dumps({"error": "userId مطلوب"}), 400, {"Content-Type": "application/json"})

        initial_state: SuggestTaskState = {
            "user_id":         data.get("userId"),
            "pressed_at":      data.get("pressedAt", datetime.now(timezone.utc).isoformat()),
            "user_location":   data.get("userLocation"),
            "exclude_task_id": data.get("excludeTaskId"),
            "today_task_id":   data.get("todayTaskId"),
            # populated by nodes
            "hour": 0, "time_label": "", "time_type": "",
            "profile": {}, "preferences": {}, "nearby_places": [],
            "available_tasks": [], "task_scores": {}, "top_task_ids": [],
            "ignored_ids": [], "exclude_ids": [],
            "prompt": "", "llm_response": None,
            "final_task": None, "final_description": "",
            "agent_reasoning": "", "used_fallback": False,
            "result": None, "error": None,
        }

        final_state = _suggest_task_graph.invoke(initial_state)
        result = final_state.get("result") or final_state.get("error") or {"error": "UNKNOWN"}
        status = 200 if "error" not in result else 404

        return (json.dumps(result, ensure_ascii=False, default=str), status,
                {"Content-Type": "application/json; charset=utf-8",
                 "Access-Control-Allow-Origin": "*"})

    except Exception as e:
        import traceback; traceback.print_exc()
        return (json.dumps({"error": str(e)}, ensure_ascii=False), 500,
                {"Content-Type": "application/json"})



################################################################


# ══════════════════════════════════════════
# Helpers (shared)
# ══════════════════════════════════════════
# ══════════════════════════════════════════
# Per-User State
# ══════════════════════════════════════════
class DailyTaskUserState(TypedDict):
    # input
    user_id: str
    user_data: dict
    available_tasks: list
    tomorrow: str

    # loaded
    prefs_data: dict
    top_task_ids: list
    task_prefs: dict
    ignored_ids: list   # set converted to list for LangGraph serialization
    pending_ids: list   # set converted to list for LangGraph serialization
    yesterday_id: Optional[str]

    # computed
    candidate_tasks: list
    user_profile: dict

    # LLM
    prompt: str
    llm_response: Optional[str]

    # result
    selected_task: Optional[dict]
    personalized_desc: str
    success: bool
    error: Optional[str]


# ══════════════════════════════════════════
# Per-User Nodes
# ══════════════════════════════════════════
def u_load_prefs(state: DailyTaskUserState) -> dict:
    uid = state["user_id"]
    try:
        doc = db.collection("userTaskPreferences").document(uid).get()
        if doc.exists:
            data = doc.to_dict()
            prefs = data.get("taskPreferences", {})
            top   = data.get("topTasks", [])
            return {"prefs_data": data, "top_task_ids": top, "task_prefs": prefs}
    except Exception as e:
        print(f"   ⚠️ prefs error: {e}")
    return {"prefs_data": {}, "top_task_ids": [], "task_prefs": {}}


def u_load_ignored(state: DailyTaskUserState) -> dict:
    uid = state["user_id"]
    ids = set()
    try:
        for doc in (db.collection("userTasks")
                    .where("userId", "==", uid).where("ignored", "==", True)
                    .order_by("ignoredAt", direction=firestore.Query.DESCENDING)
                    .limit(20).stream()):
            tid = doc.to_dict().get("taskId")
            if tid:
                ids.add(tid)
    except Exception as e:
        print(f"   ⚠️ ignored error: {e}")
    return {"ignored_ids": list(ids)}


def u_load_pending(state: DailyTaskUserState) -> dict:
    uid = state["user_id"]
    ids = set()
    try:
        cutoff_ts = (datetime.now() - timedelta(days=7)).timestamp()
        for doc in (db.collection("dailyTasks").document(uid)
                    .collection("tasks").where("status", "==", "pending").stream()):
            d = doc.to_dict()
            created_at = d.get("createdAt")
            try:
                doc_ts = (
                    created_at._seconds if hasattr(created_at, "_seconds")
                    else created_at.timestamp() if hasattr(created_at, "timestamp")
                    else None
                )
                if doc_ts and doc_ts >= cutoff_ts:
                    tid = d.get("id")
                    if tid:
                        ids.add(tid)
            except Exception:
                pass
    except Exception as e:
        print(f"   ⚠️ pending error: {e}")
    return {"pending_ids": list(ids)}


def u_load_yesterday(state: DailyTaskUserState) -> dict:
    uid = state["user_id"]
    try:
        yesterday_str = (datetime.now() - timedelta(days=1)).strftime("%Y-%m-%d")
        doc = (db.collection("dailyTasks").document(uid)
               .collection("tasks").document(yesterday_str).get())
        if doc.exists:
            tid = doc.to_dict().get("id")
            print(f"   📅 Yesterday task: {doc.to_dict().get('title')} ({tid})")
            return {"yesterday_id": tid}
    except Exception as e:
        print(f"   ⚠️ yesterday error: {e}")
    return {"yesterday_id": None}


def u_build_profile(state: DailyTaskUserState) -> dict:
    data       = state["user_data"]
    task_prefs = state["task_prefs"]
    gender     = data.get("gender", "")

    level_id = data.get("userLevelId", "seedling")
    level_map  = {
        "seedling": ("بذرة 🌱",          "تشجيعي — مستخدم جديد"),
        "sprout":   ("نبتة 🌿",          "إيجابي — بدأ رحلته"),
        "tree":     ("شجرة 🌳",          "إيجابي — مستخدم نشيط"),
        "guardian": ("حارس البيئة 🌍",   "احترافي — مستخدم ملتزم"),
        "champion": ("بطل الاستدامة 🏆", "تحدي — مستخدم متقدم"),
    }
    level_label, level_tone = level_map.get(level_id, ("بذرة 🌱", "تشجيعي"))
    pronoun = "أنتِ" if gender == "female" else "أنت"
    suffix  = "ي"   if gender == "female" else ""

    top_prefs = sorted(
        [{"id": k, **v} for k, v in task_prefs.items() if v.get("score", 0) > 3],
        key=lambda x: x.get("score", 0), reverse=True
    )[:5]
    ignored_prefs = [
        {"id": k, **v} for k, v in task_prefs.items()
        if v.get("ignored", 0) > v.get("completed", 0)
    ]
    high_view_low_score = [
        k for k, v in task_prefs.items()
        if v.get("viewCount", 0) > 5 and v.get("score", 1) < 2
    ]
    streak = data.get("currentStreak", 0)

    # Compute candidate tasks
    tasks_to_avoid = set(state["ignored_ids"]) | set(state["pending_ids"])
    if state.get("yesterday_id"):
        tasks_to_avoid.add(state["yesterday_id"])

    candidates = [t for t in state["available_tasks"] if t["id"] not in tasks_to_avoid]
    if not candidates:
        candidates = state["available_tasks"]

    profile = {
        "level_id": level_id, "level_label": level_label, "level_tone": level_tone,
        "pronoun": pronoun, "suffix": suffix, "gender": gender,
        "completed": data.get("completedTask", 0),
        "streak": streak, "points": data.get("points", 0),
        "carbon_saved": round(data.get("totalCarbonSaved", 0), 2),
        "top_prefs": top_prefs, "ignored_prefs": ignored_prefs[:3],
        "high_view_low_score": high_view_low_score[:5],
        "streak_text": f"لديك {streak} يوم متتالي 🔥" if streak > 1 else "",
    }
    return {"user_profile": profile, "candidate_tasks": candidates}


def u_build_prompt(state: DailyTaskUserState) -> dict:
    p          = state["user_profile"]
    tasks      = state["candidate_tasks"]
    task_prefs = state["task_prefs"]
    pronoun    = p["pronoun"]
    suffix     = p["suffix"]
    level_label = p["level_label"]
    level_tone  = p["level_tone"]
    streak_text = p["streak_text"]

    top_prefs_text = "\n".join([
        f"   • [{t['id']}] {t.get('title','')} (score: {t.get('score',0):.1f})"
        for t in p["top_prefs"]
    ]) or "   لا توجد"
    ignored_text = "\n".join([
        f"   • [{t['id']}] {t.get('title','')}"
        for t in p["ignored_prefs"]
    ]) or "   لا توجد"
    high_view_text = "\n".join([f"   • [{tid}]" for tid in p["high_view_low_score"]]) or "   لا توجد"
    task_list = "\n".join([
        f"{i+1}. [{t['id']}] {t['title']} - {t['category']} (score: {task_prefs.get(t['id'],{}).get('score',1):.1f})"
        for i, t in enumerate(tasks)
    ])

    prompt = f"""أنت مساعد بيئي ذكي. اختر مهمة يومية واحدة مناسبة واكتب وصفاً شخصياً.

ملف المستخدم:
- المستوى: {level_label} — {level_tone}
- الجنس: {p['gender']} — خاطبه بـ "{pronoun}"
- المهام المكتملة: {p['completed']}
- النقاط: {p['points']}
- الكربون الموفَّر: {p['carbon_saved']} كغ
{f"- {streak_text}" if streak_text else ""}

المهام المفضلة (score عالي):
{top_prefs_text}

المهام المتجاهلة (تجنبها):
{ignored_text}

معروضة كثيراً بدون إنجاز (تجنبها):
{high_view_text}

المهام المتاحة:
{task_list}

قواعد الاختيار:
1. من المفضلة (score > 3) إن وجدت
2. تجنب المتجاهلة والمعروضة كثيراً
3. لا تكرر نفس المهمة يومياً
4. وزّع على تصنيفات مختلفة

قواعد الوصف:
- لا تستخدم إيموجيات أكثر من 1 بحد اعلى
- خاطب بـ "{pronoun}"، 15-20 كلمة
- مختلف عن الوصف الأصلي
{f'- اذكر الـ streak: "حافظ{suffix} على سلسلتك!"' if streak_text else ""}

أرجع JSON فقط:
{{
  "taskId": "معرف المهمة",
  "reasoning": "سبب الاختيار",
  "personalizedDescription": "وصف شخصي دافئ"
}}"""
    return {"prompt": prompt}


def u_call_llm(state: DailyTaskUserState) -> dict:
    response = _call_gemini(state["prompt"])
    return {"llm_response": response}


def u_parse_result(state: DailyTaskUserState) -> dict:
    tasks    = state["candidate_tasks"]
    response = state.get("llm_response")
    if response:
        parsed = _extract_json(response)
        if parsed and parsed.get("taskId"):
            task_id = parsed["taskId"].replace("[", "").replace("]", "").strip()
            task    = next((t for t in tasks if t["id"] == task_id), None)
            if task:
                return {"selected_task": task, "personalized_desc": parsed.get("personalizedDescription", "")}
    return {"selected_task": None}


def u_fallback_select(state: DailyTaskUserState) -> dict:
    tasks     = state["candidate_tasks"]
    top_ids   = state["top_task_ids"]
    p         = state["user_profile"]

    # Try top tasks first, then highest score, then random
    for tid in top_ids:
        task = next((t for t in tasks if t["id"] == tid), None)
        if task:
            return {"selected_task": task, "personalized_desc": _build_fallback_desc(task, p)}

    scored = sorted(tasks, key=lambda t: state["task_prefs"].get(t["id"], {}).get("score", 1), reverse=True)
    if scored:
        task = scored[0]
        return {"selected_task": task, "personalized_desc": _build_fallback_desc(task, p)}

    if tasks:
        task = random.choice(tasks)
        return {"selected_task": task, "personalized_desc": _build_fallback_desc(task, p)}

    return {"selected_task": None, "error": "NO_SUITABLE_TASK_FOUND"}


def _build_fallback_desc(task: dict, profile: dict) -> str:
    pronoun     = profile["pronoun"]
    suffix      = profile["suffix"]
    level_label = profile["level_label"]
    streak_text = profile["streak_text"]
    base = (
        f"{pronoun} في بداية رحلتك البيئية، {task['title']} خطوة رائعة للانطلاق."
        if "بذرة" in level_label else
        f"واصل{suffix} تقدمك، {task['title']} تضيف نقاطاً وتفرق."
        if "نبتة" in level_label or "شجرة" in level_label else
        f"تحدٍّ جديد يا بطل{suffix} البيئة، {task['title']} في انتظارك."
    )
    if streak_text:
        base += f" حافظ{suffix} على سلسلتك 🔥"
    return base


def u_save_task(state: DailyTaskUserState) -> dict:
    task = state.get("selected_task")
    if not task:
        return {"success": False, "error": state.get("error", "NO_TASK")}

    desc = state.get("personalized_desc") or task.get("description", "")

    # ── إذا المهمة تحتاج اختبار قصير → اربطها بمقال ──
    article_id = None
    if task.get("validationStrategy") == "التحقق عبر اجراء اختبار قصير":
        try:
            articles = list(db.collection("articles")
                            .order_by("createdAt", direction=firestore.Query.DESCENDING)
                            .limit(10).stream())
            if articles:
                article_id = random.choice(articles).id
                print(f"   📰 Linked article: {article_id}")
        except Exception as e:
            print(f"   ⚠️ Article fetch error: {e}")

    try:
        task_doc = {
            **task,
            "description": desc,
            "createdAt":   firestore.SERVER_TIMESTAMP,
            "status":      "pending",
        }
        if article_id:
            task_doc["articleId"] = article_id

        db.collection("dailyTasks").document(state["user_id"]) \
          .collection("tasks").document(state["tomorrow"]).set(task_doc)
        print(f"   ✅ Saved: {task['title']}")
        return {"success": True}
    except Exception as e:
        print(f"   ❌ Save error: {e}")
        return {"success": False, "error": str(e)}

def u_update_view_count(state: DailyTaskUserState) -> dict:
    task = state.get("selected_task")
    if not task:
        return {}
    try:
        prefs_ref = db.collection("userTaskPreferences").document(state["user_id"])
        if prefs_ref.get().exists:
            prefs_ref.update({
                f"taskPreferences.{task['id']}.viewCount":    firestore.Increment(1),
                f"taskPreferences.{task['id']}.lastViewedAt": firestore.SERVER_TIMESTAMP,
                f"taskPreferences.{task['id']}.title":        task.get("title", ""),
                f"taskPreferences.{task['id']}.category":     task.get("category", ""),
            })
    except Exception as e:
        print(f"   ⚠️ viewCount error: {e}")
    return {}


# ══════════════════════════════════════════
# Conditional edges
# ══════════════════════════════════════════
def after_parse_user(state: DailyTaskUserState) -> str:
    return "fallback" if state.get("selected_task") is None else "save_task"


# ══════════════════════════════════════════
# Build per-user graph
# ══════════════════════════════════════════
def build_per_user_graph() -> Any:
    g = StateGraph(DailyTaskUserState)
    g.add_node("load_prefs",         u_load_prefs)
    g.add_node("load_ignored",       u_load_ignored)
    g.add_node("load_pending",       u_load_pending)
    g.add_node("load_yesterday",     u_load_yesterday)
    g.add_node("build_user_profile", u_build_profile)
    g.add_node("build_prompt",       u_build_prompt)
    g.add_node("call_llm",           u_call_llm)
    g.add_node("parse_result",       u_parse_result)
    g.add_node("fallback",           u_fallback_select)
    g.add_node("save_task",          u_save_task)
    g.add_node("update_view_count",  u_update_view_count)

    g.set_entry_point("load_prefs")
    g.add_edge("load_prefs",         "load_ignored")
    g.add_edge("load_ignored",       "load_pending")
    g.add_edge("load_pending",       "load_yesterday")
    g.add_edge("load_yesterday",     "build_user_profile")
    g.add_edge("build_user_profile", "build_prompt")
    g.add_edge("build_prompt",       "call_llm")
    g.add_edge("call_llm",           "parse_result")
    g.add_conditional_edges(
        "parse_result",
        after_parse_user,
        {"fallback": "fallback", "save_task": "save_task"},
    )
    g.add_edge("fallback",           "save_task")
    g.add_edge("save_task",          "update_view_count")
    g.add_edge("update_view_count",  END)
    return g.compile()


# ══════════════════════════════════════════
# Batch Orchestrator State
# ══════════════════════════════════════════
class BatchState(TypedDict):
    tomorrow: str
    current_month: str
    available_tasks: list
    users: list
    tasks_created: int
    total_users: int
    error: Optional[str]


def batch_load_tasks(state: BatchState) -> dict:
    print("📋 Batch Node 1: Loading tasks...")
    month  = state["current_month"]
    tasks  = []
    fallback = [
        {"id": "fallback_1", "title": "وفر الطاقة",  "description": "افصل الأجهزة الكهربائية", "category": "الكهرباء",        "points": 10},
        {"id": "fallback_2", "title": "دور المخلفات","description": "افصل البلاستيك عن الورق",  "category": "إعادة التدوير",   "points": 10},
        {"id": "fallback_3", "title": "امشِ اليوم",  "description": "امشِ إذا المسافة قريبة",    "category": "النقل المستدام",  "points": 10},
        {"id": "fallback_4", "title": "وفر الماء",   "description": "أغلق الصنبور أثناء تنظيف الأسنان", "category": "ترشيد الماء", "points": 10},
    ]
    try:
        for doc in db.collection("tasks").where("status", "==", "active").stream():
            t = doc.to_dict()
            if t.get("visible_from", "") > month:
                continue
            if t.get("expiry_month") and t["expiry_month"] < month:
                continue
            tasks.append({
                "id": doc.id, "title": t.get("title", ""),
                "description": t.get("description", ""), "category": t.get("category", ""),
                "points": t.get("points", 10),
                "validationStrategy": t.get("validationStrategy", ""),
                "calcMode": t.get("calcMode", ""),
                "emissionFactorRef": t.get("emissionFactorRef", ""),
            })
    except Exception as e:
        print(f"⚠️ load tasks error: {e}")

    result_tasks = tasks if tasks else fallback
    print(f"   Found {len(result_tasks)} tasks")
    if not result_tasks:
        return {"available_tasks": [], "error": "NO_TASKS_AVAILABLE"}
    return {"available_tasks": result_tasks}


def batch_load_users(state: BatchState) -> dict:
    print("👥 Batch Node 2: Loading users...")
    users = []
    try:
        for doc in db.collection("users").stream():
            d = doc.to_dict()
            if d.get("role") == "admin":
                continue
            users.append({"id": doc.id, **d})
    except Exception as e:
        print(f"⚠️ load users error: {e}")
        return {"users": [], "total_users": 0, "error": str(e)}

    print(f"   Found {len(users)} users")
    return {"users": users, "total_users": len(users)}


def batch_process_users(state: BatchState) -> dict:
    print("⚙️ Batch Node 3: Processing all users...")
    per_user_graph = build_per_user_graph()
    tasks_created  = 0

    for user in state["users"]:
        uid = user["id"]
        print(f"\n👤 Processing: {uid}")
        try:
            initial: DailyTaskUserState = {
                "user_id": uid, "user_data": user,
                "available_tasks": state["available_tasks"],
                "tomorrow": state["tomorrow"],
                "prefs_data": {}, "top_task_ids": [], "task_prefs": {},
                "ignored_ids": [], "pending_ids": [], "yesterday_id": None,
                "candidate_tasks": [], "user_profile": {},
                "prompt": "", "llm_response": None,
                "selected_task": None, "personalized_desc": "",
                "success": False, "error": None,
            }
            final = per_user_graph.invoke(initial)
            if final.get("success"):
                tasks_created += 1
        except Exception as e:
            print(f"   ❌ Failed for {uid}: {e}")

        time.sleep(8)  # rate limit

    return {"tasks_created": tasks_created}


def batch_check_tasks(state: BatchState) -> str:
    if state.get("error") == "NO_TASKS_AVAILABLE":
        return "end_error"
    return "load_users"


def build_batch_graph() -> Any:
    g = StateGraph(BatchState)
    g.add_node("load_tasks",      batch_load_tasks)
    g.add_node("load_users",      batch_load_users)
    g.add_node("process_users",   batch_process_users)

    g.set_entry_point("load_tasks")
    g.add_conditional_edges(
        "load_tasks",
        batch_check_tasks,
        {"end_error": END, "load_users": "load_users"},
    )
    g.add_conditional_edges(
        "load_users",
        lambda s: "end_error" if s.get("error") else "process_users",
        {"end_error": END, "process_users": "process_users"},
    )
    g.add_edge("process_users", END)
    return g.compile()


_batch_graph = build_batch_graph()


@functions_framework.http
def generate_daily_tasks_agent(request):
    if request.method == "OPTIONS":
        return ("", 204, {"Access-Control-Allow-Origin": "*",
                          "Access-Control-Allow-Methods": "POST, OPTIONS",
                          "Access-Control-Allow-Headers": "Content-Type, Authorization"})
    if request.method != "POST":
        return (json.dumps({"error": "POST only"}), 405, {"Content-Type": "application/json"})

    try:
        now      = datetime.now()
        tomorrow = (now + timedelta(days=1)).strftime("%Y-%m-%d")

        initial: BatchState = {
            "tomorrow":        tomorrow,
            "current_month":   now.strftime("%Y-%m"),
            "available_tasks": [],
            "users":           [],
            "tasks_created":   0,
            "total_users":     0,
            "error":           None,
        }

        final  = _batch_graph.invoke(initial)
        result = {
            "created":      final.get("tasks_created", 0),
            "total_users":  final.get("total_users", 0),
            "date":         tomorrow,
        }
        if final.get("error"):
            result["error"] = final["error"]

        status = 200 if "error" not in result else 500
        return (json.dumps(result, ensure_ascii=False, default=str), status,
                {"Content-Type": "application/json; charset=utf-8",
                 "Access-Control-Allow-Origin": "*"})

    except Exception as e:
        import traceback; traceback.print_exc()
        return (json.dumps({"error": str(e)}, ensure_ascii=False), 500,
                {"Content-Type": "application/json"})



################################################################


# ══════════════════════════════════════════
# Helpers
# ══════════════════════════════════════════
# ══════════════════════════════════════════
# State
# ══════════════════════════════════════════
class AdminAgentState(TypedDict):
    admin_id: str
    current_month: str

    # Analytics
    task_analytics: dict
    reports: dict
    user_insights: dict
    seasonal_patterns: dict
    season: dict

    # LLM
    prompt: str
    llm_response: Optional[str]

    # Recommendations
    recommendations: list

    # Auto-apply
    auto_mode: bool
    auto_results: dict
    carbon_target_result: dict

    # Summary
    summary: dict
    analytics: dict

    error: Optional[str]


# ══════════════════════════════════════════
# Node 1 — Task analytics
# ══════════════════════════════════════════
def node_task_analytics(state: AdminAgentState) -> dict:
    print("📊 Node 1: Task analytics...")
    active_tasks = []
    try:
        for doc in db.collection("tasks").where("status", "==", "active").stream():
            t = doc.to_dict()
            active_tasks.append({"id": doc.id, "title": t.get("title",""), "description": t.get("description",""), "category": t.get("category",""), "points": t.get("points",0)})
    except Exception as e:
        print(f"⚠️ active tasks: {e}")

    completed_count, ignored_count = {}, {}
    try:
        for doc in db.collection("userTasks").where("status","==","completed").stream():
            tid = doc.to_dict().get("taskId")
            if tid: completed_count[tid] = completed_count.get(tid,0) + 1
        for doc in db.collection("userTasks").where("ignored","==",True).stream():
            tid = doc.to_dict().get("taskId")
            if tid: ignored_count[tid] = ignored_count.get(tid,0) + 1
    except Exception as e:
        print(f"⚠️ task stats: {e}")

    def enrich(count_dict, limit):
        return sorted([{
            "id": k, "count": v,
            "title":       next((t["title"]       for t in active_tasks if t["id"]==k), k),
            "description": next((t["description"] for t in active_tasks if t["id"]==k), ""),
            "category":    next((t["category"]    for t in active_tasks if t["id"]==k), ""),
        } for k,v in count_dict.items()], key=lambda x:x["count"], reverse=True)[:limit]

    completed_ids   = set(completed_count.keys())
    zero_completion = [t for t in active_tasks if t["id"] not in completed_ids]

    analytics = {
        "totalActiveTasks":    len(active_tasks),
        "zeroCompletionTasks": len(zero_completion),
        "mostSuccessful":      enrich(completed_count, 5),
        "mostIgnored":         enrich(ignored_count,   5),
        "zeroTasks":           zero_completion[:5],
    }
    return {
        "task_analytics": analytics,
        "summary": {"totalTasks": len(active_tasks), "zeroCompletionTasks": len(zero_completion)},
        "analytics": {"problematicTasks": [], "problematicFacilities": []},
    }


# ══════════════════════════════════════════
# Node 2 — Reports
# ══════════════════════════════════════════
def node_get_reports(state: AdminAgentState) -> dict:
    print("🚨 Node 2: Getting reports...")
    task_reports, container_reports = [], []
    try:
        for doc in db.collection("taskReports").where("decision","==","pending").stream():
            d = doc.to_dict()
            task_reports.append({"taskId": d.get("taskId",""), "reason": d.get("reason","")})
        for doc in db.collection("facilityReports").where("status","==","pending").stream():
            d = doc.to_dict()
            container_reports.append({"facilityId": d.get("facilityID",""), "type": d.get("type","")})
    except Exception as e:
        print(f"⚠️ reports: {e}")

    # Aggregate
    task_rc, facility_rc = {}, {}
    for r in task_reports:
        tid = r["taskId"]
        if tid:
            task_rc.setdefault(tid, {"count":0,"reasons":[]})
            task_rc[tid]["count"] += 1
            if r["reason"]: task_rc[tid]["reasons"].append(r["reason"])
    for r in container_reports:
        fid = r["facilityId"]
        if fid:
            facility_rc.setdefault(fid, {"count":0,"types":[]})
            facility_rc[fid]["count"] += 1
            if r["type"]: facility_rc[fid]["types"].append(r["type"])

    problematic_tasks = []
    for tid, data in sorted(task_rc.items(), key=lambda x: x[1]["count"], reverse=True)[:5]:
        try:
            doc = db.collection("tasks").document(tid).get()
            if doc.exists:
                t = doc.to_dict()
                problematic_tasks.append({"taskId": tid, "title": t.get("title",""), "description": t.get("description",""), "reportCount": data["count"], "reasons": list(set(data["reasons"]))[:3]})
        except: pass

    problematic_facilities = []
    for fid, data in sorted(facility_rc.items(), key=lambda x: x[1]["count"], reverse=True)[:5]:
        try:
            doc = db.collection("facilities").document(fid).get()
            if doc.exists:
                f = doc.to_dict()
                types = data["types"]
                type_count = {}
                for t in types: type_count[t] = type_count.get(t,0)+1
                main_issue = max(type_count, key=type_count.get) if type_count else ""
                problematic_facilities.append({"facilityId": fid, "name": f.get("type","حاوية"), "address": f.get("address",""), "reportCount": data["count"], "mainIssue": main_issue})
        except: pass

    reports = {
        "pendingTaskReports":     len(task_reports),
        "pendingFacilityReports": len(container_reports),
        "problematicTasks":       problematic_tasks,
        "problematicFacilities":  problematic_facilities,
    }

    summary = state.get("summary", {})
    summary["pendingReports"] = len(task_reports) + len(container_reports)
    analytics = state.get("analytics", {})
    analytics.update({"problematicTasks": problematic_tasks, "problematicFacilities": problematic_facilities})

    return {"reports": reports, "summary": summary, "analytics": analytics}


# ══════════════════════════════════════════
# Node 3 — User insights
# ══════════════════════════════════════════
def node_user_insights(state: AdminAgentState) -> dict:
    print("👥 Node 3: User insights...")
    total_users, total_points, total_carbon = 0, 0, 0.0
    level_counts = {"seedling":0,"sprout":0,"tree":0,"guardian":0,"champion":0}

    try:
        for doc in db.collection("users").stream():
            d = doc.to_dict()
            if d.get("role") == "admin": continue
            total_users  += 1
            level = d.get("userLevelId","seedling")
            if level in level_counts: level_counts[level] += 1
            total_points += d.get("points",0)
            total_carbon += d.get("totalCarbonSaved",0)
    except Exception as e:
        print(f"⚠️ user insights: {e}")

    insights = {
        "totalUsers":  total_users,
        "levelCounts": level_counts,
        "avgPoints":   round(total_points / max(total_users,1), 1),
        "totalCarbon": round(total_carbon, 2),
    }
    summary = state.get("summary", {})
    summary["totalUsers"] = total_users
    return {"user_insights": insights, "summary": summary}


# ══════════════════════════════════════════
# Node 4 — Seasonal patterns
# ══════════════════════════════════════════
def node_seasonal_patterns(state: AdminAgentState) -> dict:
    print("📅 Node 4: Seasonal patterns...")
    now, one_year_ago = datetime.now(), datetime.now() - timedelta(days=365)
    monthly_stats = {}

    try:
        for doc in db.collection("userTasks").where("status","==","completed").stream():
            d = doc.to_dict()
            completed_at = d.get("completedAt")
            category     = d.get("category","") or d.get("taskCategory","")
            if not completed_at or not category: continue
            try:
                dt = (
                    datetime.fromtimestamp(completed_at._seconds)  if hasattr(completed_at, "_seconds")
                    else datetime.fromtimestamp(completed_at.timestamp()) if hasattr(completed_at, "timestamp")
                    else None
                )
                if not dt or dt < one_year_ago: continue
                month_key = dt.strftime("%Y-%m")
                monthly_stats.setdefault(month_key, {})
                monthly_stats[month_key][category] = monthly_stats[month_key].get(category,0) + 1
            except: pass
    except Exception as e:
        print(f"⚠️ seasonal: {e}")

    last_year_key  = f"{now.year-1}-{now.month:02d}"
    current_key    = now.strftime("%Y-%m")
    last_year_data = monthly_stats.get(last_year_key, {})
    current_data   = monthly_stats.get(current_key, {})

    top_category      = max(last_year_data, key=last_year_data.get) if last_year_data else ""
    top_category_cnt  = last_year_data.get(top_category, 0)

    trends = []
    for cat in set(list(last_year_data) + list(current_data)):
        lyc = last_year_data.get(cat, 0)
        cc  = current_data.get(cat, 0)
        if lyc == 0: continue
        pct = ((cc - lyc) / lyc) * 100
        if pct > 20:
            trends.append({"category": cat, "trend": "ارتفاع", "change": f"+{pct:.0f}%", "message": f"نشاط '{cat}' ارتفع {pct:.0f}%", "action": "add"})
        elif pct < -20:
            trends.append({"category": cat, "trend": "انخفاض", "change": f"{pct:.0f}%", "message": f"نشاط '{cat}' انخفض {abs(pct):.0f}%", "action": "add_or_modify"})

    monthly_totals = {m: sum(cats.values()) for m, cats in monthly_stats.items()}
    peak_months    = [m[0] for m in sorted(monthly_totals.items(), key=lambda x:x[1], reverse=True)[:3]]

    patterns = {
        "lastYearSameMonth":      last_year_key,
        "topCategoryLastYear":    top_category,
        "topCategoryCount":       top_category_cnt,
        "currentMonthVsLastYear": trends,
        "peakMonths":             peak_months,
        "suggestion": f"في {last_year_key}، كان '{top_category}' الأكثر نشاطاً ({top_category_cnt} إنجاز)" if top_category else "",
    }
    return {"seasonal_patterns": patterns}


# ══════════════════════════════════════════
# Node 5 — Weather / Season
# ══════════════════════════════════════════
def node_get_season(state: AdminAgentState) -> dict:
    print("🌤️ Node 5: Getting season/weather...")
    api_key = os.environ.get("WEATHER_API_KEY", "")
    month   = datetime.now().month

    def month_season():
        if month in [3,4,5]:   return {"season":"الربيع","emoji":"🌸"}
        if month in [6,7,8]:   return {"season":"الصيف","emoji":"☀️"}
        if month in [9,10,11]: return {"season":"الخريف","emoji":"🍂"}
        return {"season":"الشتاء","emoji":"❄️"}

    if not api_key:
        return {"season": month_season()}

    try:
        url = f"https://api.openweathermap.org/data/2.5/weather?lat=24.7136&lon=46.6753&appid={api_key}"
        with urllib.request.urlopen(urllib.request.Request(url), timeout=10) as resp:
            w    = json.loads(resp.read().decode())
            temp = round(w["main"]["temp"] - 273.15, 1)
            desc = w["weather"][0]["description"]
            hum  = w["main"]["humidity"]
            if temp >= 35:   season, emoji = "الصيف الحار", "🌡️"
            elif temp >= 25: season, emoji = "الصيف", "☀️"
            elif temp >= 15: season, emoji = "الربيع", "🌸"
            else:            season, emoji = "الشتاء", "❄️"
            return {"season": {"season":season,"emoji":emoji,"temp":temp,"description":desc,"humidity":hum}}
    except Exception as e:
        print(f"⚠️ Weather API: {e}")
        return {"season": month_season()}

# # ══════════════════════════════════════════
# # Node 5.5 — Fetch Articles from RSS  
# # ══════════════════════════════════════════
# def node_fetch_articles(state: AdminAgentState) -> dict:
#     print("📰 Node: Fetching articles from RSS...")
#     import re

#     articles_saved = 0

#     for feed_url in RSS_FEEDS:
#         try:
#             req = urllib.request.Request(
#                 feed_url,
#                 headers={"User-Agent": "Mozilla/5.0"}
#             )
#             with urllib.request.urlopen(req, timeout=10) as resp:
#                 content = resp.read().decode("utf-8")

#             # استخراج المقالات
#             items = re.findall(r'<item>(.*?)</item>', content, re.DOTALL)

#             for item in items[:3]:  # أول 3 مقالات من كل مصدر
#                 title   = re.search(r'<title><!\[CDATA\[(.*?)\]\]></title>', item)
#                 title   = title.group(1).strip() if title else ""
#                 if not title:
#                     title_plain = re.search(r'<title>(.*?)</title>', item)
#                     title = title_plain.group(1).strip() if title_plain else ""

#                 link    = re.search(r'<link>(.*?)</link>', item)
#                 link    = link.group(1).strip() if link else ""

#                 desc    = re.search(r'<description><!\[CDATA\[(.*?)\]\]></description>', item, re.DOTALL)
#                 desc    = desc.group(1).strip() if desc else ""
#                 # تنظيف HTML tags
#                 desc    = re.sub(r'<[^>]+>', '', desc).strip()

#                 image   = re.search(r'<media:content[^>]+url=["\']([^"\']+)["\']', item)
#                 image   = image.group(1) if image else ""

#                 if not title or not desc:
#                     continue

#                 # تحقق إن المقال ما موجود مسبقاً
#                 existing = list(db.collection("articles")
#                                 .where("title", "==", title)
#                                 .limit(1).get())
#                 if existing:
#                     continue

#                 # تحديد المصدر
#                 if "aljazeera" in feed_url:
#                     source = "الجزيرة"
#                 elif "bbc" in feed_url:
#                     source = "BBC عربي"
#                 elif "saudigazette" in feed_url:
#                     source = "Saudi Gazette"
#                 else:
#                     source = "مصدر بيئي"

#                 db.collection("articles").add({
#                     "title":      title,
#                     "content":    desc,
#                     "sourceName": source,
#                     "sourceUrl":  link,
#                     "urlToImage": image,
#                     "category":   "بيئة",
#                     "createdAt":  firestore.SERVER_TIMESTAMP,
#                     "autoFetched": True,
#                 })
#                 articles_saved += 1
#                 print(f"   ✅ Saved: {title[:40]}")

#         except Exception as e:
#             print(f"   ⚠️ RSS error ({feed_url}): {e}")

#     print(f"   📰 Total articles saved: {articles_saved}")
#     return {}
# ══════════════════════════════════════════
# Node 6 — Build prompt
# ══════════════════════════════════════════
def admin_node_build_prompt(state: AdminAgentState) -> dict:
    print("📝 Node 6: Building admin prompt...")
    analytics = state["task_analytics"]
    reports   = state["reports"]
    insights  = state["user_insights"]
    seasonal  = state["seasonal_patterns"]
    season    = state["season"]

    def task_lines(task_list, extra=""):
        return "\n".join([
            f"   • [{t['id']}] {t['title']} — {t.get('count',0)} مرة\n     الوصف: {t.get('description','')[:80]}"
            for t in task_list
        ]) or "   لا توجد"

    successful_text     = task_lines(analytics.get("mostSuccessful",[]))
    ignored_text        = task_lines(analytics.get("mostIgnored",[]))
    zero_text           = "\n".join([f"   • [{t['id']}] {t['title']}\n     الوصف: {t.get('description','')[:80]}" for t in analytics.get("zeroTasks",[])]) or "   لا توجد"
    task_reports_text   = "\n".join([f"   • [{t['taskId']}] {t['title']}: {t['reportCount']} بلاغ\n     الأسباب: {', '.join(t['reasons'][:2])}\n     الوصف: {t.get('description','')[:80]}" for t in reports.get("problematicTasks",[])]) or "   لا توجد"
    facility_text       = "\n".join([f"   • {f['name']} ({f['address']}): {f['reportCount']} بلاغ — {f['mainIssue']}" for f in reports.get("problematicFacilities",[])]) or "   لا توجد"
    trends_text         = "\n".join([f"   • {t['message']}" for t in seasonal.get("currentMonthVsLastYear",[])]) or "   لا توجد"

    prompt = f"""أنت مستشار بيئي ذكي. بناءً على البيانات التالية، قدم 5 توصيات عملية للإدمن.

الموسم: {season['season']} {season.get('emoji','')}

أداء المهام:
- إجمالي النشطة: {analytics.get('totalActiveTasks',0)}
- بدون إنجازات: {analytics.get('zeroCompletionTasks',0)}

الأكثر نجاحاً:
{successful_text}

الأكثر تجاهلاً:
{ignored_text}

بدون إنجازات:
{zero_text}

بلاغات معلقة:
- مهام: {reports.get('pendingTaskReports',0)}
- حاويات: {reports.get('pendingFacilityReports',0)}

مهام بلاغات متكررة:
{task_reports_text}

حاويات بلاغات متكررة:
{facility_text}

المستخدمون:
- الإجمالي: {insights.get('totalUsers',0)}
- متوسط النقاط: {insights.get('avgPoints',0)}
- كربون موفَّر: {insights.get('totalCarbon',0)} كغ

مقارنة بـ {seasonal.get('lastYearSameMonth','')}:
- الأكثر نشاطاً العام الماضي: {seasonal.get('topCategoryLastYear','لا توجد بيانات')}
- {seasonal.get('suggestion','')}
- أشهر الذروة: {', '.join(seasonal.get('peakMonths',[]))}

التغيرات:
{trends_text}

قواعد التوصيات:
1. بدون إنجازات → modify (وصف أكثر تحفيزاً)
2. كثيرة التجاهل → modify (وصف أكثر جاذبية)
3. بلاغات متكررة → review_reports
4. تصنيف كان نشطاً العام الماضي → add
5. تصنيف انخفض → add أو modify
6. إذا كان عدد المهام في تصنيف "المنتجات المحلية" قليلاً → add مهمة منتج محلي جديد

improvedDescription (modify): 15-20 كلمة، "أنت" خطاب مباشر، محفز، يذكر الفائدة البيئية، بدون إيموجيات
userDescription (add): 15-25 كلمة، وصف المهمة الجديدة للمستخدم مباشرة، بدون إيموجيات

أرجع JSON فقط:
{{
  "recommendations": [
    {{
      "type": "add | modify | review_reports",
      "category": "التصنيف",
      "title": "عنوان التوصية",
      "description": "شرح للإدمن",
      "taskId": "إن وجد",
      "improvedDescription": "للـ modify فقط",
      "userDescription": "للـ add فقط",
      "validationStrategy": "للـ add فقط",
      "facilityId": "إن وجد",
      "facilityName": "إن وجد",
      "facilityAddress": "إن وجد",
      "reportCount": 0
    }}
  ]
}}"""
    return {"prompt": prompt}


# ══════════════════════════════════════════
# Node 7 — Call LLM
# ══════════════════════════════════════════
def admin_node_call_llm(state: AdminAgentState) -> dict:
    print("🤖 Node 7: Calling Gemini...")
    response = _call_gemini(
        state["prompt"],
        temperature=0.4,
        max_tokens=2000
    )
    return {"llm_response": response}


# ══════════════════════════════════════════
# Node 8 — Parse recommendations
# ══════════════════════════════════════════
def node_parse_recommendations(state: AdminAgentState) -> dict:
    print("🔍 Node 8: Parsing recommendations...")
    response = state.get("llm_response")
    if response:
        parsed = _extract_json(response)
        if parsed:
            recs = parsed if isinstance(parsed, list) else parsed.get("recommendations", [])
            if recs:
                print(f"   ✅ Got {len(recs)} recommendations")
                return {"recommendations": recs}
    print("   ⚠️ Parse failed → fallback")
    return {"recommendations": []}


# ══════════════════════════════════════════
# Node 9 — Fallback recommendations
# ══════════════════════════════════════════
def _pick_validation_strategy(title: str, description: str = "") -> str:
    text = (title + " " + description).lower()
    knowledge_keywords = ["اقرأ", "تعلم", "توعية", "معلومات", "مقال", "نصائح", "وعي"]
    visual_keywords    = ["تدوير", "فرز", "حاوية", "تصنيف", "سلة"]
    
    # ← أضيفي هذا
    location_keywords  = ["محطة", "موقع", "قريب", "حافلة", "مترو", "سكوتر", "ركوب", "نقل"]
    
    k_score = sum(1 for kw in knowledge_keywords if kw in text)
    v_score = sum(1 for kw in visual_keywords    if kw in text)
    l_score = sum(1 for kw in location_keywords  if kw in text) 
    
    if l_score > k_score and l_score > v_score: 
        return "التحقق عبر الموقع"
    return "التحقق عبر اجراء اختبار قصير" if k_score > v_score else "التحقق عبر معالجة الصور"

def node_fallback_recommendations(state: AdminAgentState) -> dict:
    print("⚠️ Node 9: Fallback recommendations...")
    analytics = state["task_analytics"]
    reports   = state["reports"]
    seasonal  = state["seasonal_patterns"]
    season    = state["season"]
    recs      = []

    for task in analytics.get("zeroTasks",[])[:2]:
        recs.append({"type":"modify","category":task.get("category","غير محدد"),"title":f"تحسين: {task['title']}","description":f"'{task['title']}' بدون إنجازات","suggestion":"أعد صياغة الوصف","basedOn":"صفر إنجازات","taskId":task.get("id",""),"improvedDescription":f"🌱 أنت تستطيع إحداث فرق! {task['title']} خطوة بسيطة نحو بيئة أنظف ✨"})
    for task in analytics.get("mostIgnored",[])[:2]:
        recs.append({"type":"modify","category":task.get("category","غير محدد"),"title":f"تحسين: {task['title']}","description":f"'{task['title']}' تجاهل {task['count']} مرة","suggestion":"أعد صياغة الوصف","basedOn":f"تجاهل {task['count']} مرة","taskId":task.get("id",""),"improvedDescription":f"💚 {task['title']} — خطوة صغيرة منك، أثر كبير 🌍"})
    for f in reports.get("problematicFacilities",[])[:2]:
        recs.append({"type":"review_reports","category":"إعادة التدوير","title":f"مراجعة: {f['name']}","description":f"{f['reportCount']} بلاغ","suggestion":f"معاينة الحاوية: {f['mainIssue']}","basedOn":"بلاغات متكررة","facilityId":f.get("facilityId",""),"facilityName":f.get("name",""),"facilityAddress":f.get("address",""),"reportCount":f.get("reportCount",0)})

    top_cat = seasonal.get("topCategoryLastYear","")
    if top_cat:
        title = f"مهام {top_cat} الموسمية"
        recs.append({"type":"add","category":top_cat,"title":title,"description":seasonal.get("suggestion",""),"suggestion":f"أضف مهام في '{top_cat}'","basedOn":f"نمط من {seasonal.get('lastYearSameMonth','')}","userDescription":f"🌱 أنت تستطيع المساهمة! جرب مهمة {top_cat} اليوم ✨","validationStrategy":_pick_validation_strategy(title)})
    else:
        title = f"مهمة موسم {season['season']}"
        recs.append({"type":"add","category":"إعادة التدوير","title":title,"description":title,"suggestion":"أضف مهمة للموسم","basedOn":f"فصل {season['season']}","userDescription":f"🌿 استغل أجواء {season['season']} وابدأ بخطوة بيئية ✨","validationStrategy":_pick_validation_strategy(title)})

    return {"recommendations": recs}


# ══════════════════════════════════════════
# Node 10 — Save to Firestore
# ══════════════════════════════════════════
def node_save_to_firestore(state: AdminAgentState) -> dict:
    print("💾 Node 10: Saving to Firestore...")
    
    # ← دالة تحذف الـ null
    def remove_nulls(obj):
        if isinstance(obj, dict):
            return {k: remove_nulls(v) for k, v in obj.items() if v is not None}
        if isinstance(obj, list):
            return [remove_nulls(i) for i in obj]
        return obj
    
    clean_recs = remove_nulls(state["recommendations"][:12])
    
    try:
        season_data = state["season"]
        season_name = season_data.get("season", "") if isinstance(season_data, dict) else str(season_data)

        db.collection("adminRecommendations").document(state["current_month"]).set({
            "month":           state["current_month"],
            "season":          season_name,
            "recommendations": clean_recs,
            "analytics":       state.get("analytics", {}),
            "generatedAt":     firestore.SERVER_TIMESTAMP,
        })
        print("   ✅ Saved")
    except Exception as e:
        print(f"   ⚠️ Save failed: {e}")

    auto_mode = False
    try:
        doc = db.collection("users").document(state["admin_id"]).get()
        auto_mode = doc.to_dict().get("autoAgentMode", False) if doc.exists else False
    except Exception as e:
        print(f"   ⚠️ autoMode check: {e}")

    return {"auto_mode": auto_mode}


# ══════════════════════════════════════════
# Node 11 — Apply recommendations (auto)
# ══════════════════════════════════════════
def node_apply_auto(state: AdminAgentState) -> dict:
    if not state.get("auto_mode"):
        print("   ⏭️ Node 11: Auto mode OFF — skipping")
        return {"auto_results": {"applied": 0, "skipped": 0}}

    print("🤖 Node 11: Auto-applying recommendations...")
    now           = datetime.now()
    next_month_dt = datetime(now.year, now.month+1, 1) if now.month < 12 else datetime(now.year+1,1,1)
    next_month    = next_month_dt.strftime("%Y-%m")
    applied, skipped = 0, 0

    for rec in state["recommendations"][:12]:
        rec_type = rec.get("type","")
        try:
            if rec_type == "add":
                title = rec.get("title","").strip()
                if not title: skipped += 1; continue

                existing = list(db.collection("tasks").where("title","==",title).limit(1).get())
                if existing: skipped += 1; continue

                validation = rec.get("validationStrategy") or _pick_validation_strategy(title, rec.get("userDescription",""))
                db.collection("tasks").add({
                    "title":              title,
                    "title_normalized":   title.strip().lower(),
                    "description":        rec.get("userDescription") or rec.get("description",""),
                    "category":           rec.get("category",""),
                    "validationStrategy": validation,
                    "points":             rec.get("points",10),
                    "status":             "active",
                    "visible_from":       next_month,
                    "calcMode":           "perItem",
                    "autoGenerated":      True,
                    # "generatedAt":        firestore.SERVER_TIMESTAMP,
                })

                cat_name = rec.get("category", "")
                if cat_name:
                    existing_cat = list(db.collection("categories")
                                        .where("name", "==", cat_name)
                                        .limit(1).get())
                    if not existing_cat:
                        db.collection("categories").add({
                            "name":             cat_name,
                            "name_normalized":  cat_name.strip().lower(),
                            "parent":           "سلوك مباشر",
                            "description":      "تصنيف مضاف تلقائياً بواسطة الأيجنت",
                        })
                        print(f"   ✅ Auto-added category: {cat_name}")

                applied += 1

            elif rec_type == "modify":
                task_id  = rec.get("taskId","").strip()
                improved = rec.get("improvedDescription","").strip()
                if not task_id or not improved: skipped += 1; continue

                doc = db.collection("tasks").document(task_id).get()
                if not doc.exists: skipped += 1; continue

                db.collection("tasks").document(task_id).update({
                    "description":    improved,
                    # "autoModified":   True,
                    # "lastModifiedAt": firestore.SERVER_TIMESTAMP,
                })
                applied += 1

            elif rec_type in ["review_reports","delete"]:
                skipped += 1
            else:
                skipped += 1
        except Exception as e:
            print(f"   ❌ Auto-apply error: {e}")
            skipped += 1

    print(f"   ✅ Applied: {applied} | Skipped: {skipped}")
    return {"auto_results": {"applied": applied, "skipped": skipped}}


# ══════════════════════════════════════════
# Node 12 — Update carbon target
# ══════════════════════════════════════════
def node_update_carbon_target(state: AdminAgentState) -> dict:
    if not state.get("auto_mode"):
        print("   ⏭️ Node 12: Auto mode OFF — skipping carbon target")
        return {"carbon_target_result": {"updated": False}}

    print("🎯 Node 12: Updating carbon target...")
    try:
        insights      = state.get("user_insights", {})
        seasonal      = state.get("seasonal_patterns", {})
        total_users   = max(insights.get("totalUsers",1), 1)
        now           = datetime.now()
        current_month = now.strftime("%Y-%m")
        month_start = datetime(now.year, now.month, 1, tzinfo=timezone.utc)
        month_end   = datetime(now.year, now.month+1, 1, tzinfo=timezone.utc) if now.month < 12 else datetime(now.year+1, 1, 1, tzinfo=timezone.utc)

        monthly_carbon = 0.0
        try:
            from google.cloud.firestore_v1 import FieldFilter
            for doc in (db.collection("submissions")
                        .where(filter=FieldFilter("status","==","approved"))
                        .where(filter=FieldFilter("createdAt",">=",month_start))
                        .where(filter=FieldFilter("createdAt","<",month_end)).stream()):
                monthly_carbon += doc.to_dict().get("carbonSaved",0) or 0
        except:
            monthly_carbon = insights.get("totalCarbon",0.0)

        monthly_carbon = round(monthly_carbon, 2)
        avg_carbon     = round(monthly_carbon / total_users, 2)

        settings_doc   = db.collection("appSettings").document("carbonTarget").get()
        current_target = float(settings_doc.to_dict().get("target",50.0)) if settings_doc.exists else 50.0

        performance_ratio = avg_carbon / current_target if current_target > 0 else 0
        new_target, direction, reason = current_target, "unchanged", ""

        if performance_ratio >= 0.8:
            new_target = round(current_target * 1.20, 1)
            reason     = f"متوسط {avg_carbon} كجم ({round(performance_ratio*100)}% من الهدف) → رفع 20%"
            direction  = "up"
        elif performance_ratio < 0.4:
            new_target = round(current_target * 0.85, 1)
            reason     = f"متوسط {avg_carbon} كجم ({round(performance_ratio*100)}% من الهدف) → خفض 15%"
            direction  = "down"
        else:
            reason    = f"أداء مقبول ({round(performance_ratio*100)}%) — الهدف يبقى {current_target}"
            direction = "unchanged"

        season_name = state["season"].get("season","")
        if season_name == "الصيف" and direction == "unchanged":
            new_target = round(current_target * 0.92, 1); reason += " | صيف → خفض 8%"; direction="down"
        elif season_name == "الربيع" and direction == "unchanged":
            new_target = round(current_target * 1.05, 1); reason += " | ربيع → رفع 5%"; direction="up"

        last_year_avg  = 0.0
        last_year_month = seasonal.get("lastYearSameMonth","")
        try:
            doc = db.collection("appSettings").document(f"carbonTarget_{last_year_month}").get()
            if doc.exists: last_year_avg = float(doc.to_dict().get("avgCarbon",0.0))
        except: pass

        if last_year_avg > 0:
            pct = ((avg_carbon - last_year_avg) / last_year_avg) * 100
            if pct > 30:
                bonus = round(current_target * 0.10, 1); new_target = round(new_target+bonus,1); reason += f" | أفضل {round(pct)}% → +{bonus}"
            elif pct < -30:
                penalty = round(current_target * 0.08, 1); new_target = round(new_target-penalty,1); reason += f" | أضعف {round(abs(pct))}% → -{penalty}"

        new_target = max(5.0, min(new_target, 500.0))

        db.collection("appSettings").document("carbonTarget").set({
            "target": new_target, "prevTarget": current_target,
            "avgCarbon": avg_carbon, "monthlyCarbon": monthly_carbon,
            "totalUsers": total_users, "performanceRatio": round(performance_ratio*100,1),
            "reason": reason, "direction": direction,
            "season": season_name, "month": current_month,
            "lastYearMonth": last_year_month, "lastYearAvg": last_year_avg,
            "updatedAt": firestore.SERVER_TIMESTAMP, "updatedBy": "autoAgent",
        })
        db.collection("appSettings").document(f"carbonTarget_{current_month}").set({
            "target": new_target, "avgCarbon": avg_carbon,
            "monthlyCarbon": monthly_carbon, "month": current_month,
            "season": season_name, "savedAt": firestore.SERVER_TIMESTAMP,
        })

        print(f"   ✅ Carbon target: {current_target} → {new_target}")
        return {"carbon_target_result": {"updated":True,"prevTarget":current_target,"newTarget":new_target,"avgCarbon":avg_carbon,"direction":direction,"reason":reason}}

    except Exception as e:
        print(f"   ❌ Carbon target error: {e}")
        return {"carbon_target_result": {"updated":False,"error":str(e)}}


# ══════════════════════════════════════════
# Conditional edges
# ══════════════════════════════════════════
def after_parse_recs(state: AdminAgentState) -> str:
    return "fallback" if not state.get("recommendations") else "save_to_firestore"


# ══════════════════════════════════════════
# Build graph
# ══════════════════════════════════════════
def build_admin_graph() -> Any:
    g = StateGraph(AdminAgentState)

    g.add_node("task_analytics",        node_task_analytics)
    g.add_node("get_reports",           node_get_reports)
    g.add_node("user_insights",         node_user_insights)
    g.add_node("seasonal_patterns",     node_seasonal_patterns)
    g.add_node("get_season",            node_get_season)
    g.add_node("build_prompt",          admin_node_build_prompt)
    g.add_node("call_llm",              admin_node_call_llm)
    g.add_node("parse_recommendations", node_parse_recommendations)
    g.add_node("fallback",              node_fallback_recommendations)
    g.add_node("save_to_firestore",     node_save_to_firestore)
    g.add_node("apply_auto",            node_apply_auto)
    g.add_node("update_carbon_target",  node_update_carbon_target)

    g.set_entry_point("task_analytics")
    g.add_edge("task_analytics",    "get_reports")
    g.add_edge("get_reports",       "user_insights")
    g.add_edge("user_insights",     "seasonal_patterns")
    g.add_edge("seasonal_patterns", "get_season")
    g.add_edge("get_season",        "build_prompt")  # ← مباشرة
    g.add_edge("build_prompt",      "call_llm")
    g.add_edge("call_llm",          "parse_recommendations")

    g.add_conditional_edges(
        "parse_recommendations",
        after_parse_recs,
        {"fallback": "fallback", "save_to_firestore": "save_to_firestore"},
    )
    g.add_edge("fallback",             "save_to_firestore")
    g.add_edge("save_to_firestore",    "apply_auto")
    g.add_edge("apply_auto",           "update_carbon_target")
    g.add_edge("update_carbon_target", END)

    return g.compile()
_admin_graph = build_admin_graph()


@functions_framework.http
def admin_recommendations_agent(request):
    if request.method == "OPTIONS":
        return ("", 204, {"Access-Control-Allow-Origin": "*",
                          "Access-Control-Allow-Methods": "POST, OPTIONS",
                          "Access-Control-Allow-Headers": "Content-Type, Authorization"})
    if request.method != "POST":
        return (json.dumps({"error": "POST only"}), 405, {"Content-Type": "application/json"})

    try:
        data     = request.get_json(silent=True) or {}
        admin_id = data.get("adminId")
        if not admin_id:
            return (json.dumps({"error": "adminId مطلوب"}), 400, {"Content-Type": "application/json"})

        initial: AdminAgentState = {
            "admin_id":      admin_id,
            "current_month": datetime.now().strftime("%Y-%m"),
            "task_analytics": {}, "reports": {}, "user_insights": {},
            "seasonal_patterns": {}, "season": {},
            "prompt": "", "llm_response": None,
            "recommendations": [],
            "auto_mode": False, "auto_results": {}, "carbon_target_result": {},
            "summary": {},    # ← في الذاكرة فقط، ما تنحفظ في Firestore
            "analytics": {},  # ← في الذاكرة فقط
            "error": None, 
        }

        final  = _admin_graph.invoke(initial)
        result = {
            "month":           final.get("current_month"),
            "season":          final.get("season"),
            "recommendations": final.get("recommendations",[])[:12],
            "autoApplied":     final.get("auto_results",{}),
            "carbonTarget":    final.get("carbon_target_result",{}),
        }

        return (json.dumps(result, ensure_ascii=False, default=str), 200,
                {"Content-Type": "application/json; charset=utf-8",
                 "Access-Control-Allow-Origin": "*"})

    except Exception as e:
        import traceback; traceback.print_exc()
        return (json.dumps({"error": str(e)}, ensure_ascii=False), 500,
                {"Content-Type": "application/json"})



################################################################


def build_ground_truth() -> dict:
    """Ground Truth = المهام التي أكملها المستخدم فعلاً"""
    ground_truth = {}
    for doc in db.collection("userTasks").where("status","==","completed").stream():
        d   = doc.to_dict()
        uid = d.get("userId")
        tid = d.get("taskId")
        if uid and tid:
            ground_truth.setdefault(uid, []).append(tid)
    return ground_truth


def compute_precision_recall(ground_truth: dict) -> dict:
    precisions, recalls = [], []
    for doc in db.collection("userTaskPreferences").stream():
        uid       = doc.id
        top_tasks = doc.to_dict().get("topTasks", [])
        actual    = set(ground_truth.get(uid, []))
        if not top_tasks or not actual:
            continue
        recommended = set(top_tasks[:5])
        precisions.append(len(recommended & actual) / len(recommended))
        recalls.append(len(recommended & actual) / len(actual))

    avg_p = round(sum(precisions)/len(precisions), 2) if precisions else 0
    avg_r = round(sum(recalls)/len(recalls),    2) if recalls    else 0
    f1    = round(2*avg_p*avg_r/(avg_p+avg_r),  2) if (avg_p+avg_r) > 0 else 0
    return {"precision": avg_p, "recall": avg_r, "f1_score": f1}


def evaluate_agent_performance() -> dict:
    # 1. Completion rate
    n_completed = sum(1 for _ in db.collection("userTasks").where("status","==","completed").stream())
    n_ignored   = sum(1 for _ in db.collection("userTasks").where("ignored","==",True).stream())
    total       = n_completed + n_ignored
    completion_rate = round(n_completed/total*100,1) if total > 0 else 0

    # 2. Precision@1
    precision_scores = []
    for doc in db.collection("userTaskPreferences").stream():
        uid       = doc.id
        top_tasks = doc.to_dict().get("topTasks",[])
        if not top_tasks: continue
        completed = list(db.collection("userTasks")
                         .where("userId","==",uid)
                         .where("taskId","==",top_tasks[0])
                         .where("status","==","completed")
                         .limit(1).stream())
        precision_scores.append(1 if completed else 0)
    precision_at_1 = round(sum(precision_scores)/len(precision_scores),2) if precision_scores else round(completion_rate/100,2)

    # 3. Wilson Score avg
    scores = []
    for doc in db.collection("userTaskPreferences").stream():
        for tid, stats in doc.to_dict().get("taskPreferences",{}).items():
            s = stats.get("score")
            if s is not None: scores.append(s)
    avg_wilson = round(sum(scores)/len(scores),2) if scores else 0

    # 4. Diversity
    categories, task_cache = {}, {}
    for doc in db.collection("tasks").stream():
        task_cache[doc.id] = doc.to_dict().get("category","unknown")
    for doc in db.collection("userTasks").where("status","==","completed").stream():
        cat = task_cache.get(doc.to_dict().get("taskId",""),"unknown")
        categories[cat] = categories.get(cat,0) + 1

    # 5. Carbon
    total_carbon = sum(
        (doc.to_dict().get("carbonSaved",0) or 0)
        for doc in db.collection("submissions").where("status","==","approved").stream()
    )

    # 6. Carbon target ratio
    target_doc     = db.collection("appSettings").document("carbonTarget").get()
    target_data    = target_doc.to_dict() if target_doc.exists else {}
    perf_ratio     = target_data.get("performanceRatio",0)
    monthly_carbon = target_data.get("monthlyCarbon",0)

    # 7. Ground truth P/R/F1
    ground_truth = build_ground_truth()
    pr_metrics   = compute_precision_recall(ground_truth)

    return {
        "task_completion_rate":  f"{completion_rate}%",
        "precision_at_1":        precision_at_1,
        "wilson_score_avg":      f"{avg_wilson}/10",
        "category_diversity":    len(categories),
        "category_breakdown":    categories,
        "precision":             pr_metrics["precision"],
        "recall":                pr_metrics["recall"],
        "f1_score":              pr_metrics["f1_score"],
        "total_carbon_saved_kg": round(total_carbon,2),
        "monthly_carbon_kg":     round(monthly_carbon,2),
        "carbon_target_ratio":   f"{perf_ratio}%",
        "total_interactions":    total,
        "n_completed":           n_completed,
        "n_ignored":             n_ignored,
        "ground_truth_users":    len(ground_truth),
        "evaluated_at":          datetime.now().strftime("%Y-%m-%d %H:%M"),
    }


@functions_framework.http
def evaluate_agent(request):
    try:
        result = evaluate_agent_performance()
        return (json.dumps(result, ensure_ascii=False), 200, {"Content-Type": "application/json"})
    except Exception as e:
        return (json.dumps({"error": str(e)}, ensure_ascii=False), 500, {"Content-Type": "application/json"})