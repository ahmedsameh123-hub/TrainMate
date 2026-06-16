from typing import Literal

from pydantic import BaseModel, ConfigDict, EmailStr, Field


class UserRegister(BaseModel):
    email: EmailStr
    password: str = Field(min_length=6)
    name: str | None = None


class UserLogin(BaseModel):
    email: str = Field(min_length=3, max_length=320)
    password: str


class ForgotPasswordRequest(BaseModel):
    email: EmailStr


class ResetPasswordRequest(BaseModel):
    email: EmailStr
    code: str = Field(min_length=4, max_length=12)
    new_password: str = Field(min_length=6, max_length=128)


class VerifyEmailRequest(BaseModel):
    email: EmailStr
    code: str = Field(min_length=4, max_length=12)


class ResendVerificationRequest(BaseModel):
    email: EmailStr


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UserOut(BaseModel):
    id: int
    email: str
    name: str | None
    email_verified: bool
    phone: str | None = None
    pending_email: str | None = None

    model_config = {"from_attributes": True}


class UserRegisterOut(UserOut):
    """Signup response; optional dev code/token when EXPOSE_VERIFICATION_CODES is enabled."""

    verification_code: str | None = None
    access_token: str | None = None
    token_type: str = "bearer"


class VerifyEmailResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserOut


class AccountUpdate(BaseModel):
    name: str | None = Field(None, max_length=255)
    email: EmailStr | None = None
    phone: str | None = Field(None, max_length=32)
    current_password: str | None = None
    new_password: str | None = Field(None, min_length=6)


class ProfileUpdate(BaseModel):
    age: int | None = Field(None, ge=1, le=120)
    sex: str | None = Field(None, max_length=32)
    height_cm: float | None = Field(None, ge=50, le=250)
    weight_kg: float | None = Field(None, ge=10, le=400)
    profile_image_base64: str | None = None


class ProfileOut(BaseModel):
    age: int | None
    sex: str | None
    height_cm: float | None
    weight_kg: float | None
    profile_image_base64: str | None

    model_config = {"from_attributes": True}


class PlanUpdate(BaseModel):
    category: str | None = Field(None, min_length=2, max_length=64)
    duration_weeks: int | None = Field(None, ge=4, le=12)
    before_photo_base64: str | None = None
    after_photo_base64: str | None = None
    onboarding_completed: bool | None = None


class PlanOut(BaseModel):
    category: str | None
    duration_weeks: int | None
    before_photo_base64: str | None
    after_photo_base64: str | None
    onboarding_completed: bool

    model_config = {"from_attributes": True}


class WorkoutPlanCreate(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    name: str = Field(min_length=2, max_length=64)
    plan_kind: str = Field(default="custom", alias="planKind")
    template_category: str | None = Field(default=None, alias="templateCategory")
    exercises: list[str] = Field(default_factory=list)
    duration_weeks: int = Field(default=8, ge=4, le=12, alias="durationWeeks")
    before_photo_base64: str | None = Field(default=None, alias="beforePhotoBase64")
    after_photo_base64: str | None = Field(default=None, alias="afterPhotoBase64")
    target_sessions: int | None = Field(default=None, ge=1, le=200, alias="targetSessions")
    activate: bool | None = True
    onboarding_completed: bool | None = Field(default=None, alias="onboardingCompleted")


class WorkoutPlanUpdate(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    name: str | None = Field(default=None, min_length=2, max_length=64)
    template_category: str | None = Field(default=None, alias="templateCategory")
    exercises: list[str] | None = None
    duration_weeks: int | None = Field(default=None, ge=4, le=12, alias="durationWeeks")
    before_photo_base64: str | None = Field(default=None, alias="beforePhotoBase64")
    after_photo_base64: str | None = Field(default=None, alias="afterPhotoBase64")
    target_sessions: int | None = Field(default=None, ge=1, le=200, alias="targetSessions")
    onboarding_completed: bool | None = Field(default=None, alias="onboardingCompleted")


class WorkoutPlanOut(BaseModel):
    id: int
    name: str
    plan_kind: str
    template_category: str | None
    exercises: list[str]
    duration_weeks: int
    before_photo_base64: str | None
    after_photo_base64: str | None
    is_active: bool
    target_sessions: int | None = None
    sessions_completed: int = 0
    is_completed: bool = False
    completed_at: str | None = None
    completion_percent: float | None = None
    ai_overall_score: float | None = None
    ai_alignment_percent: float | None = None
    created_at: str | None


class PlanCompleteRequest(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    after_photo_base64: str = Field(alias="afterPhotoBase64")
    language_code: str = Field(default="en", alias="languageCode")


class PlanExerciseStatOut(BaseModel):
    exercise: str
    sessions: int
    total_reps: int
    total_kcal: float | None = None


class PlanCompletionStatsOut(BaseModel):
    total_sessions: int
    total_reps: int
    total_kcal: float | None = None
    total_duration_sec: int | None = None
    by_exercise: list[PlanExerciseStatOut] = Field(default_factory=list)


class PlanCompletionOut(BaseModel):
    plan: WorkoutPlanOut
    stats: PlanCompletionStatsOut
    analysis: dict | None = None


class MeOut(BaseModel):
    user: UserOut
    profile: ProfileOut | None
    plan: PlanOut | None
    workout_plans: list[WorkoutPlanOut] = Field(default_factory=list)
    active_plan: WorkoutPlanOut | None = None


class ChatMessage(BaseModel):
    role: Literal["user", "assistant"]
    content: str


class ChatRequest(BaseModel):
    model_config = ConfigDict(extra="ignore", populate_by_name=True)

    messages: list[ChatMessage] = Field(default_factory=list)
    message: str | None = None
    image_base64: str | None = Field(default=None, alias="imageBase64")
    assistant_tone: str | None = None
    prefer_short_reply: bool | None = None
    cross_chat_summary: str | None = Field(default=None, alias="crossChatSummary")


class ChatResponse(BaseModel):
    reply: str


class WorkoutCreate(BaseModel):
    exercise_label: str = Field(min_length=1, max_length=128)
    reps: int = Field(ge=0)
    duration_sec: int | None = Field(None, ge=0)
    source: Literal["auto_classify", "manual_exercise"]
    weight_kg: float | None = Field(None, ge=0, le=600)
    equipment: Literal["bar", "dumbbell", "bodyweight", "other"] | None = None
    sets: int | None = Field(None, ge=1, le=50)
    estimated_kcal: float | None = Field(None, ge=0)
    generate_ai_report: bool = False
    language_code: str = Field(default="en", alias="languageCode")


class WorkoutOut(BaseModel):
    id: int
    exercise_label: str
    reps: int
    duration_sec: int | None
    source: str
    created_at: str
    weight_kg: float | None = None
    equipment: str | None = None
    sets: int | None = None
    estimated_kcal: float | None = None
    session_report: str | None = None

    model_config = {"from_attributes": True}
