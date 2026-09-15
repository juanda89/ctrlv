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

export type FeedbackEmailInput = {
  rating: number | null;
  category: string;
  message: string;
  contactEmail: string | null;
  accountEmail: string | null;
  appVersion: string | null;
  platform: string;
  installIDHash: string;
};

export function feedbackEmailSubject(input: FeedbackEmailInput): string {
  const stars = input.rating ? "★".repeat(input.rating) + "☆".repeat(5 - input.rating) : "no rating";
  return `ctrl+v feedback · ${stars} · ${input.category}`;
}

export function feedbackEmailHTML(input: FeedbackEmailInput): string {
  const who = input.accountEmail
    ? `${escapeHTML(input.accountEmail)} (signed in)`
    : input.contactEmail
      ? `${escapeHTML(input.contactEmail)} (trial, gave email)`
      : `trial user · install ${input.installIDHash.slice(0, 10)}`;
  const stars = input.rating ? "★".repeat(input.rating) + "☆".repeat(5 - input.rating) : "—";
  const message = input.message.trim().length > 0
    ? escapeHTML(input.message).replace(/\n/g, "<br/>")
    : "<em>(no message)</em>";
  return `
    <!DOCTYPE html>
    <html><body style="font-family: -apple-system, BlinkMacSystemFont, sans-serif; max-width: 600px; margin: 40px auto; padding: 24px; color: #1e293b;">
      <h1 style="font-size: 20px; font-weight: 600; margin: 0 0 16px;">New feedback · ${escapeHTML(input.category)}</h1>
      <p style="font-size: 26px; letter-spacing: 2px; margin: 0 0 16px; color: #d97706;">${stars}</p>
      <p style="line-height: 1.6; font-size: 15px; margin: 0 0 16px; padding: 14px 16px; background: #f8fafc; border-radius: 8px;">${message}</p>
      <table style="font-size: 13px; color: #64748b; border-collapse: collapse;">
        <tr><td style="padding: 2px 12px 2px 0;">From</td><td>${who}</td></tr>
        <tr><td style="padding: 2px 12px 2px 0;">App</td><td>${escapeHTML(input.appVersion ?? "unknown")} · ${escapeHTML(input.platform)}</td></tr>
      </table>
    </body></html>
  `.trim();
}

function escapeHTML(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}
