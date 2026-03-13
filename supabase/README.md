# Supabase Translation Backend

La app `ctrl+v` ya no debe pedir API keys al usuario.  
Este directorio contiene el backend que:

- valida licencias Lemon cuando existe una key activa,
- mantiene trial de 14 dias,
- aplica limites trial y fair-use pago,
- llama a OpenRouter con la key secreta del servidor,
- responde a la app con el texto traducido.

## Runtime actual

- Funcion Edge activa: `translate`
- Migracion base del gateway: `migrations/20260313000100_translation_gateway.sql`

## Variables de entorno requeridas

- `OPENROUTER_API_KEY`
- `OPENROUTER_MODEL=x-ai/grok-4.1-fast`
- `OPENROUTER_REFERER=https://control-v.info`
- `OPENROUTER_APP_NAME=ctrl+v`
- `LEMON_LICENSE_API_BASE_URL=https://api.lemonsqueezy.com`
- `TRIAL_DAYS=14`

## Limites por defecto

- Trial:
  - `TRIAL_DAILY_TRANSLATION_LIMIT=50`
  - `TRIAL_MAX_CHARACTERS=3000`
- Pago:
  - `PAID_REQUESTS_PER_10_MIN=80`
  - `PAID_REQUESTS_PER_DAY=1500`
  - `PAID_CHARACTERS_PER_DAY=1200000`
  - `PAID_MAX_CHARACTERS=12000`

## Despliegue

1. Aplicar migraciones:
   - `supabase migration up`
2. Deploy de la funcion:
   - `supabase functions deploy translate --no-verify-jwt`
3. Configurar secrets:
   - `supabase secrets set OPENROUTER_API_KEY=...`
   - `supabase secrets set OPENROUTER_MODEL=x-ai/grok-4.1-fast`
   - `supabase secrets set OPENROUTER_REFERER=https://control-v.info`
   - `supabase secrets set OPENROUTER_APP_NAME=ctrl+v`
4. Configurar la app con:
   - `CtrlVTranslationAPIURL=https://<project-ref>.functions.supabase.co/translate`

## Notas

- La key de OpenRouter nunca debe ir en el repo ni en la app.
- La app sigue validando localmente el estado trial/licencia para UX rapida, pero el backend vuelve a verificar limites antes de llamar al modelo.
- Las funciones Paddle y magic-code que aun existen en este directorio quedan como legacy y no son parte del runtime actual.
