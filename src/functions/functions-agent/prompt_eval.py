import json
import time
import urllib.request
import os
import re
from collections import defaultdict

# ─── المهام الحقيقية ────────────────────────────────────────────
real_tasks = [
    ("bJjITCm7ZWlmzEk2QNPr", "قراءة خبر بيئي",                          "التوعية والاستدامة"),
    ("f2SYfX2lEjDyb31Ugwqg", "إعادة تدوير علب البلاستيك (قوارير الماء)", "إعادة التدوير"),
    ("fTVRcGbemEc6C1JMU2v0", "استخدام الميترو",                           "وسائل النقل المستدامة"),
]

valid_task_ids = [t[0] for t in real_tasks]
task_list      = "\n".join([f"[{tid}] {title} - {cat}" for tid, title, cat in real_tasks])

# ─── حالات الاختبار ─────────────────────────────────────────────
test_cases = [
    {
        "name":   "بدون أماكن قريبة",
        "nearby": [],
        "time":   "المساء — وقت ممتاز للتدوير",
    },
    {
        "name":   "مع حاوية بلاستيك قريبة",
        "nearby": [{"type": "حاوية بلاستيك", "distance": 0.8, "name": "حاوية الملز", "address": "حي الملز"}],
        "time":   "الصباح — وقت النشاط والحركة",
    },
    {
        "name":   "مع محطة مترو قريبة",
        "nearby": [{"type": "محطة مترو", "distance": 0.3, "name": "محطة الملز", "address": "خط 1"}],
        "time":   "الصباح — وقت النشاط والحركة",
    },
]

# ══════════════════════════════════════════
# نسخ البرومت
# ══════════════════════════════════════════

def make_prompt_no_rules(task_list, nearby, time_label):
    """بدون قواعد — Zero-shot بسيط"""
    nearby_text = "\n".join([f"• {p['type']} — {p['distance']} كم" for p in nearby]) or "لا توجد أماكن قريبة"
    return f"""أنت مساعد بيئي. اختر مهمة مناسبة للمستخدم.

الوقت: {time_label}
الأماكن القريبة: {nearby_text}
المهام المتاحة:
{task_list}

أرجع JSON فقط:
{{"taskId": "...", "reasoning": "...", "personalizedDescription": "..."}}"""


def make_prompt_with_rules(task_list, nearby, time_label):
    """مع قواعد صريحة — البرومت الحالي المختار"""
    if not nearby:
        nearby_section = "⚠️ لا توجد أي أماكن أو حاويات أو محطات قريبة نهائياً.\nلا تذكر أي مكان في الوصف إطلاقاً."
    else:
        nearby_list = "\n".join([f"• {p['type']} — {p['distance']} كم — {p.get('address','')}" for p in nearby])
        nearby_section = f""" الأماكن القريبة الفعلية (فقط هذه موجودة):
{nearby_list}
🔴 لا تختلق أماكن أو مسافات غير موجودة في القائمة."""

    return f"""أنت مساعد بيئي ذكي ومحفز. اختر مهمة واحدة وصِغ وصفاً شخصياً.

الوقت: {time_label}

{nearby_section}

المهام المتاحة:
{task_list}

قواعد الوصف:
- إذا "لا توجد أماكن قريبة" → لا تذكر أي حاوية أو محطة أو مسافة إطلاقاً
- فقط اذكر الأماكن الموجودة في القائمة أعلاه
- لا تختلق مسافات أو أرقام
- لا تستخدم أكثر من إيموجي واحد

أرجع JSON فقط:
{{"taskId": "...", "reasoning": "...", "personalizedDescription": "..."}}"""


