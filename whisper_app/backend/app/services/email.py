import smtplib
import logging
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from app.core.config import settings

logger = logging.getLogger(__name__)

def send_verification_email_sync(to_email: str, code: str) -> bool:
    """
    Simple and reliable email sending function
    """
    try:
        print(f"📧 Starting email send to: {to_email}")
        
        # Create message
        msg = MIMEMultipart('alternative')
        msg['Subject'] = 'Verify Your Whisper Space Account'
        msg['From'] = settings.SMTP_FROM
        msg['To'] = to_email
        
        # Text version
        text = f"""Whisper Space Verification

Your verification code is: {code}

Enter this code in the app to verify your email.

This code will expire in 10 minutes.

If you didn't request this, please ignore this email.
"""
        
        # HTML version
        html = f"""<!DOCTYPE html>
<html>
<body style="font-family: Arial, sans-serif; padding: 20px;">
    <div style="max-width: 600px; margin: 0 auto; padding: 30px; background: #f8f9fa; border-radius: 10px;">
        <h2 style="color: #333;">Whisper Space</h2>
        <h3 style="color: #555;">Email Verification Required</h3>
        
        <p>Hello,</p>
        
        <p>Please use the following code to verify your email address:</p>
        
        <div style="text-align: center; margin: 30px 0;">
            <div style="
                display: inline-block;
                font-size: 32px;
                font-weight: bold;
                color: white;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                padding: 20px 40px;
                border-radius: 8px;
                letter-spacing: 5px;
            ">
                {code}
            </div>
        </div>
        
        <p style="color: #666; font-size: 14px;">
            <strong>Note:</strong> This code expires in 10 minutes.
        </p>
        
        <div style="margin-top: 40px; padding-top: 20px; border-top: 1px solid #ddd; color: #888; font-size: 12px;">
            <p>If you didn't create an account with Whisper Space, please ignore this email.</p>
            <p>© 2024 Whisper Space</p>
        </div>
    </div>
</body>
</html>"""
        
        # Attach parts
        msg.attach(MIMEText(text, 'plain'))
        msg.attach(MIMEText(html, 'html'))
        
        # Send email
        if settings.SMTP_PORT == 465:
            # SSL
            with smtplib.SMTP_SSL(settings.SMTP_HOST, settings.SMTP_PORT, timeout=30) as server:
                server.login(settings.SMTP_USER, settings.SMTP_PASS)
                server.send_message(msg)
                print(f"✅ Email sent via SSL to {to_email}")
        else:
            # TLS (587 or 2525)
            with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT, timeout=30) as server:
                server.starttls()
                server.login(settings.SMTP_USER, settings.SMTP_PASS)
                server.send_message(msg)
                print(f"✅ Email sent via TLS to {to_email}")
        
        return True
        
    except smtplib.SMTPAuthenticationError:
        print(f"❌ SMTP Authentication failed for {settings.SMTP_USER}")
        print("Please check your email password/API key")
        return False
    except Exception as e:
        print(f"❌ Failed to send email: {e}")
        return False


async def send_verification_email(to_email: str, code: str) -> bool:
    """
    Async wrapper
    """
    import asyncio
    return await asyncio.to_thread(send_verification_email_sync, to_email, code)

def send_password_reset_email_sync(to_email: str, code: str) -> bool:
    try:
        msg = MIMEMultipart('alternative')
        msg['Subject'] = 'Whisper Space - Reset Your Password'
        msg['From'] = settings.SMTP_FROM
        msg['To'] = to_email

        text = f"""Password Reset Request

Your password reset code is: {code}

Enter this code in the app to set a new password.
This code expires in 15 minutes.

If you didn't request this, ignore this email.
"""

        html = f"""<!DOCTYPE html>
<html>
<body style="font-family: Arial, sans-serif; padding: 20px;">
    <div style="max-width: 600px; margin: 0 auto; padding: 30px; background: #f8f9fa; border-radius: 10px;">
        <h2 style="color: #333;">Whisper Space</h2>
        <h3>Password Reset Request</h3>
        <p>Hello,</p>
        <p>You requested to reset your password. Use the code below:</p>
        
        <div style="text-align: center; margin: 30px 0;">
            <div style="display: inline-block; font-size: 32px; font-weight: bold; color: white;
                        background: linear-gradient(135deg, #ff6b6b, #ee5a52); padding: 20px 40px;
                        border-radius: 8px; letter-spacing: 5px;">
                {code}
            </div>
        </div>
        
        <p style="color: #666;"><strong>Expires in 15 minutes.</strong></p>
        <p>If you didn't request this, you can safely ignore this email.</p>
    </div>
</body>
</html>"""

        msg.attach(MIMEText(text, 'plain'))
        msg.attach(MIMEText(html, 'html'))

        # Same SMTP logic as before
        if settings.SMTP_PORT == 465:
            with smtplib.SMTP_SSL(settings.SMTP_HOST, settings.SMTP_PORT, timeout=30) as server:
                server.login(settings.SMTP_USER, settings.SMTP_PASS)
                server.send_message(msg)
        else:
            with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT, timeout=30) as server:
                server.starttls()
                server.login(settings.SMTP_USER, settings.SMTP_PASS)
                server.send_message(msg)
        
        print(f"✅ Password reset email sent to {to_email}")
        return True
    except Exception as e:
        print(f"❌ Failed to send password reset email: {e}")
        return False

async def send_password_reset_email(to_email: str, code: str) -> bool:
    import asyncio
    return await asyncio.to_thread(send_password_reset_email_sync, to_email, code)