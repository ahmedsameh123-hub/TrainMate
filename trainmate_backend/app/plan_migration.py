"""Migrate legacy single user_plans row into workout_plans list."""

from __future__ import annotations

import json

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import User, UserPlan, WorkoutPlan
from app.routers.plans import TEMPLATE_EXERCISES


def migrate_legacy_plans(db: Session) -> None:
    users = db.scalars(select(User)).all()
    for user in users:
        existing = db.scalars(
            select(WorkoutPlan).where(WorkoutPlan.user_id == user.id).limit(1)
        ).first()
        if existing is not None:
            continue

        legacy: UserPlan | None = user.plan
        if legacy is None or not legacy.category:
            continue

        cat = legacy.category.strip()
        is_template = cat in TEMPLATE_EXERCISES
        exercises = TEMPLATE_EXERCISES.get(cat, TEMPLATE_EXERCISES["Muscle Gain"])

        row = WorkoutPlan(
            user_id=user.id,
            name=cat,
            plan_kind="template" if is_template else "custom",
            template_category=cat if is_template else "Muscle Gain",
            exercises_json=json.dumps(exercises),
            duration_weeks=legacy.duration_weeks or 8,
            before_photo_base64=legacy.before_photo_base64,
            after_photo_base64=legacy.after_photo_base64,
            is_active=1,
        )
        db.add(row)
    db.commit()
