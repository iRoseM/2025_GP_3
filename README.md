# 🌱 Nameer: A Sustainability Mobile App  
*2025_GP_3*

![Logo](docs/img/Logo.png)


---

## 📖 Introduction
**Nameer** (نمير) is inspired by the Arabic word for *pure water*, symbolizing life and sustainability.  
This mobile application motivates individuals to adopt **eco-friendly habits** such as:
- ♻️ Recycling  
- 🚶 Using public transport  

Our goal is to align with **Saudi Vision 2030** and the **Saudi Green Initiative (SGI)**, turning sustainability into a fun, engaging lifestyle.  

---

## 🚀 Features
✨ Gamified tasks with rewards  
✨ Eco-impact tracking dashboard  
✨ Recycling bin locator (Riyadh)  
✨ AI-powered validation (image recognition & quiz generation)  

---

## 🛠️ Technology Stack
- **Frontend**: Flutter (Dart)  
- **Backend / Database**:  NoSQL database 
- **Machine Learning**: Python 
- **Tools**: GitHub , VSC ,  Android studio

---

## ⚡ Launching Instructions
1. Clone the repository:
   ```bash
   git clone https://github.com/iRoseM/Nameer-Sustainability_Mobile_App.git

2. Navigate to the project folder:
   ```bash
    cd Nameer-Sustainability_Mobile_App

3. Install dependencies:
   ```bash
   flutter pub get
4. Run
   ```bash
   flutter run



## 📊 Dataset

The `Dataset` folder contains all research and machine-learning materials collected and used throughout the project:

- **Requirements Elicitation** — Interview settings, observation notes, and transcriptions collected during the requirements-gathering phase.
- **Tasks Dataset** — Image data used to train and evaluate the image-classification model, organized by task category (Scooter, RVM, Plastic, Paper, Metro, Food, Cloth, Bus, Bicycle):
  - `Raw/` — Original, unmodified images per category.
  - `Augmented/` — Augmented versions of the same images (flipping, rotation, color jitter) used for training.
- **Testing** — Usability and evaluation data, including SUS survey responses and UAT (User Acceptance Testing) results for both regular users and administrators.

---

## 📂 Project Structure

```
2025_GP_3/
│
├── Dataset/                     # Research data, ML training data, and evaluation results
│   ├── Requirements Elicitation/
│   ├── Tasks Dataset/
│   │   ├── Raw/
│   │   │   ├── Scooter/
│   │   │   ├── RVM/
│   │   │   ├── Plastic/
│   │   │   ├── Paper/
│   │   │   ├── Metro/
│   │   │   ├── Food/
│   │   │   ├── Cloth/
│   │   │   ├── Bus/
│   │   │   └── Bicycle/
│   │   └── Augmented/
│   │       ├── Scooter/
│   │       ├── RVM/
│   │       ├── Plastic/
│   │       ├── Paper/
│   │       ├── Metro/
│   │       ├── Food/
│   │       ├── Cloth/
│   │       ├── Bus/
│   │       └── Bicycle/
│   └── Testing/
│
├── lib/                # Main Flutter source code 
├── assets/             # Images, icons, and other static media  
├── docs/               # Documentation, diagrams, and reports  
│
├── android/            # Native Android project files  
├── ios/                # Native iOS project files  
│
├── .gitignore          # Git ignore rules  
├── AUTHORS.md          # List of contributors and their roles  
├── README.md           # Project overview
├── analysis_options.yaml # Dart/Flutter static analysis rules  
├── pubspec.yaml        # Flutter dependencies and configuration  
└── pubspec.lock        # Locked dependency versions
```
