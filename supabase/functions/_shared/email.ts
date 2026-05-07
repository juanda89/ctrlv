// Resend email sender for Stripe lifecycle events.

const RESEND_API = "https://api.resend.com/emails";

type SendEmailOptions = {
  to: string;
  subject: string;
  html: string;
};

export async function sendEmail(options: SendEmailOptions): Promise<boolean> {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  const fromEmail = Deno.env.get("RESEND_FROM_EMAIL");
  if (!apiKey || !fromEmail) {
    return false;
  }

  try {
    const response = await fetch(RESEND_API, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: fromEmail,
        to: [options.to],
        subject: options.subject,
        html: options.html,
      }),
    });
    return response.ok;
  } catch {
    return false;
  }
}

export function welcomeEmailHTML(): string {
  return `
    <!DOCTYPE html>
    <html><body style="font-family: -apple-system, BlinkMacSystemFont, sans-serif; max-width: 560px; margin: 40px auto; padding: 24px; color: #1e293b;">
      <h1 style="font-size: 22px; font-weight: 600; margin: 0 0 16px;">Welcome to Control-V Pro</h1>
      <p style="line-height: 1.6; font-size: 15px; margin: 0 0 16px;">
        Your subscription is active. From now on, your shortcut translates anywhere on your Mac — no daily limits.
      </p>
      <p style="line-height: 1.6; font-size: 15px; margin: 0 0 16px;">
        Open Control-V from your menu bar and start translating.
      </p>
      <p style="line-height: 1.6; font-size: 13px; color: #64748b; margin: 24px 0 0; padding-top: 16px; border-top: 1px solid #e2e8f0;">
        Need help? Reply to this email.<br/>
        Manage your subscription anytime from the app's "Manage" button.
      </p>
    </body></html>
  `.trim();
}

export function cancellationEmailHTML(): string {
  return `
    <!DOCTYPE html>
    <html><body style="font-family: -apple-system, BlinkMacSystemFont, sans-serif; max-width: 560px; margin: 40px auto; padding: 24px; color: #1e293b;">
      <h1 style="font-size: 22px; font-weight: 600; margin: 0 0 16px;">Your Control-V subscription was canceled</h1>
      <p style="line-height: 1.6; font-size: 15px; margin: 0 0 16px;">
        You'll keep access until the end of your current billing period. After that, the app will return to trial behavior.
      </p>
      <p style="line-height: 1.6; font-size: 15px; margin: 0 0 16px;">
        Changed your mind? You can resubscribe anytime from the app — same email, same account.
      </p>
      <p style="line-height: 1.6; font-size: 13px; color: #64748b; margin: 24px 0 0; padding-top: 16px; border-top: 1px solid #e2e8f0;">
        We'd love to hear what didn't work. Just reply to this email.
      </p>
    </body></html>
  `.trim();
}

export function pastDueEmailHTML(): string {
  return `
    <!DOCTYPE html>
    <html><body style="font-family: -apple-system, BlinkMacSystemFont, sans-serif; max-width: 560px; margin: 40px auto; padding: 24px; color: #1e293b;">
      <h1 style="font-size: 22px; font-weight: 600; margin: 0 0 16px;">Payment issue with your subscription</h1>
      <p style="line-height: 1.6; font-size: 15px; margin: 0 0 16px;">
        We couldn't process your last payment for Control-V Pro. To avoid losing access, please update your payment method.
      </p>
      <p style="line-height: 1.6; font-size: 15px; margin: 0 0 16px;">
        Open Control-V from your menu bar and click <strong>Manage</strong> to update your card.
      </p>
    </body></html>
  `.trim();
}
