Datasets link "https://www.kaggle.com/datasets/hasyimabdillah/workoutfitness-video"
              "https://www.kaggle.com/datasets/philosopher0808/gym-workoutexercises-video"

---

🏋️ Smart Gym Assistant – Train Mate

A Streamlit-based AI fitness application that supports:

Exercise repetition counting (video & webcam)

Automatic exercise classification

AI fitness chatbot

User authentication (register / login / logout)

User profile data collection (age, sex, height, weight)

1️⃣ System Requirements

Before starting, ensure the following are installed:

Python 3.9 – 3.11

Visual Studio Code

Webcam (for Webcam & Auto Classify modes)

Internet connection (for chatbot API)

2️⃣ Project Setup (ZIP Option)

Download the project as a ZIP file

Extract it to any folder on your machine

Open Visual Studio Code

Click File → Open Folder

Select the extracted project folder

You should see a structure similar to:

auth/
ExerciseAiTrainer.py
chatbot.py
main.py
requirements.txt
users.db
...

3️⃣ Create Virtual Environment (Recommended)

Open VS Code Terminal and run:

Windows
python -m venv fitness-ai
fitness-ai\Scripts\activate

macOS / Linux
python3 -m venv fitness-ai
source fitness-ai/bin/activate

4️⃣ Install Dependencies

Install all required packages:

pip install -r requirements.txt

Notes

If any package fails, rerun:

pip install streamlit opencv-python mediapipe tensorflow langchain groq python-dotenv


No extra packages are required beyond this.

5️⃣ API Key Configuration (Chatbot)

The chatbot uses a free LLM API (Groq).

Steps:

Create a .env file in the project root

Add your API key:

GROQ_API_KEY=your_api_key_here


⚠️ Do NOT hard-code the key inside Python files.

6️⃣ Run the Application

From the project root:

python -m streamlit run main.py


Streamlit will display:

Local URL: http://localhost:8501


Open it in your browser.

7️⃣ Application Flow
🔐 Authentication

Register a new user

Login with credentials

Logout available in the sidebar

👤 User Profile

After first login, the user is prompted to enter:

Age

Sex

Height

Weight

This data is stored locally and used for personalization.

8️⃣ Features Overview
📹 Video Mode

Upload exercise video

Select exercise type

AI counts repetitions

📷 Webcam Mode

Live webcam tracking

Real-time repetition counting

🤖 Auto Classify

Automatically detects exercise type

Counts repetitions without manual selection

💬 AI Chatbot

Fitness-focused chatbot

Answers training, posture, and workout questions

9️⃣ Data & Storage

users.db
Stores authentication and user profile data (SQLite)

.pkl files
Pretrained ML model and scaler (do not modify)

🔁 Restart / Logout Behavior

Logout resets authentication session

Page reload handled using st.rerun()

Session state ensures secure navigation

⚠️ Common Issues & Fixes
Webcam not opening

Close other apps using the camera

Restart Streamlit

Model warnings

TensorFlow warnings are normal

Do not affect functionality

Chatbot error

Verify API key

Ensure correct model name

Restart the app

✅ Project Status

✔ Fully functional
✔ Authentication enabled
✔ AI features integrated
✔ Ready for demo or submission