def make_prompt_few_shot(task_list, nearby, time_label):
    """مع أمثلة Few-shot"""
    if not nearby:
        nearby_section = "لا توجد أماكن قريبة"
    else:
        nearby_section = "\n".join([f"• {p['type']} — {p['distance']} كم" for p in nearby])

    return f"""أنت مساعد بيئي ذكي. اختر مهمة واحدة مناسبة.

=== مثال 1: بدون أماكن ===
الأماكن: لا توجد أماكن قريبة
المهمة: قراءة خبر بيئي
 الوصف الصحيح: "كن على اطلاع! اقرأ خبراً بيئياً اليوم وابدأ رحلتك نحو وعي أعمق"
 الوصف الخاطئ: "حاوية بلاستيك قريبة 0.5 كم منك!" ← خطأ لأنه لا توجد أماكن

=== مثال 2: مع حاوية ===
الأماكن: حاوية بلاستيك — 0.8 كم
المهمة: إعادة تدوير البلاستيك
 الوصف الصحيح: " حاوية بلاستيك على بعد 0.8 كم! فرصة رائعة لإعادة التدوير الآن"
 الوصف الخاطئ: "محطة مترو قريبة منك!" ← خطأ لأن المهمة تدوير وليس نقل
=== نهاية الأمثلة ===

الوقت: {time_label}
الأماكن القريبة:
{nearby_section}

المهام المتاحة:
{task_list}

أرجع JSON فقط:
{{"taskId": "...", "reasoning": "...", "personalizedDescription": "..."}}"""


def make_prompt_positive_only(task_list, nearby, time_label):
    """قواعد إيجابية فقط (بدون نفي)"""
    if not nearby:
        nearby_section = "لا توجد أماكن قريبة"
    else:
        nearby_section = "\n".join([f"• {p['type']} — {p['distance']} كم" for p in nearby])

    return f"""أنت مساعد بيئي ذكي. اختر مهمة واحدة.

الوقت: {time_label}
الأماكن القريبة: {nearby_section}
المهام: {task_list}

قواعد:
- اذكر فقط الأماكن الموجودة في القائمة
- الوصف يتطابق مع نوع المهمة
- إيموجي واحد فقط

أرجع JSON فقط:
{{"taskId": "...", "reasoning": "...", "personalizedDescription": "..."}}"""


# ══════════════════════════════════════════
# استدعاء Gemini
# ══════════════════════════════════════════

def call_gemini(prompt: str, temperature: float = 0.2) -> dict:
    api_key = os.environ.get("GEMINI_API_KEY", "")
    if not api_key:
        return {"text": "", "latency_ms": 0, "error": "GEMINI_API_KEY not set"}

    url  = f"https://generativelanguage.googleapis.com/v1/models/gemini-2.0-flash:generateContent?key={api_key}"
    body = json.dumps({
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {"temperature": temperature, "maxOutputTokens": 600}
    }).encode()

    start = time.time()
    try:
        req = urllib.request.Request(url, data=body,
            headers={"Content-Type": "application/json"}, method="POST")
        with urllib.request.urlopen(req, timeout=30) as resp:
            result  = json.loads(resp.read().decode())
            text    = result["candidates"][0]["content"]["parts"][0]["text"]
            latency = round((time.time() - start) * 1000)
            return {"text": text, "latency_ms": latency, "error": None}
    except Exception as e:
        return {"text": "", "latency_ms": 0, "error": str(e)}


# ══════════════════════════════════════════
# تقييم الرد
# ══════════════════════════════════════════

