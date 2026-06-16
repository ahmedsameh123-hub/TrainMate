from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import get_db
from app.deps import get_current_user
from app.email_delivery import send_verification_email
from app.models import User, UserPlan, UserProfile, WorkoutPlan
from app.routers.plans import _plan_out
from app.schemas import (
    AccountUpdate,
    MeOut,
    PlanOut,
    PlanUpdate,
    ProfileOut,
    ProfileUpdate,
    UserOut,
)
from app.security import hash_password, verify_password
from app.verification import enforce_resend_cooldown, issue_verification_code

router = APIRouter(prefix="/users", tags=["users"])


@router.get("/me", response_model=MeOut)
def me(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    db.refresh(user)
    prof = user.profile
    profile_out = None
    if prof:
        profile_out = ProfileOut(
            age=prof.age,
            sex=prof.sex,
            height_cm=prof.height_cm,
            weight_kg=prof.weight_kg,
            profile_image_base64=prof.profile_image_base64,
        )
    plan = user.plan
    plan_out = None
    if plan:
        plan_out = PlanOut(
            category=plan.category,
            duration_weeks=plan.duration_weeks,
            before_photo_base64=plan.before_photo_base64,
            after_photo_base64=plan.after_photo_base64,
            onboarding_completed=bool(plan.onboarding_completed),
        )

    wp_rows = db.scalars(
        select(WorkoutPlan)
        .where(
            WorkoutPlan.user_id == user.id,
            WorkoutPlan.completed_at.is_(None),
        )
        .order_by(WorkoutPlan.is_active.desc(), WorkoutPlan.created_at.desc())
    ).all()
    workout_plans_out = [_plan_out(r, db) for r in wp_rows]
    active = next((p for p in workout_plans_out if p.is_active and not p.is_completed), None)

    return MeOut(
        user=UserOut.model_validate(user),
        profile=profile_out,
        plan=plan_out,
        workout_plans=workout_plans_out,
        active_plan=active,
    )


@router.patch("/me/profile", response_model=ProfileOut)
def update_profile(
    body: ProfileUpdate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    prof = user.profile
    if prof is None:
        prof = UserProfile(user_id=user.id)
        db.add(prof)
        db.flush()

    data = body.model_dump(exclude_unset=True)
    for key, val in data.items():
        setattr(prof, key, val)

    db.commit()
    db.refresh(prof)
    return ProfileOut(
        age=prof.age,
        sex=prof.sex,
        height_cm=prof.height_cm,
        weight_kg=prof.weight_kg,
        profile_image_base64=prof.profile_image_base64,
    )


@router.patch("/me/account", response_model=UserOut)
def update_account(
    body: AccountUpdate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    data = body.model_dump(exclude_unset=True)

    if "phone" in data:
        raw = data["phone"]
        user.phone = raw.strip() if raw and str(raw).strip() else None

    if "name" in data:
        user.name = data["name"].strip() if data["name"] else None

    if data.get("new_password") is not None:
        curr = data.get("current_password") or ""
        if not curr or not verify_password(curr, user.hashed_password):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Current password is incorrect",
            )
        user.hashed_password = hash_password(data["new_password"])

    send_to: str | None = None
    code_plain: str | None = None
    if "email" in data and data["email"] is not None:
        new_email = data["email"].lower().strip()
        if new_email != user.email:
            taken_primary = db.scalar(select(User).where(User.email == new_email, User.id != user.id))
            taken_pending = db.scalar(
                select(User).where(User.pending_email == new_email, User.id != user.id),
            )
            if taken_primary or taken_pending:
                raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Email already registered")
            user.pending_email = new_email
            enforce_resend_cooldown(user)
            code_plain = issue_verification_code(user, db)
            send_to = new_email

    db.commit()
    db.refresh(user)

    if send_to and code_plain:
        try:
            send_verification_email(send_to, code_plain)
        except Exception:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Could not send verification email. Try again later.",
            )

    return UserOut.model_validate(user)


@router.patch("/me/plan", response_model=PlanOut)
def update_plan(
    body: PlanUpdate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    plan = user.plan
    if plan is None:
        plan = UserPlan(user_id=user.id)
        db.add(plan)
        db.flush()

    data = body.model_dump(exclude_unset=True)
    for key, val in data.items():
        if key == "onboarding_completed" and val is not None:
            setattr(plan, key, 1 if val else 0)
            continue
        setattr(plan, key, val)

    db.commit()
    db.refresh(plan)
    return PlanOut(
        category=plan.category,
        duration_weeks=plan.duration_weeks,
        before_photo_base64=plan.before_photo_base64,
        after_photo_base64=plan.after_photo_base64,
        onboarding_completed=bool(plan.onboarding_completed),
    )
