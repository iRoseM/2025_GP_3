# main.py - Cloud Function for Task Verification
# Deploy to Google Cloud Functions

import os
import torch
import torch.nn as nn
import timm
from PIL import Image
import io
import base64
from google.cloud import storage
import functions_framework
from flask import jsonify
import torchvision.transforms as transforms

# ===============================
# Model Definition (same as training)
# ===============================
class TaskModel(nn.Module):
    def __init__(self, num_classes=9):
        super().__init__()
        self.backbone = timm.create_model('efficientnet_b0', pretrained=False)
        in_features = self.backbone.classifier.in_features
        self.backbone.classifier = nn.Sequential(
            nn.Dropout(0.3),
            nn.Linear(in_features, 512),
            nn.ReLU(),
            nn.Dropout(0.2),
            nn.Linear(512, num_classes)
        )
    
    def forward(self, x):
        return self.backbone(x)

# ===============================
# Global variables (loaded once)
# ===============================
model = None
device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')

CLASS_NAMES = [
    'scooter',
    'rvm', 
    'plastic',
    'paper',
    'metro',
    'food',
    'cloth',
    'bus',
    'bicycle'
]

DISPLAY_NAMES_AR = {
    'scooter': 'سكوتر ',
    'rvm': 'آلة إعادة التدوير ',
    'plastic': 'بلاستيك ',
    'paper': 'ورق ',
    'metro': 'مترو ',
    'food': 'طعام ',
    'cloth': 'ملابس ',
    'bus': 'باص ',
    'bicycle': 'دراجة '
}

# Image transforms (same as validation)
transform = transforms.Compose([
    transforms.Resize((224, 224)),
    transforms.ToTensor(),
    transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225])
])

def load_model():
    """Load model from Cloud Storage bucket"""
    global model
    if model is not None:
        return model
    
    # Option 1: Load from local file (if deployed with model)
    model_path = 'task_model.pth'
    
    # Option 2: Load from Cloud Storage
    # bucket_name = 'your-bucket-name'
    # blob_name = 'models/task_model.pth'
    # storage_client = storage.Client()
    # bucket = storage_client.bucket(bucket_name)
    # blob = bucket.blob(blob_name)
    # blob.download_to_filename('/tmp/task_model.pth')
    # model_path = '/tmp/task_model.pth'
    
    model = TaskModel(num_classes=9)
    checkpoint = torch.load(model_path, map_location=device)
    model.load_state_dict(checkpoint['model'])
    model.to(device)
    model.eval()
    
    print("Model loaded successfully")
    return model

def predict_image(image_bytes, threshold=0.7):
    """
    Predict task type from image bytes
    
    Args:
        image_bytes: Raw image bytes
        threshold: Confidence threshold for verification
    
    Returns:
        dict: Prediction results
    """
    global model
    if model is None:
        model = load_model()
    
    # Load and transform image
    image = Image.open(io.BytesIO(image_bytes)).convert('RGB')
    image_tensor = transform(image).unsqueeze(0).to(device)
    
    # Predict
    with torch.no_grad():
        outputs = model(image_tensor)
        probs = torch.softmax(outputs, dim=1)[0]
        confidence, predicted = probs.max(0)
    
    pred_idx = predicted.item()
    conf = confidence.item()
    
    return {
        'success': True,
        'task_id': pred_idx,
        'task_name': CLASS_NAMES[pred_idx],
        'task_name_ar': DISPLAY_NAMES_AR[CLASS_NAMES[pred_idx]],
        'confidence': round(conf, 4),
        'confidence_percent': f"{conf * 100:.1f}%",
        'verified': conf >= threshold,
        'all_predictions': {
            CLASS_NAMES[i]: round(probs[i].item(), 4) 
            for i in range(len(CLASS_NAMES))
        }
    }

# ===============================
# Cloud Function Entry Point
# ===============================
@functions_framework.http
def verify_task(request):
    """
    HTTP Cloud Function for task verification
    
    Request JSON:
        - image_base64: Base64 encoded image string
        - image_url: URL to image in Cloud Storage (alternative)
        - threshold: Optional confidence threshold (default 0.7)
        - expected_task: Optional expected task name for validation
    
    Returns:
        JSON response with prediction results
    """
    # CORS headers
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type',
    }
    
    # Handle preflight
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    try:
        request_json = request.get_json(silent=True)
        
        if not request_json:
            return jsonify({
                'success': False,
                'error': 'No JSON data provided'
            }), 400, headers
        
        # Get threshold
        threshold = request_json.get('threshold', 0.7)
        expected_task = request_json.get('expected_task', None)
        
        # Get image bytes
        image_bytes = None
        
        # Option 1: Base64 encoded image
        if 'image_base64' in request_json:
            image_base64 = request_json['image_base64']
            # Remove data URL prefix if present
            if ',' in image_base64:
                image_base64 = image_base64.split(',')[1]
            image_bytes = base64.b64decode(image_base64)
        
        # Option 2: Image URL from Cloud Storage
        elif 'image_url' in request_json:
            image_url = request_json['image_url']
            # Download from Cloud Storage
            storage_client = storage.Client()
            # Parse gs:// URL or https:// URL
            if image_url.startswith('gs://'):
                parts = image_url.replace('gs://', '').split('/', 1)
                bucket_name, blob_name = parts[0], parts[1]
                bucket = storage_client.bucket(bucket_name)
                blob = bucket.blob(blob_name)
                image_bytes = blob.download_as_bytes()
            else:
                import requests
                response = requests.get(image_url, timeout=10)
                image_bytes = response.content
        
        if image_bytes is None:
            return jsonify({
                'success': False,
                'error': 'No image provided. Use image_base64 or image_url'
            }), 400, headers
        
        # Run prediction
        result = predict_image(image_bytes, threshold)
        
        # Check if matches expected task
        if expected_task:
            expected_lower = expected_task.lower().strip()
            predicted_lower = result['task_name'].lower()
            result['matches_expected'] = (expected_lower == predicted_lower)
            result['expected_task'] = expected_task
        
        return jsonify(result), 200, headers
    
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500, headers


# ===============================
# For local testing
# ===============================
if __name__ == '__main__':
    # Test with a local image
    print("Loading model...")
    load_model()
    
    # Test prediction
    test_image_path = 'test_image.jpg'  # Change to your test image
    if os.path.exists(test_image_path):
        with open(test_image_path, 'rb') as f:
            image_bytes = f.read()
        
        result = predict_image(image_bytes)
        print("\n Prediction Result:")
        print(f"   Task: {result['task_name_ar']}")
        print(f"   Confidence: {result['confidence_percent']}")
        print(f"   Verified: {'✅' if result['verified'] else '❌'}")
    else:
        print(f" Test image not found: {test_image_path}")
