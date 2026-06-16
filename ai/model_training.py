import numpy as np
import json
import os
import tensorflow as tf

from tensorflow.keras.models import Model
from tensorflow.keras.layers import (
    Input,
    LSTM,
    Bidirectional,
    Dense,
    Dropout,
    BatchNormalization
)
from tensorflow.keras.optimizers import Adam
from tensorflow.keras.regularizers import l2

from sklearn.model_selection import train_test_split

# ==========================
# 1. PATHS
# ==========================
DATA_DIR = r"C:\data\pose_dataset"
MODEL_PATH = "final_forthesis_bidirectionallstm_and_encoder_exercise_classifier_model.h5"

X_PATH = os.path.join(DATA_DIR, "X.npy")
Y_PATH = os.path.join(DATA_DIR, "y.npy")
LABELS_PATH = os.path.join(DATA_DIR, "labels.json")

# ==========================
# 2. LOAD DATA
# ==========================
X = np.load(X_PATH)
y = np.load(Y_PATH)

with open(LABELS_PATH, "r") as f:
    label_map = json.load(f)

num_classes = len(label_map)

print("✅ Loaded dataset")
print("X shape:", X.shape)   # (samples, timesteps, features)
print("y shape:", y.shape)
print("Classes:", label_map)

# ==========================
# 3. TRAIN / VALIDATION SPLIT
# ==========================
X_train, X_val, y_train, y_val = train_test_split(
    X,
    y,
    test_size=0.2,
    random_state=42,
    stratify=y
)

# ==========================
# 4. BIGGER MODEL ARCHITECTURE
# ==========================
def build_pose_lstm_big(sequence_len, features, classes):
    inp = Input(shape=(sequence_len, features))

    # -------- LSTM BLOCK 1 --------
    x = Bidirectional(
        LSTM(
            256,
            return_sequences=True,
            dropout=0.2
        )
    )(inp)
    x = BatchNormalization()(x)

    # -------- LSTM BLOCK 2 --------
    x = Bidirectional(
        LSTM(
            256,
            return_sequences=True,
            dropout=0.2
        )
    )(x)
    x = BatchNormalization()(x)

    # -------- LSTM BLOCK 3 --------
    x = Bidirectional(
        LSTM(
            128,
            return_sequences=False,
            dropout=0.2
        )
    )(x)
    x = BatchNormalization()(x)

    # -------- DENSE HEAD --------
    x = Dense(
        256,
        activation="relu",
        kernel_regularizer=l2(1e-4)
    )(x)
    x = Dropout(0.5)(x)

    x = Dense(
        128,
        activation="relu",
        kernel_regularizer=l2(1e-4)
    )(x)
    x = Dropout(0.4)(x)

    out = Dense(classes, activation="softmax")(x)

    model = Model(inp, out)
    return model


model = build_pose_lstm_big(
    sequence_len=X.shape[1],
    features=X.shape[2],
    classes=num_classes
)

model.summary()

# ==========================
# 5. COMPILE
# ==========================
model.compile(
    optimizer=Adam(learning_rate=3e-4),
    loss="sparse_categorical_crossentropy",
    metrics=["accuracy"]
)

# ==========================
# 6. TRAIN
# ==========================
history = model.fit(
    X_train,
    y_train,
    validation_data=(X_val, y_val),
    epochs=110,  # Specify the number of epochs here
    batch_size=32
)

# ==========================
# 7. SAVE FINAL MODEL
# ==========================
model.save(MODEL_PATH)
print(f"\n✅ MODEL SAVED SUCCESSFULLY: {MODEL_PATH}")
