# توثيق باك إند TrainMate (FastAPI)

هذا الملف يشرح **باك إند تطبيق TrainMate**: ماذا يفعل، كيف يعمل، المكونات، إدارة البيانات، ونقاط الـ API الرئيسية — مع مخططات **Use Case** و**Class** و**Sequence** (بما فيها المصادقة والتهيئة، وإنهاء التمرين مع الشات بوت).

---

## 1. نظرة عامة

- **الإطار**: [FastAPI](https://fastapi.tiangolo.com/) على Python، يعمل عبر **Uvicorn**.
- **الواجهة**: REST تحت البادئة **`/api`** مع **JWT (Bearer)** للمسارات المحمية.
- **قاعدة البيانات**: **SQLAlchemy 2** مع SQLite افتراضيًا (`sqlite:///./trainmate.db`) — يمكن تغيير `DATABASE_URL` لقاعدة أخرى مدعومة.
- **الذكاء الاصطناعي**:
  - **Groq** (`groq`) لتوليد تقارير الجلسات ولـ chat المساعد.
  - **OpenRouter** (عبر عميل `openai`) كبديل اختياري حسب الإعدادات.
- **البريد**: إرسال أكواد التحقق وإعادة تعيين كلمة المرور عبر **SMTP** أو **Resend** (`app/email_delivery.py`).
- **تعلم الآلة على السيرفر** (اختياري): تصنيف تمارين من نافذة Pose عبر **TensorFlow/Keras** إذا وُجدت الأوزان تحت `ai/models/` أو `ML_MODELS_DIR`.

**تشغيل محلي (من مجلد `trainmate_backend`):**

```bash
.venv\Scripts\activate
pip install -r requirements.txt
copy .env.example .env   # ثم ضبط JWT_SECRET_KEY و GROQ_API_KEY وغيرها
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

**فحص الصحة:** `GET http://127.0.0.1:8000/api/health`

---

## 2. مخطط حالات الاستخدام (Use Case Diagram)

يعرض الأدوار الرئيسية والتفاعلات مع النظام (المستخدم عبر تطبيق Flutter/الويب، والخدمات الخارجية).

```mermaid
flowchart LR
  subgraph actors["الممثلون"]
    U["المستخدم (عميل التطبيق)"]
    EM["مزود البريد (SMTP / Resend)"]
    LLM["Groq / OpenRouter"]
  end

  subgraph system["باك إند TrainMate"]
    UC1["التسجيل والتحقق من البريد"]
    UC2["تسجيل الدخول (JWT)"]
    UC3["استعادة كلمة المرور"]
    UC4["الملف والخطة (profile / plan)"]
    UC5["تسجيل جلسات التمرين"]
    UC6["تقرير جلسة بالذكاء الاصطناعي"]
    UC7["محادثة المساعد الذكي"]
    UC8["ملاحظات التقدم"]
    UC9["تصنيف ML للحركة (اختياري)"]
    UC10["Health check"]
  end

  U --> UC1
  U --> UC2
  U --> UC3
  U --> UC4
  U --> UC5
  U --> UC6
  U --> UC7
  U --> UC8
  U --> UC9
  UC1 --> EM
  UC3 --> EM
  UC6 --> LLM
  UC7 --> LLM
  UC8 --> LLM
```

---

## 3. مخطط الصفوف (Class Diagram)

يعكس **طبقة النموذج (ORM)** والعلاقات، مع أهم الطبقات المجاورة في التطبيق.

```mermaid
classDiagram
  direction TB

  class User {
    +int id
    +string email
    +string hashed_password
    +string name
    +string phone
    +bool email_verified
    +string pending_email
    +datetime verification_expires_at
    +relationship profile
    +relationship plan
    +relationship workouts
  }

  class UserProfile {
    +int id
    +int user_id FK
    +int age
    +string sex
    +float height_cm
    +float weight_kg
    +text notes
    +text profile_image_base64
  }

  class UserPlan {
    +int id
    +int user_id FK
    +string category
    +int duration_weeks
    +text before_photo_base64
    +text after_photo_base64
    +int onboarding_completed
  }

  class WorkoutSession {
    +int id
    +int user_id FK
    +string exercise_label
    +int reps
    +int duration_sec
    +string source
    +float weight_kg
    +string equipment
    +int sets
    +float estimated_kcal
    +text session_report
    +datetime created_at
  }

  User "1" --> "0..1" UserProfile : profile
  User "1" --> "0..1" UserPlan : plan
  User "1" --> "*" WorkoutSession : workouts

  note for User "JWT يحمل uid للربط مع السجل"
```

**طبقات إضافية (ليست كلها صفوف ORM):**

| طبقة | الملفات / الدور |
|------|------------------|
| Routers | `app/routers/auth.py`, `users.py`, `workouts.py`, `chat.py`, `ml.py` — تعريف المسارات |
| Schemas | `app/schemas.py` — Pydantic للطلبات والاستجابات |
| Security | `app/security.py` — bcrypt، JWT، HMAC لأكواد البريد |
| Dependencies | `app/deps.py` — استخراج المستخدم الحالي من Bearer |
| Config | `app/config.py` — إعدادات البيئة (`.env`) |
| Email | `app/email_delivery.py` — إرسال الرسائل |
| Verification | `app/verification.py` — توليد/حدود إعادة الإرسال للأكواد |

---

## 4. مخطط تسلسل عام (طلب محمي نموذجي)

من لحظة إرسال الطلب حتى الاستجابة من قاعدة البيانات و/أو الـ LLM.

```mermaid
sequenceDiagram
  participant C as العميل (Flutter)
  participant API as FastAPI
  participant Dep as get_current_user
  participant DB as SQLAlchemy Session
  participant Svc as خدمة (أمان / LLM / ML)

  C->>API: HTTP + Authorization Bearer
  API->>Dep: decode JWT + load User
  Dep->>DB: SELECT User by id
  DB-->>Dep: User
  Dep-->>API: User (أو 401/403)
  API->>Svc: منطق المسار (مثلاً حفظ تمرين أو chat)
  Svc->>DB: INSERT/SELECT حسب الحاجة
  DB-->>Svc: نتيجة
  opt إن وُجد LLM
    Svc->>Svc: Groq / OpenRouter
  end
  API-->>C: JSON response
```

---

## 5. مخطط تسلسل: المصادقة والتهيئة (Authentication & Initialization)

يتضمن: تسجيلًا جديدًا مع التحقق بالبريد، أو تسجيل دخول بعد التحقق، ثم استخدام الـ token للوصول إلى `/users/me`.

```mermaid
sequenceDiagram
  participant App as التطبيق
  participant Auth as /api/auth/*
  participant DB as قاعدة البيانات
  participant Mail as SMTP / Resend

  alt تسجيل حساب جديد
    App->>Auth: POST /api/auth/register
    Auth->>DB: إنشاء User + UserProfile، حفظ hash كلمة المرور
    Auth->>Auth: توليد كود تحقق (مخزّن كـ HMAC)
    Auth->>Mail: إرسال بريد التحقق
    Mail-->>Auth: (نجاح/فشل)
    Auth-->>App: 201 + بيانات المستخدم (+ كود في JSON إذا EXPOSE_VERIFICATION_CODES)
  end

  alt تأكيد البريد
    App->>Auth: POST /api/auth/verify-email
    Auth->>DB: التحقق من الكود والصلاحية
    Auth->>Auth: create_access_token(uid)
    Auth-->>App: JWT + بيانات المستخدم
  end

  alt تسجيل الدخول
    App->>Auth: POST /api/auth/login
    Auth->>DB: التحقق من البريد وكلمة المرور
    Note over Auth: 403 إن EMAIL_NOT_VERIFIED
    Auth->>Auth: create_access_token
    Auth-->>App: access_token (JWT)
  end

  App->>Auth: GET /api/users/me + Bearer
  Auth->>DB: تحميل profile و plan
  Auth-->>App: MeOut (user + profile + plan)
```

**ملاحظات تنفيذية:**

- **`get_current_user`** في `app/deps.py` يرفض الطلب إن لم يكن هناك Bearer صالح، أو إن **`email_verified`** ليس `true`.
- تغيير البريد من **`PATCH /api/users/me/account`** قد يضع **`pending_email`** ويرسل كود تحقق للبريد الجديد (مشابه لتدفق التسجيل).

---

## 6. مخطط تسلسل: إنهاء التمرين وتفاعل الشات بوت

يجمع بين حفظ الجلسة (`POST /api/workouts`) وتوليد تقرير اختياري بالـ AI، ثم محادثة المساعد (`POST /api/chat`) التي تُحقن بسياق المستخدم من قاعدة البيانات.

```mermaid
sequenceDiagram
  participant App as التطبيق
  participant WO as /api/workouts
  participant Chat as /api/chat
  participant DB as قاعدة البيانات
  participant G as Groq / OpenRouter

  App->>WO: POST /api/workouts + JWT + WorkoutCreate
  WO->>DB: جلب User (مع profile/plan للـ kcal والتقرير)
  WO->>WO: حساب estimated_kcal (MET تقريبي أو من الطلب)
  WO->>DB: INSERT WorkoutSession

  alt generate_ai_report = true
    WO->>G: طلب نص تقرير الجلسة (لغة من language_code)
    G-->>WO: نص التقرير
    WO->>DB: UPDATE session_report
  else بدون مفتاح Groq أو فشل الطلب
    WO->>WO: تقرير بديل نصي (عربي/إنجليزي) محليًا
  end
  WO-->>App: WorkoutOut (يشمل session_report إن وُجد)

  App->>Chat: POST /api/chat + JWT + رسالة / سجل محادثة
  Chat->>DB: بناء سياق: إحصاءات، ملخص تمارين، آخر تقرير جلسة، الخطة، الملف
  Chat->>G: رسائل النظام + سياق المستخدم + محادثة المستخدم
  G-->>Chat: رد المساعد
  alt لا يوجد مفتاح LLM أو خطأ
    Chat-->>App: رد fallback (بدون رفع 5xx للمحادثة)
  else نجاح
    Chat-->>App: ChatResponse
  end
```

**نقطة إضافية:** يوجد **`GET /api/chat/progress-feedback?lang=`** يولّد ملخص تقدم قصير من بيانات التمارين والملف (مع نفس منطق الـ provider والـ fallback).

---

## 7. الوحدات الأساسية والتقنيات (Core Backend Modules & Technologies)

| المكون | التقنية | الوظيفة |
|--------|---------|---------|
| إطار الويب | FastAPI | مسارات REST، تحقق Pydantic، OpenAPI تلقائي |
| الخادم | Uvicorn | تشغيل ASGI |
| ORM | SQLAlchemy 2 | نماذج `User`, `UserProfile`, `UserPlan`, `WorkoutSession` |
| المصادقة | python-jose + bcrypt | JWT HS256، تشفير كلمات المرور |
| إعدادات | pydantic-settings | قراءة `.env` |
| ذكاء اصطناعي | groq، openai (OpenRouter) | تقارير الجلسات، الشات، ملاحظات التقدم |
| CORS | CORSMiddleware | السماح للعميل (الويب/المحمول) بالاتصال |
| بريد | SMTP أو Resend API | تحقق البريد، إعادة التعيين |
| ML اختياري | tensorflow-cpu، joblib، numpy | `/api/ml/classify` عند توفر النماذج |

**مسارات الراوتر المجمّعة في `app/main.py`:**

- `/api/auth/*`
- `/api/users/*`
- `/api/workouts/*`
- `/api/chat/*`
- `/api/ml/*`
- `/api/health`

---

## 8. إدارة البيانات في الباك إند (Backend Data Management)

### 8.1 تهيئة الجداول والترحيل الخفيف لـ SQLite

- عند الإقلاع: `Base.metadata.create_all(bind=engine)` ينشئ الجداول إن لم تكن موجودة.
- دالة **`_ensure_sqlite_columns()`** تضيف أعمدة جديدة للجداول القديمة في SQLite (ترقية بدون Alembic — مناسب للتطوير السريع).

### 8.2 الجداول والعلاقات

- **`users`**: الهوية، كلمة المرور، حالة التحقق، أكواد التحقق/إعادة التعيين (مخزنة كـ hash).
- **`user_profiles`**: بيانات جسدية وملاحظات وصورة profile بصيغة base64.
- **`user_plans`**: فئة الخطة، المدة بالأسابيع، صور قبل/بعد، اكتمال الـ onboarding.
- **`workout_sessions`**: كل سجل تمرين مع حقول إضافية (وزن، معدات، مجموعات، سعرات، تقرير نصي).

### 8.3 الجلسات (Sessions)

- `get_db()` يفتح جلسة SQLAlchemy لكل طلب ويغلقها بعد الانتهاء — نمط شائع مع FastAPI.

### 8.4 الأسرار والبيئة

أهم المتغيرات (انظر `app/config.py` و `.env.example`):

- `JWT_SECRET_KEY`, `JWT_ALGORITHM`, `ACCESS_TOKEN_EXPIRE_MINUTES`
- `DATABASE_URL`
- `GROQ_API_KEY`, `GROQ_MODEL`, `LLM_PROVIDER`, `OPENROUTER_*`
- `SMTP_*` أو `RESEND_API_KEY`
- `EXPOSE_VERIFICATION_CODES` (للتطوير: إرجاع كود التحقق في JSON)
- `ML_MODELS_DIR` (مسار اختياري لأوزان Keras)

---

## 9. جدول مختصر لأهم نقاط API

| الطريقة | المسار | الحماية | الغرض |
|---------|--------|---------|--------|
| GET | `/api/health` | لا | حالة الخدمة وإعداد البريد/الـ LLM |
| POST | `/api/auth/register` | لا | تسجيل + إرسال تحقق |
| POST | `/api/auth/login` | لا | JWT بعد التحقق |
| POST | `/api/auth/verify-email` | لا | إتمام التحقق + JWT |
| POST | `/api/auth/resend-verification` | لا | إعادة إرسال الكود |
| POST | `/api/auth/forgot-password` | لا | طلب كود إعادة تعيين |
| POST | `/api/auth/reset-password` | لا | تعيين كلمة مرور جديدة |
| GET | `/api/users/me` | Bearer | المستخدم + الملف + الخطة |
| PATCH | `/api/users/me/profile` | Bearer | تحديث الملف |
| PATCH | `/api/users/me/account` | Bearer | الاسم/الهاتف/البريد/كلمة المرور |
| PATCH | `/api/users/me/plan` | Bearer | الخطة والصور و onboarding |
| POST | `/api/workouts` | Bearer | إنشاء جلسة + تقرير AI اختياري |
| GET | `/api/workouts` | Bearer | قائمة آخر التمارين |
| POST | `/api/chat` | Bearer | محادثة مع سياق المستخدم |
| POST | `/api/chat/progress-feedback` | Bearer | ملاحظات تقدم مختصرة |
| GET | `/api/ml/status` | لا (أو حسب النشر) | هل الملفات موجودة |
| POST | `/api/ml/classify` | Bearer | تصنيف نافذة pose |

---

## 10. إضافات مفيدة

- **الأمان**: كلمات المرور بـ bcrypt؛ أكواد البريد عبر HMAC؛ لا يُعاد كود إعادة التعيين في JSON (عكس التحقق عند التطوير).
- **مرونة الـ LLM**: `LLM_PROVIDER=auto` يختار OpenRouter إن وُجد مفتاح، وإلا Groq.
- **الشات**: يبني سياقًا غنيًا من آخر التمارين والإحصاءات لتقليل “الاختلاق” — مع قواعد في الـ system prompts.
- **التمرين**: تقدير السعرات يعتمد MET تقريبي حسب اسم التمرين ووزن الجسم إن وُجد.

---

*آخر تحديث يعتمد على الكود في المستودع (`trainmate_backend/app`). إذا غيّرت المسارات أو النماذج، حدّث هذا الملف بنفس الوقت.*
