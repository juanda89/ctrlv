# Legacy Paddle + Supabase Backend (Deprecated)

> Este módulo quedó como referencia histórica y **ya no es usado por el runtime de la app**.
> La app actual usa Lemon Squeezy con license key directa (sin login por email).

Este directorio implementa la capa comercial de `ctrl+v`:

- Webhook de Paddle (firma + idempotencia).
- Login por `email + magic code`.
- Endpoint de estado de suscripción para la app macOS.

## Estructura

- `migrations/20260224000100_paddle_subscription_foundation.sql`
- `functions/paddle-webhook`
- `functions/request-magic-code`
- `functions/verify-magic-code`
- `functions/subscription-status`

## Variables de entorno (Edge Functions)

- `PADDLE_WEBHOOK_SECRET`
- `MAGIC_CODE_PEPPER`
- `MAGIC_CODE_LIFETIME_MINUTES` (opcional, default `10`)
- `SESSION_LIFETIME_DAYS` (opcional, default `30`)
- `TRIAL_DAYS` (opcional, default `14`)
- `PADDLE_SIGNATURE_TOLERANCE_SECONDS` (opcional, default `300`)
- `RESEND_API_KEY` + `RESEND_FROM_EMAIL` (opcional para envío real)
- `ALLOW_DEV_MAGIC_CODE=true` (solo desarrollo local)

## Despliegue rápido

1. Aplicar migración:
   - `supabase migration up`
2. Deploy funciones:
   - `supabase functions deploy paddle-webhook --no-verify-jwt`
   - `supabase functions deploy request-magic-code --no-verify-jwt`
   - `supabase functions deploy verify-magic-code --no-verify-jwt`
   - `supabase functions deploy subscription-status --no-verify-jwt`
3. Configurar webhook en Paddle:
   - URL: `https://<project-ref>.functions.supabase.co/paddle-webhook`
   - Eventos mínimos: `customer.created`, `customer.updated`, `subscription.created`, `subscription.updated`, `subscription.canceled`

## Endpoints consumidos por la app

- `POST /request-magic-code` body: `{ "email": "you@example.com" }`
- `POST /verify-magic-code` body: `{ "email": "you@example.com", "code": "123456" }`
- `POST /subscription-status` header: `Authorization: Bearer <session_token>`

La disponibilidad de updates Sparkle no depende del estado de suscripción.
