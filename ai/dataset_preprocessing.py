import os
import cv2
import mediapipe as mp
import numpy as np
import json
from collections import deque

# ==========================
# CONFIG
# ==========================
DATASET_DIR = r"C:\project"        # root folder: one folder per exercise
OUTPUT_DIR = r"C:\data\pose_dataset"
SEQUENCE_LENGTH = 20

os.makedirs(OUTPUT_DIR, exist_ok=True)

# ==========================
# MediaPipe Pose
# ==========================
mp_pose = mp.solutions.pose
pose = mp_pose.Pose(
    min_detection_confidence=0.5,
    min_tracking_confidence=0.5
)

# ==========================
# Helpers
# ==========================
def extract_pose(landmarks):
    """Convert 33 landmarks to a flat vector (99 values)"""
    data = []
    for lm in landmarks:
        data.extend([lm.x, lm.y, lm.z])
    return np.array(data, dtype=np.float32)

# ==========================
# Build Dataset
# ==========================
X = []
y = []
label_map = {}
label_id = 0

for exercise in sorted(os.listdir(DATASET_DIR)):
    exercise_path = os.path.join(DATASET_DIR, exercise)
    if not os.path.isdir(exercise_path):
        continue

    label_map[exercise] = label_id
    print(f"📌 Processing: {exercise} → label {label_id}")

    for video in os.listdir(exercise_path):
        if not video.lower().endswith(".mp4"):
            continue

        cap = cv2.VideoCapture(os.path.join(exercise_path, video))
        buffer = deque(maxlen=SEQUENCE_LENGTH)

        while cap.isOpened():
            ret, frame = cap.read()
            if not ret:
                break

            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            results = pose.process(rgb)

            if results.pose_landmarks:
                pose_vec = extract_pose(results.pose_landmarks.landmark)
                buffer.append(pose_vec)

                if len(buffer) == SEQUENCE_LENGTH:
                    X.append(np.array(buffer))
                    y.append(label_id)

        cap.release()

    label_id += 1

# ==========================
# Save Dataset
# ==========================
X = np.array(X, dtype=np.float32)   # (samples, 20, 99)
y = np.array(y, dtype=np.int32)

np.save(os.path.join(OUTPUT_DIR, "X.npy"), X)
np.save(os.path.join(OUTPUT_DIR, "y.npy"), y)

with open(os.path.join(OUTPUT_DIR, "labels.json"), "w") as f:
    json.dump(label_map, f, indent=4)

print("\n✅ DATASET CREATED SUCCESSFULLY")
print("X shape:", X.shape)
print("y shape:", y.shape)
print("Labels:", label_map)