def evaluate_response(response_text: str, nearby: list, valid_task_ids: list) -> dict:
    # 1. JSON parse
    try:
        clean  = response_text.replace("```json","").replace("```","").strip()
        parsed = json.loads(clean[clean.index("{"):clean.rindex("}")+1])
        json_ok = True
    except:
        parsed  = {}
        json_ok = False

    # 2. TaskID valid
    task_id       = parsed.get("taskId","").strip("[]").strip()
    task_id_valid = task_id in valid_task_ids

    # 3. Hallucination (fake location)
    desc           = parsed.get("personalizedDescription", "")
    fake_location  = False
    fake_reason    = ""

    if not nearby:
        # لو ما في أماكن → أي ذكر لمكان أو مسافة = وهمي
        if re.search(r'\d+\.?\d*\s*كم', desc):
            fake_location = True
            fake_reason   = "ذكر مسافة بدون أماكن حقيقية"
        for word in ["حاوية", "محطة", "قريب من", "على بعد"]:
            if word in desc:
                fake_location = True
                fake_reason   = f"ذكر '{word}' بدون أماكن حقيقية"
                break
    else:
        # لو في أماكن → تحقق إن المسافة مذكورة صحيحة
        distances_in_desc = re.findall(r'\d+\.?\d*\s*كم', desc)
        real_distances    = [str(p.get("distance","")) for p in nearby]
        real_types        = [p.get("type","") for p in nearby]

        if distances_in_desc:
            found = any(any(d in num for d in real_distances) for num in distances_in_desc)
            if not found:
                fake_location = True
                fake_reason   = f"مسافة وهمية: {distances_in_desc}"

        # تحقق إن نوع المكان المذكور موجود فعلاً
        for fake_type in ["حاوية طعام","حاوية بلاستيك","حاوية ورق","محطة مترو","محطة باص"]:
            if fake_type in desc and not any(fake_type in rt for rt in real_types):
                fake_location = True
                fake_reason   = f"ذكر '{fake_type}' وهو غير موجود في القائمة"
                break

    return {
        "json_ok":       json_ok,
        "task_id_valid": task_id_valid,
        "fake_location": fake_location,
        "fake_reason":   fake_reason,
        "task_id":       task_id,
        "description":   desc,
        "raw":           response_text[:200],
    }


# ══════════════════════════════════════════
# تشغيل المقارنة
# ══════════════════════════════════════════

