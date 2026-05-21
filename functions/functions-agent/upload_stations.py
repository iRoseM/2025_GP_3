# upload_stations.py
import json
import os
import firebase_admin
from firebase_admin import firestore, credentials

# ============================================
# تأكد من وجود ملف Service Account Key
# ============================================
# الطريقة الأولى: إذا كنت مشغل gcloud auth login
if not firebase_admin._apps:
    try:
        firebase_admin.initialize_app()
        print("✅ Firebase initialized with default credentials")
    except:
        # الطريقة الثانية: استخدم ملف JSON خاص
        # حمّل المفتاح من Firebase Console > Project Settings > Service Accounts
        # وحطه في نفس المجلد
        cred_path = "serviceAccountKey.json"
        if os.path.exists(cred_path):
            cred = credentials.Certificate(cred_path)
            firebase_admin.initialize_app(cred)
            print(f"✅ Firebase initialized with {cred_path}")
        else:
            print("❌ No credentials found. Run: gcloud auth application-default login")
            exit(1)

db = firestore.client()

# ============================================
# رفع البيانات إلى Firestore
# ============================================
def upload_stations():
    base = os.path.join(os.path.dirname(__file__), "assets", "data")
    
    # قائمة الملفات والمجموعات المقابلة
    files_to_upload = [
        ("bus_stations.json", "busStations"),
        ("metro_stations.json", "metroStations"),
        ("plastic_bins.json", "plasticBins"),
        ("paper_bins.json", "paperBins"),
        ("food_bins.json", "foodBins"),
        ("clothing_bins.json", "clothingBins"),
        ("rvm_bins.json", "rvmBins"),
    ]
    
    for filename, collection_name in files_to_upload:
        filepath = os.path.join(base, filename)
        if not os.path.exists(filepath):
            print(f"⚠️ {filename} not found — skipping")
            continue
        
        with open(filepath, encoding="utf-8") as f:
            data = json.load(f)
        
        # تأكد أن البيانات بصيغة list
        stations = data if isinstance(data, list) else data.get("stations") or data.get("features") or []
        
        count = 0
        for station in stations:
            # استخراج الإحداثيات
            lat = station.get("lat") or station.get("latitude")
            lng = station.get("lng") or station.get("longitude") or station.get("lon")
            
            # إذا كان الملف بصيغة GeoJSON (features)
            if not lat and station.get("geometry"):
                coords = station["geometry"].get("coordinates", [])
                if len(coords) >= 2:
                    lng, lat = coords[0], coords[1]
            
            if lat and lng:
                db.collection(collection_name).add({
                    "name": station.get("name") or station.get("station_name") or station.get("title", "بدون اسم"),
                    "address": station.get("address", ""),
                    "lat": float(lat),
                    "lng": float(lng),
                    "original_data": station  # احتفظ بالبيانات الأصلية للرجوع لها
                })
                count += 1
        
        print(f"✅ Uploaded {count} documents to '{collection_name}'")
    
    print("\n🎉 All stations uploaded successfully!")

if __name__ == "__main__":
    upload_stations()