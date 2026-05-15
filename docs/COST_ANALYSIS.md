# Cost Analysis — Control-V Pro at $8.99/mo

Updated: 2026-05. Purpose: validate whether $8.99/month is sustainable.

---

## TL;DR

Si un usuario hace **~600 traducciones/mes** (20/día) con texto promedio de **300 caracteres**, el COGS por usuario son ~$0.55/mes. A $8.99/mo de venta, el margen bruto es **~88%**. Pricing es saludable. El break-even contra los costos fijos llega rápido (~20–40 usuarios pagos).

---

## Cost components

### 1. Variable — escala con uso

| Servicio | Qué cobra | Tarifa actual | Estimación por traducción promedio |
|---|---|---|---|
| **OpenRouter (Grok 4.1 Fast)** | tokens IN + OUT | ~$0.20/M input, $0.50/M output | ~$0.0008 (300 char in + 300 out ≈ 200 tokens total) |
| **Stripe** | % por transacción | 2.9% + $0.30 USD | $0.56 sobre $8.99 (una sola vez al mes) |
| **Supabase Edge Functions** | invocaciones | $2 per 1M GB-seconds (≈ free hasta 500K invocations/mes en Pro) | Despreciable hasta ~30K usuarios |
| **Supabase DB** | filas + bandwidth | 8 GB free en Pro tier | Despreciable |
| **Resend** | emails enviados | $0 hasta 3,000/mes, luego $20/mes hasta 50K | $0 a tu volumen |
| **Vercel** | hosting landing | $0 (Hobby) o $20/mes (Pro si lo necesitas) | $0 |

### 2. Fijo — no escala con uso

| Item | Costo/año |
|---|---|
| Apple Developer Program | $99 |
| Dominio (control-v.info) | ~$15 |
| Supabase Pro (recomendado para producción) | $300 ($25/mes) |
| Subtotal fijos | **~$414/año = $34/mes** |

---

## Cálculo por usuario

### Asunciones de uso (ajustar con tus datos reales)

- **20 traducciones/día** de un usuario activo promedio (alto, conservador)
- **300 caracteres promedio** por request
- **30 días/mes**
- Token ratio: ~4 chars = 1 token. 300 chars ≈ 75 tokens input. Output suele ser similar.

### Por traducción
```
input tokens  = 75 + ~200 system prompt overhead = 275 tokens
output tokens = ~80 tokens
cost = (275 × $0.0000002) + (80 × $0.0000005)
     = $0.000055 + $0.00004
     = $0.0000950 ≈ $0.0001
```

### Por usuario por mes (uso intenso, 600 trad/mes)
```
LLM cost = 600 × $0.0001 = $0.06
Stripe fee = $0.56 (una vez al mes)
COGS total = $0.62
```

### Margen bruto
```
Revenue    $8.99
COGS      -$0.62
Margen    $8.37 (93%)
```

### Si el usuario es bestia (3000 trad/mes — nuestro límite paid)
```
LLM cost = 3000 × $0.0001 = $0.30
Stripe fee = $0.56
COGS total = $0.86
Margen = $8.13 (90%)
```

Incluso en el caso límite del rate limit (1500/día × 30 = 45K trad/mes, donde el usuario quema el límite todos los días):
```
LLM cost = 45,000 × $0.0001 = $4.50
Stripe fee = $0.56
COGS total = $5.06
Margen = $3.93 (44%)
```
**→ aun así es rentable.** Si alguien se acerca a esto, ya tiene rate limits activos (12k chars/req, 80 req/10min, 1.5M chars/día) que lo cortan.

---

## Break-even

Costos fijos: ~$34/mes (Apple Dev + dominio + Supabase Pro)

```
Usuarios pagos para cubrir fijos:
$34 / $8.37 (margen neto promedio) = 5 usuarios

Para cubrir un sueldo de $1,500/mes:
($1,500 + $34) / $8.37 = 184 usuarios pagos

Para cubrir $5,000/mes:
($5,000 + $34) / $8.37 = 602 usuarios pagos
```

---

## Riesgos a vigilar

1. **Modelo más caro** — si cambias de Grok 4.1 Fast a Claude Sonnet 4.5 ($3/$15 por M tokens), el costo por traducción se multiplica por ~30x:
   ```
   600 trad × $0.003 = $1.80/mes
   → margen baja de 93% a 73%. Sigue siendo bueno pero notas el cambio.
   ```
2. **Power users que comparten cuenta** — license_hash en account_subscriptions limita 1 cuenta = 1 user. Si Stripe permite multi-seat sin que lo controlemos, podrías ver costos x3 por suscripción.
3. **Stripe disputes/refunds** — un chargeback cuesta $15 + el monto reembolsado. Mantente vigilante en disputas.
4. **Apple notarization / cert renewal** — $99/año recurrente, fácil de olvidar.
5. **Resend si crece** — el tier de $20/mes da 50K emails. A 1 email/mes/usuario (welcome) eso son 50K usuarios antes de subir tier.

---

## Cómo verificar con números reales

### 1. OpenRouter — tu gasto real
Ve a https://openrouter.ai/settings/credits → tab "Activity":
- Verás tokens consumidos por día, semana, mes
- Revisa últimos 30 días vs # de translations en la DB
- Si te da > $0.001/translation hay algo raro (system prompt enorme, modelo distinto al esperado, etc.)

### 2. Supabase — uso actual
Dashboard → Reports → Usage:
- Edge Functions invocations
- Database egress
- Realtime messages (no usamos)
- Si estás en Free tier (no Pro), revisa si te acercas a los límites

### 3. Stripe — fees acumulados
Dashboard → Payments → "Stripe fees" report:
- Verás el % effective rate (debería rondar 3.2%)

### 4. Resend
Dashboard → API Keys → ver invocaciones del mes

### 5. Query directa en nuestra DB (con token de Supabase válido)
```sql
-- Total chars por mes
select
  date_trunc('month', created_at) as month,
  count(*) as translations,
  sum(char_count) as total_chars,
  count(distinct identity_hash) as unique_devices,
  count(*) filter (where plan = 'active') as paid_translations
from translation_usage_events
group by 1
order by 1 desc;

-- Top users por consumo
select
  identity_hash,
  count(*) as translations,
  sum(char_count) as total_chars,
  max(plan) as plan
from translation_usage_events
where created_at > now() - interval '30 days'
group by 1
order by total_chars desc
limit 10;
```

---

## Conclusión

A $8.99/mo el pricing es **fuertemente rentable** con el modelo actual (Grok 4.1 Fast). Margen bruto por usuario activo: 88-93%. Los costos fijos se cubren con **5-10 suscriptores**.

Cosas que cambiarían el cálculo:
- **Cambiar a Claude/GPT-4** → margen baja a 70-75% (sigue siendo bueno)
- **Soporte/atención al cliente** → si dedicas horas a soporte, el "costo real" sube por tu tiempo
- **Pricing por seats** → si abres team plans, el modelo cambia

**Recomendación:** mantén $8.99 mientras valides product-market fit. Si en 3-6 meses ves que hay demanda y poco churn, considera subir a $11.99-12.99/mo en nuevos signups (los actuales se quedan al precio viejo, "grandfathered").