def run_comparison():
    variants = [
        ("① بدون قواعد (Zero-shot)",      make_prompt_no_rules,      0.2),
        ("② قواعد إيجابية فقط",           make_prompt_positive_only, 0.2),
        ("③ قواعد كاملة (البرومت الحالي)", make_prompt_with_rules,    0.2),
        ("④ Few-shot مع أمثلة",           make_prompt_few_shot,      0.2),
        ("⑤ قواعد كاملة temp=0.0",        make_prompt_with_rules,    0.0),
        ("⑥ قواعد كاملة temp=0.7",        make_prompt_with_rules,    0.7),
    ]

    all_results = []

    for case in test_cases:
        print(f"\n{'='*60}")
        print(f"Test Case: {case['name']}")
        print(f"{'='*60}")

        for variant_name, prompt_fn, temp in variants:
            print(f"\n  🔹 {variant_name}  (temp={temp})")

            prompt = prompt_fn(task_list, case["nearby"], case["time"])
            resp   = call_gemini(prompt, temperature=temp)

            if resp["error"]:
                print(f"      Error: {resp['error']}")
                continue

            ev = evaluate_response(resp["text"], case["nearby"], valid_task_ids)

            row = {
                "test_case":     case["name"],
                "variant":       variant_name,
                "temperature":   temp,
                "json_ok":       ev["json_ok"],
                "task_id_valid": ev["task_id_valid"],
                "fake_location": ev["fake_location"],
                "fake_reason":   ev["fake_reason"],
                "latency_ms":    resp["latency_ms"],
                "task_id":       ev["task_id"],
                "description":   ev["description"],
            }
            all_results.append(row)

            j_icon  = "" if ev["json_ok"]       else ""
            t_icon  = "" if ev["task_id_valid"]  else ""
            h_icon  = "" if not ev["fake_location"] else ""

            print(f"     {j_icon} JSON Parse:    {ev['json_ok']}")
            print(f"     {t_icon} TaskID Valid:  {ev['task_id_valid']}  ({ev['task_id']})")
            print(f"     {h_icon} No Hallucination: {not ev['fake_location']}"
                  + (f"  ← {ev['fake_reason']}" if ev["fake_location"] else ""))
            print(f"      Latency:        {resp['latency_ms']} ms")
            print(f"     Desc: {ev['description'][:100]}")

            time.sleep(4)  # rate limit

    # ── ملخص ────────────────────────────────────────────────────
    print(f"\n\n{'='*60}")
    print("FINAL SUMMARY")
    print(f"{'='*60}")
    print(f"{'Variant':<35} {'JSON':>6} {'TaskID':>8} {'No-Halluc':>11} {'Latency':>9}")
    print("-"*73)

    by_variant = defaultdict(list)
    for r in all_results:
        by_variant[r["variant"]].append(r)

    summary_rows = []
    for variant_name, _, _ in variants:
        rows = by_variant.get(variant_name, [])
        if not rows:
            continue
        n = len(rows)
        json_rate  = sum(r["json_ok"]           for r in rows) / n * 100
        task_rate  = sum(r["task_id_valid"]      for r in rows) / n * 100
        no_hall    = sum(not r["fake_location"]  for r in rows) / n * 100
        avg_lat    = sum(r["latency_ms"]         for r in rows) / n

        print(f"{variant_name:<35} {json_rate:>5.0f}%  {task_rate:>6.0f}%  {no_hall:>9.0f}%  {avg_lat:>7.0f}ms")

        summary_rows.append({
            "variant":            variant_name,
            "json_parse_rate":    f"{json_rate:.0f}%",
            "task_id_valid_rate": f"{task_rate:.0f}%",
            "no_hallucination":   f"{no_hall:.0f}%",
            "avg_latency_ms":     f"{avg_lat:.0f}",
        })

    # ── حفظ ─────────────────────────────────────────────────────
    output = {"summary": summary_rows, "details": all_results}
    with open("prompt_eval_results.json", "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)

    print(f"\n Results saved → prompt_eval_results.json")
    return summary_rows
# ══════════════════════════════════════════
# اختبار Temperature — نفس البرومت 3 مرات
# ══════════════════════════════════════════

def run_temperature_test():
    prompt = make_prompt_with_rules(task_list, [], "الصباح — وقت النشاط والحركة")

    print(f"\n\n{'='*60}")
    print("🌡️  TEMPERATURE CONSISTENCY TEST")
    print("نفس البرومت (بدون أماكن) — 3 مرات لكل temperature")
    print(f"{'='*60}")

    temp_results = {}

    for temp in [0.0, 0.2, 0.7]:
        print(f"\n  Temperature = {temp}")
        print(f"  {'-'*40}")
        descriptions = []

        for run in range(3):
            resp = call_gemini(prompt, temperature=temp)
            if resp["error"]:
                print(f"    Run {run+1}: Error — {resp['error']}")
                continue
            try:
                clean  = resp["text"].replace("```json","").replace("```","").strip()
                parsed = json.loads(clean[clean.index("{"):clean.rindex("}")+1])
                desc   = parsed.get("personalizedDescription","")
                descriptions.append(desc)
                print(f"    Run {run+1}: {desc[:90]}")
            except:
                print(f"    Run {run+1}: JSON parse failed")
            time.sleep(4)

        # قياس التنوع — لو كل الردود متطابقة → تنوع 0%
        unique = len(set(descriptions))
        diversity = round((unique - 1) / max(len(descriptions) - 1, 1) * 100)
        print(f"  → التنوع: {unique}/{len(descriptions)} ردود مختلفة ({diversity}%)")
        temp_results[temp] = {"descriptions": descriptions, "diversity": diversity}

    print(f"\n\n{'='*60}")
    print("TEMPERATURE SUMMARY")
    print(f"{'='*60}")
    print(f"  temp=0.0 → تنوع: {temp_results.get(0.0,{}).get('diversity','N/A')}%  (حتمي — مناسب للاختبار)")
    print(f"  temp=0.2 → تنوع: {temp_results.get(0.2,{}).get('diversity','N/A')}%  (متوازن — المختار ✓)")
    print(f"  temp=0.7 → تنوع: {temp_results.get(0.7,{}).get('diversity','N/A')}%  (إبداعي — قد ينحرف)")

    return temp_results

if __name__ == "__main__":
    print("=" * 60)
    print("PART 1 — Prompt Variant Comparison")
    print("=" * 60)
    run_comparison()

    print("\n\n")
    print("=" * 60)
    print("PART 2 — Temperature Consistency Test")
    print("=" * 60)
    run_temperature_test()