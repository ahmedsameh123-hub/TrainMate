import json
import logging
import smtplib
import ssl
import urllib.error
import urllib.request
from email.mime.text import MIMEText

from app.config import settings

logger = logging.getLogger(__name__)


def _log_code_no_delivery(kind: str, to_addr: str, code: str) -> None:
    """Loud log when neither Resend nor SMTP is configured."""
    logger.warning(
        "\n"
        + "=" * 62
        + "\n"
        + f"  TrainMate: no email delivery (inbox will NOT receive mail).\n"
        + f"  {kind} → {to_addr}\n"
        + f"  CODE: {code}\n"
        + "  Fix: set RESEND_API_KEY or SMTP_* in .env — see .env.example.\n"
        + "=" * 62
    )


def _send_via_resend(to_addr: str, subject: str, body: str) -> None:
    payload = {
        "from": (settings.resend_from or "TrainMate <onboarding@resend.dev>").strip(),
        "to": [to_addr],
        "subject": subject,
        "text": body,
    }
    data = json.dumps(payload).encode("utf-8")
    # Resend (via Cloudflare) returns 403 error 1010 if User-Agent is missing.
    req = urllib.request.Request(
        "https://api.resend.com/emails",
        data=data,
        method="POST",
        headers={
            "Authorization": f"Bearer {settings.resend_api_key.strip()}",
            "Content-Type": "application/json",
            "User-Agent": f"{settings.app_name}-Backend/1.0 (Python)",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            code = resp.getcode()
            if code not in (200, 201):
                raw = resp.read().decode("utf-8", errors="replace")
                raise RuntimeError(f"Resend HTTP {code}: {raw}")
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace") if e.fp else ""
        raise RuntimeError(f"Resend HTTP {e.code}: {err_body}") from e


def _send_via_smtp(to_addr: str, subject: str, body: str) -> None:
    msg = MIMEText(body, "plain", "utf-8")
    msg["Subject"] = subject
    msg["From"] = (settings.smtp_from or settings.smtp_user or "noreply@localhost").strip()
    msg["To"] = to_addr

    mail_from = msg["From"]

    if settings.smtp_use_ssl:
        context = ssl.create_default_context()
        with smtplib.SMTP_SSL(
            settings.smtp_host,
            settings.smtp_port,
            context=context,
            timeout=45,
        ) as server:
            if settings.smtp_user:
                server.login(settings.smtp_user, settings.smtp_password or "")
            server.sendmail(mail_from, [to_addr], msg.as_string())
        return

    with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=45) as server:
        if settings.smtp_use_tls:
            context = ssl.create_default_context()
            server.starttls(context=context)
        if settings.smtp_user:
            server.login(settings.smtp_user, settings.smtp_password or "")
        server.sendmail(mail_from, [to_addr], msg.as_string())


def _dispatch_email(to_addr: str, subject: str, body: str, log_label: str) -> None:
    """Try every configured transport; only fail if all of them fail.

    SMTP is attempted before Resend because Resend's free tier can only
    deliver to the account owner's address, while SMTP (Gmail app password)
    can reach any recipient.
    """
    errors: list[str] = []

    if settings.smtp_ready:
        try:
            _send_via_smtp(to_addr, subject, body)
            logger.info("%s sent via SMTP to %s", log_label, to_addr)
            return
        except Exception as exc:
            errors.append(f"SMTP: {exc}")
            logger.warning("SMTP delivery failed for %s: %s", to_addr, exc)

    if settings.resend_ready:
        try:
            _send_via_resend(to_addr, subject, body)
            logger.info("%s sent via Resend to %s", log_label, to_addr)
            return
        except Exception as exc:
            errors.append(f"Resend: {exc}")
            logger.warning("Resend delivery failed for %s: %s", to_addr, exc)

    if errors:
        raise RuntimeError("; ".join(errors))
    raise RuntimeError("no email transport configured")


def send_password_reset_email(to_addr: str, code: str) -> bool:
    """Returns True if the email was actually delivered, False otherwise.

    Raises only when delivery failed AND dev code exposure is disabled.
    """
    subj = f"{settings.app_name} — reset your password"
    body = (
        f"Your password reset code is: {code}\n\n"
        f"It expires in 15 minutes. If you did not request a reset, ignore this message.\n"
    )
    if not settings.email_delivery_ready:
        _log_code_no_delivery("Password reset", to_addr, code)
        if settings.expose_verification_codes:
            return False
        raise RuntimeError("no email transport configured")

    try:
        _dispatch_email(to_addr, subj, body, "Password reset email")
        return True
    except Exception:
        logger.exception("Failed to send password reset email to %s", to_addr)
        if settings.expose_verification_codes:
            _log_code_no_delivery("Password reset (send failed — use code below)", to_addr, code)
            return False
        raise


def send_verification_email(to_addr: str, code: str, *, subject: str | None = None) -> bool:
    """Returns True if the email was actually delivered, False otherwise.

    Raises only when delivery failed AND dev code exposure is disabled.
    """
    subj = subject or f"{settings.app_name} — email verification"
    body = (
        f"Your verification code is: {code}\n\n"
        f"It expires in 15 minutes. If you did not request this, ignore this message.\n"
    )
    if not settings.email_delivery_ready:
        _log_code_no_delivery("Email verification", to_addr, code)
        if settings.expose_verification_codes:
            return False
        raise RuntimeError("no email transport configured")

    try:
        _dispatch_email(to_addr, subj, body, "Verification email")
        return True
    except Exception:
        logger.exception("Failed to send verification email to %s", to_addr)
        if settings.expose_verification_codes:
            return False
        raise
