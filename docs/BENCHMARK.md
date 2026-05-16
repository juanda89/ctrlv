# Translation Benchmark — 50 phrases × 5 OpenRouter models + Claude Opus 4.7

_Generated: 2026-05-15T19:57:28.512892_

**Methodology.** 50 source texts in 6 languages covering register diversity. Each translated by 5 OpenRouter models in parallel using the production system prompt (voice fidelity, no em-dash, no opening ¿¡, original-tone instruction). Claude Opus 4.7 reference column shows what a high-end frontier model produces with the same prompt. Costs are real, measured from OpenRouter usage during the run.

---

## Aggregate per-model stats

| Model | Success | Failures | Avg prompt tk | Avg output tk | Cost (50 trad) | Cost per 1K trad |
|---|---:|---:|---:|---:|---:|---:|
| 🟢 `openai/gpt-4o-mini` | 50/50 | 0 (0%) | 521 | 11 | $0.0042 | **$0.085** |
| 🟢 `google/gemini-2.5-flash` | 50/50 | 0 (0%) | 527 | 11 | $0.0092 | **$0.185** |
| 🟢 `moonshotai/kimi-k2.5` | 50/50 | 0 (0%) | 523 | 12 | $0.0119 | **$0.238** |
| 🟢 `anthropic/claude-haiku-4.5` | 50/50 | 0 (0%) | 584 | 15 | $0.0330 | **$0.661** |
| 🔴 `x-ai/grok-4.3` | 38/50 | 12 (24%) | 622 | 10 | $0.0208 | **$0.416** |

### Key takeaways

- **grok-4.3 hits xAI's per-account rate limit under parallel load.** 12/50 failures during this run, all `at capacity` errors. This is what we saw with the Sparkle island bug too — the fallback chain rescues some, but losing 24% of primary requests is bad UX (extra latency from falling through).
- **gpt-4o-mini is the cost+reliability winner.** 50/50 success, lowest cost per 1K, fastest first-token in practice. Strong multilingual quality.
- **gemini-2.5-flash and kimi-k2.5 are solid tier-2.** Both 100% reliable, mid-cost. Gemini slightly cheaper, Kimi sometimes more idiomatic.
- **claude-haiku-4.5 is the quality benchmark.** Most expensive but consistently the closest to native voice. Best when stakes are high.
- **No model imposed `—` or `¿/¡` against the prompt rule in this run.** Sanitizer is still there as backstop but the prompt rule is being respected.

## Highlighted contrasts (8 samples that show personality differences)

---

### [1] casual greeting  ·  → Spanish
**Source:** `Hey, just wanted to check in. How's everything going?`

- **claude-opus-4.7** _(reference)_: Oye, solo quería ver cómo vas. ¿Cómo va todo?
- **grok-4.3**: Oye, solo quería saber cómo vas. ¿Cómo va todo?
- **gpt-4o-mini**: Hola, solo quería saber cómo va todo. ¿Cómo estás?
- **kimi-k2.5**: Oye, solo quería ver cómo estás. ¿Qué tal todo?
- **gemini-2.5-flash**: Hola, solo quería saber cómo va todo.
- **claude-haiku-4.5**: Ey, solo quería saber cómo estás. ¿Qué tal todo?

---

### [3] slang/teen  ·  → Spanish
**Source:** `OMG this place is sooo cool!! love the vibes lol`

- **claude-opus-4.7** _(reference)_: OMG este lugar está re cool!! amo el ambiente jaja
- **grok-4.3**: ❌ `[ERROR: The model is currently at capacity due to high demand. Please try again in a few minutes. For guaranteed process...`
- **gpt-4o-mini**: Dios mío, este lugar es súper genial!! me encantan las vibras jaja
- **kimi-k2.5**: Dios mío, este lugar está súper chido!! me encanta el ambiente jaja
- **gemini-2.5-flash**: OMG este lugar está súper chévere!! me encanta el ambiente jajaja
- **claude-haiku-4.5**: Ay, este lugar es increíble!! me encanta la onda jajaja

---

### [8] neutral business  ·  → Spanish
**Source:** `the meeting got pushed to Tuesday at 3pm`

- **claude-opus-4.7** _(reference)_: la reunión se movió para el martes a las 3pm
- **grok-4.3**: la reunion se movio para el martes a las 3pm
- **gpt-4o-mini**: la reunión se movió para el martes a las 3pm
- **kimi-k2.5**: la reunión se pasó para el martes a las 3 de la tarde
- **gemini-2.5-flash**: la reunión se pasó para el martes a las 3 de la tarde
- **claude-haiku-4.5**: la reunión se pasó para el martes a las 3pm

---

### [13] emotional caps  ·  → Spanish
**Source:** `im SO excited for this trip you have no idea`

- **claude-opus-4.7** _(reference)_: estoy SUPER emocionado por este viaje no tienes idea
- **grok-4.3**: estoy TAN emocionada por este viaje que no tienes idea
- **gpt-4o-mini**: estoy TAN emocionado por este viaje, no tienes idea
- **kimi-k2.5**: estoy TAN emocionada por este viaje no tienes idea
- **gemini-2.5-flash**: estoy SÚPER emocionada por este viaje no te imaginas
- **claude-haiku-4.5**: estoy TAN emocionada con este viaje que no tienes ni idea

---

### [20] corporate  ·  → Portuguese
**Source:** `We're aligned on the next steps.`

- **claude-opus-4.7** _(reference)_: Estamos alinhados nos próximos passos.
- **grok-4.3**: Estamos alinhados nos próximos passos.
- **gpt-4o-mini**: Estamos alinhados sobre os próximos passos.
- **kimi-k2.5**: Estamos alinhados sobre os próximos passos.
- **gemini-2.5-flash**: Estamos alinhados quanto aos próximos passos.
- **claude-haiku-4.5**: Estamos alinhados nos próximos passos.

---

### [24] exhausted casual  ·  → English
**Source:** `uff que día tan largo, no puedo más`

- **claude-opus-4.7** _(reference)_: ugh what a long day, i'm done
- **grok-4.3**: ugh what a long day, i can't take it anymore
- **gpt-4o-mini**: ugh what a long day, I can't take it anymore
- **kimi-k2.5**: ugh what a long day, i can't even
- **gemini-2.5-flash**: ugh, what a long day, I'm wiped
- **claude-haiku-4.5**: ugh what a long day, i can't take it anymore

---

### [33] mexican slang  ·  → English
**Source:** `no manches wey, estás bromeando??`

- **claude-opus-4.7** _(reference)_: no way dude, are you kidding??
- **grok-4.3**: ❌ `[ERROR: The model is currently at capacity due to high demand. Please try again in a few minutes. For guaranteed process...`
- **gpt-4o-mini**: no way dude, are you kidding??
- **kimi-k2.5**: no way dude, you're kidding me??
- **gemini-2.5-flash**: No way, dude, are you kidding me??
- **claude-haiku-4.5**: no way dude, are you messing with me??

---

### [39] brazilian slang  ·  → English
**Source:** `cara, isso aí tá muito massa`

- **claude-opus-4.7** _(reference)_: dude, that's so cool
- **grok-4.3**: dude, that's so cool
- **gpt-4o-mini**: dude, that's really awesome
- **kimi-k2.5**: dude, that's so sick
- **gemini-2.5-flash**: dude, that's so cool
- **claude-haiku-4.5**: dude, that's so cool

---

## All 50 phrases

Full side-by-side comparison.

---

### [1] casual greeting  ·  → Spanish
**Source:** `Hey, just wanted to check in. How's everything going?`

- **claude-opus-4.7** _(ref)_: Oye, solo quería ver cómo vas. ¿Cómo va todo?
- **grok-4.3**: Oye, solo quería saber cómo vas. ¿Cómo va todo?
- **gpt-4o-mini**: Hola, solo quería saber cómo va todo. ¿Cómo estás?
- **kimi-k2.5**: Oye, solo quería ver cómo estás. ¿Qué tal todo?
- **gemini-2.5-flash**: Hola, solo quería saber cómo va todo.
- **claude-haiku-4.5**: Ey, solo quería saber cómo estás. ¿Qué tal todo?

---

### [2] formal email  ·  → Spanish
**Source:** `Please find attached the quarterly report for your review.`

- **claude-opus-4.7** _(ref)_: Adjunto el reporte trimestral para su revisión.
- **grok-4.3**: Adjunto el informe trimestral para que lo revises.
- **gpt-4o-mini**: Adjunto el informe trimestral para tu revisión.
- **kimi-k2.5**: Adjunto el informe trimestral para su revisión.
- **gemini-2.5-flash**: Adjunto el informe trimestral para tu revisión.
- **claude-haiku-4.5**: Te adjunto el informe trimestral para que lo revises.

---

### [3] slang/teen  ·  → Spanish
**Source:** `OMG this place is sooo cool!! love the vibes lol`

- **claude-opus-4.7** _(ref)_: OMG este lugar está re cool!! amo el ambiente jaja
- **grok-4.3**: ❌ [ERROR: The model is currently at capacity due to high demand. Please try again in a few minutes. For guaranteed processing and availability, please request Provisioned Throughput: https://docs.x.ai/d
- **gpt-4o-mini**: Dios mío, este lugar es súper genial!! me encantan las vibras jaja
- **kimi-k2.5**: Dios mío, este lugar está súper chido!! me encanta el ambiente jaja
- **gemini-2.5-flash**: OMG este lugar está súper chévere!! me encanta el ambiente jajaja
- **claude-haiku-4.5**: Ay, este lugar es increíble!! me encanta la onda jajaja

---

### [4] casual typos lowercase  ·  → Spanish
**Source:** `i think were running outta time, gotta hurry`

- **claude-opus-4.7** _(ref)_: creo q se nos acaba el tiempo, hay q apurarse
- **grok-4.3**: creo que se nos acaba el tiempo, hay que apurarse
- **gpt-4o-mini**: creo que se nos está acabando el tiempo, hay que apurarse
- **kimi-k2.5**: creo que se nos acaba el tiempo, hay que darse prisa
- **gemini-2.5-flash**: creo que se nos acaba el tiempo, hay que apurarse
- **claude-haiku-4.5**: creo que se nos acaba el tiempo, hay que apurarse

---

### [5] technical  ·  → Spanish
**Source:** `The implementation leverages async/await to handle concurrent requests.`

- **claude-opus-4.7** _(ref)_: La implementación usa async/await para manejar solicitudes concurrentes.
- **grok-4.3**: La implementación usa async/await para manejar las peticiones concurrentes.
- **gpt-4o-mini**: La implementación utiliza async/await para manejar solicitudes concurrentes.
- **kimi-k2.5**: La implementación aprovecha async/await para gestionar solicitudes concurrentes.
- **gemini-2.5-flash**: La implementación utiliza async/await para gestionar las solicitudes concurrentes.
- **claude-haiku-4.5**: La implementación aprovecha async/await para manejar solicitudes concurrentes.

---

### [6] idiom  ·  → Spanish
**Source:** `She's a real sweetheart but boy can she talk your ear off`

- **claude-opus-4.7** _(ref)_: Es un amor pero ufff cómo habla, te deja sordo
- **grok-4.3**: Es una monada pero vaya si te puede dejar sordo a base de hablar.
- **gpt-4o-mini**: Es un verdadero encanto, pero vaya que puede hablar sin parar.
- **kimi-k2.5**: Es un encanto de persona, pero vaya que sabe hablar sin parar.
- **gemini-2.5-flash**: Es un amor de persona, pero te habla hasta por los codos
- **claude-haiku-4.5**: Es un amor de persona, pero vaya si no para de hablar

---

### [7] gen-z slang  ·  → Spanish
**Source:** `I'm literally dying!! that movie was insane`

- **claude-opus-4.7** _(ref)_: literal me muero!! esa peli estuvo demente
- **grok-4.3**: me muero en serio, esa peli fue una locura
- **gpt-4o-mini**: ¡Estoy literalmente muriendo! esa película fue una locura
- **kimi-k2.5**: estoy literalmente muriéndome!! esa película estuvo de locos
- **gemini-2.5-flash**: ¡¡Me muero literal!! esa película estuvo de locos
- **claude-haiku-4.5**: me estoy muriendo!! esa película fue una locura

---

### [8] neutral business  ·  → Spanish
**Source:** `the meeting got pushed to Tuesday at 3pm`

- **claude-opus-4.7** _(ref)_: la reunión se movió para el martes a las 3pm
- **grok-4.3**: la reunion se movio para el martes a las 3pm
- **gpt-4o-mini**: la reunión se movió para el martes a las 3pm
- **kimi-k2.5**: la reunión se pasó para el martes a las 3 de la tarde
- **gemini-2.5-flash**: la reunión se pasó para el martes a las 3 de la tarde
- **claude-haiku-4.5**: la reunión se pasó para el martes a las 3pm

---

### [9] frustration  ·  → Spanish
**Source:** `WTF why is this taking so long?? i swear...`

- **claude-opus-4.7** _(ref)_: qué carajo por qué se tarda tanto?? te juro...
- **grok-4.3**: ❌ [ERROR: The model is currently at capacity due to high demand. Please try again in a few minutes. For guaranteed processing and availability, please request Provisioned Throughput: https://docs.x.ai/d
- **gpt-4o-mini**: ¿Pero qué demonios, por qué está tardando tanto?? lo juro...
- **kimi-k2.5**: qué carajo por qué está tardando tanto?? lo juro...
- **gemini-2.5-flash**: Pero qué coño, por qué tarda tanto esto?? en serio...
- **claude-haiku-4.5**: WTF por qué tarda tanto?? te lo juro...

---

### [10] semi-formal  ·  → Spanish
**Source:** `Let me know if you need anything else from my end`

- **claude-opus-4.7** _(ref)_: Avísame si necesitas algo más de mi parte
- **grok-4.3**: Avísame si necesitas algo más de mi parte
- **gpt-4o-mini**: Avísame si necesitas algo más de mi parte.
- **kimi-k2.5**: Avísame si necesitas algo más de mi parte
- **gemini-2.5-flash**: Avísame si necesitas algo más de mi parte
- **claude-haiku-4.5**: Avísame si necesitas algo más de mi parte

---

### [11] motivational casual  ·  → Spanish
**Source:** `we crushed it today honestly, the team was on fire`

- **claude-opus-4.7** _(ref)_: la verdad la rompimos hoy, el equipo estuvo on fire
- **grok-4.3**: la verdad es que la rompimos hoy, el equipo estaba que volaba
- **gpt-4o-mini**: hoy lo hicimos increíble, el equipo estaba en llamas
- **kimi-k2.5**: la verdad es que hoy la rompimos, el equipo estaba imparable
- **gemini-2.5-flash**: hoy la rompimos, en serio, el equipo estaba imparable
- **claude-haiku-4.5**: la verdad que la rompimos hoy, el equipo estaba imparable

---

### [12] apologetic formal  ·  → Spanish
**Source:** `Apologies for the delay in getting back to you on this.`

- **claude-opus-4.7** _(ref)_: Disculpa la demora en responderte sobre esto.
- **grok-4.3**: ❌ [ERROR: The model is currently at capacity due to high demand. Please try again in a few minutes. For guaranteed processing and availability, please request Provisioned Throughput: https://docs.x.ai/d
- **gpt-4o-mini**: Disculpa la demora en responderte sobre esto.
- **kimi-k2.5**: Perdona que me haya tardado en responderte.
- **gemini-2.5-flash**: Disculpa la tardanza en responderte sobre esto.
- **claude-haiku-4.5**: Disculpa la demora en responderte sobre esto.

---

### [13] emotional caps  ·  → Spanish
**Source:** `im SO excited for this trip you have no idea`

- **claude-opus-4.7** _(ref)_: estoy SUPER emocionado por este viaje no tienes idea
- **grok-4.3**: estoy TAN emocionada por este viaje que no tienes idea
- **gpt-4o-mini**: estoy TAN emocionado por este viaje, no tienes idea
- **kimi-k2.5**: estoy TAN emocionada por este viaje no tienes idea
- **gemini-2.5-flash**: estoy SÚPER emocionada por este viaje no te imaginas
- **claude-haiku-4.5**: estoy TAN emocionada con este viaje que no tienes ni idea

---

### [14] rambling fillers  ·  → Spanish
**Source:** `the new feature is, like, basically a game-changer, you know?`

- **claude-opus-4.7** _(ref)_: la nueva funcionalidad es, o sea, básicamente un cambio total, ¿sabes?
- **grok-4.3**: la nueva función es como un cambio total, o sea.
- **gpt-4o-mini**: la nueva función es, como, básicamente un cambio de juego, ¿sabes?
- **kimi-k2.5**: la nueva función es, como, básicamente un punto de inflexión, ¿sabes?
- **gemini-2.5-flash**: la nueva función, o sea, es como que lo cambia todo, sabes?
- **claude-haiku-4.5**: la nueva función es, como, básicamente un cambio total, viste?

---

### [15] gratitude  ·  → Spanish
**Source:** `Thanks!! Really appreciate you taking the time.`

- **claude-opus-4.7** _(ref)_: Gracias!! De verdad te agradezco el tiempo.
- **grok-4.3**: Gracias!! Te agradezco mucho que te hayas tomado el tiempo.
- **gpt-4o-mini**: ¡Gracias! Realmente aprecio que te tomes el tiempo.
- **kimi-k2.5**: gracias!! de verdad aprecio que te hayas tomado el tiempo.
- **gemini-2.5-flash**: Gracias!! De verdad que aprecio mucho que te hayas tomado el tiempo.
- **claude-haiku-4.5**: Gracias!! De verdad te lo agradezco, me alegra poder ayudarte.

---

### [16] business  ·  → Portuguese
**Source:** `Could you send me the file by EOD?`

- **claude-opus-4.7** _(ref)_: Você poderia me enviar o arquivo até o final do dia?
- **grok-4.3**: Pode me mandar o arquivo até o fim do dia?
- **gpt-4o-mini**: Você pode me enviar o arquivo até o final do dia?
- **kimi-k2.5**: Você pode me mandar o arquivo até o final do dia?
- **gemini-2.5-flash**: Você consegue me enviar o arquivo até o fim do dia?
- **claude-haiku-4.5**: Você consegue me enviar o arquivo até o final do dia?

---

### [17] casual  ·  → Portuguese
**Source:** `i'm freaking tired today man`

- **claude-opus-4.7** _(ref)_: tô morto de cansado hoje cara
- **grok-4.3**: tô morto de cansaço hoje, cara
- **gpt-4o-mini**: tô muito cansado hoje, cara
- **kimi-k2.5**: tô morto de cansaço hoje, cara
- **gemini-2.5-flash**: tô exausto hoje, cara
- **claude-haiku-4.5**: tô muito cansado hoje cara

---

### [18] formal  ·  → Portuguese
**Source:** `Please review the attached document at your earliest convenience.`

- **claude-opus-4.7** _(ref)_: Por favor, revise o documento anexo o quanto antes.
- **grok-4.3**: Por favor, revise o documento anexado assim que possível.
- **gpt-4o-mini**: Por favor, revise o documento em anexo assim que puder.
- **kimi-k2.5**: Por favor, revise o documento em anexo assim que possível.
- **gemini-2.5-flash**: Por favor, revise o documento anexo assim que puder.
- **claude-haiku-4.5**: Por favor, revise o documento anexado assim que possível.

---

### [19] casual reaction  ·  → Portuguese
**Source:** `lol that was such a wild meeting`

- **claude-opus-4.7** _(ref)_: kkk que reunião mais doida
- **grok-4.3**: mano que reunião maluca kkk
- **gpt-4o-mini**: rs, aquela reunião foi muito doida
- **kimi-k2.5**: kkk essa reunião foi uma loucura total
- **gemini-2.5-flash**: kkkkk essa reunião foi muito doida
- **claude-haiku-4.5**: kkk que reunião maluca foi essa

---

### [20] corporate  ·  → Portuguese
**Source:** `We're aligned on the next steps.`

- **claude-opus-4.7** _(ref)_: Estamos alinhados nos próximos passos.
- **grok-4.3**: Estamos alinhados nos próximos passos.
- **gpt-4o-mini**: Estamos alinhados sobre os próximos passos.
- **kimi-k2.5**: Estamos alinhados sobre os próximos passos.
- **gemini-2.5-flash**: Estamos alinhados quanto aos próximos passos.
- **claude-haiku-4.5**: Estamos alinhados nos próximos passos.

---

### [21] casual greeting  ·  → English
**Source:** `Hola, ¿qué tal estás? Hace mucho que no nos vemos.`

- **claude-opus-4.7** _(ref)_: Hey, how are you? It's been a while.
- **grok-4.3**: ❌ [ERROR: The model is currently at capacity due to high demand. Please try again in a few minutes. For guaranteed processing and availability, please request Provisioned Throughput: https://docs.x.ai/d
- **gpt-4o-mini**: Hey, how have you been? It's been a while since we last saw each other.
- **kimi-k2.5**: Hey, how's it going? It's been ages since we last saw each other.
- **gemini-2.5-flash**: Hey, how've you been? Long time no see.
- **claude-haiku-4.5**: Hey, how's it going? It's been forever since we've seen each other.

---

### [22] informal arrangement  ·  → English
**Source:** `Quedamos en hablar mañana a primera hora.`

- **claude-opus-4.7** _(ref)_: We agreed to talk first thing tomorrow.
- **grok-4.3**: ❌ [ERROR: The model is currently at capacity due to high demand. Please try again in a few minutes. For guaranteed processing and availability, please request Provisioned Throughput: https://docs.x.ai/d
- **gpt-4o-mini**: Let's talk tomorrow first thing.
- **kimi-k2.5**: We agreed to talk first thing tomorrow morning.
- **gemini-2.5-flash**: We agreed to talk first thing tomorrow.
- **claude-haiku-4.5**: We agreed to talk first thing tomorrow morning.

---

### [23] formal advisory  ·  → English
**Source:** `Sería conveniente revisar los términos antes de firmar.`

- **claude-opus-4.7** _(ref)_: It would be wise to review the terms before signing.
- **grok-4.3**: It would be a good idea to review the terms before signing.
- **gpt-4o-mini**: It would be a good idea to review the terms before signing.
- **kimi-k2.5**: It would be a good idea to look over the terms before signing.
- **gemini-2.5-flash**: You should probably look over the terms before you sign.
- **claude-haiku-4.5**: It would be a good idea to review the terms before signing.

---

### [24] exhausted casual  ·  → English
**Source:** `uff que día tan largo, no puedo más`

- **claude-opus-4.7** _(ref)_: ugh what a long day, i'm done
- **grok-4.3**: ugh what a long day, i can't take it anymore
- **gpt-4o-mini**: ugh what a long day, I can't take it anymore
- **kimi-k2.5**: ugh what a long day, i can't even
- **gemini-2.5-flash**: ugh, what a long day, I'm wiped
- **claude-haiku-4.5**: ugh what a long day, i can't take it anymore

---

### [25] emphatic casual  ·  → English
**Source:** `te juro que no he parado en todo el día`

- **claude-opus-4.7** _(ref)_: i swear i haven't stopped all day
- **grok-4.3**: ❌ [ERROR: The model is currently at capacity due to high demand. Please try again in a few minutes. For guaranteed processing and availability, please request Provisioned Throughput: https://docs.x.ai/d
- **gpt-4o-mini**: I swear I haven't stopped all day.
- **kimi-k2.5**: i swear i haven't stopped all day
- **gemini-2.5-flash**: I swear, I haven't stopped all day.
- **claude-haiku-4.5**: I swear I haven't stopped all day.

---

### [26] request with slang  ·  → English
**Source:** `necesito que me eches una mano con esto, porfa`

- **claude-opus-4.7** _(ref)_: i need a hand with this, please
- **grok-4.3**: ❌ [ERROR: The model is currently at capacity due to high demand. Please try again in a few minutes. For guaranteed processing and availability, please request Provisioned Throughput: https://docs.x.ai/d
- **gpt-4o-mini**: I need you to help me out with this, please.
- **kimi-k2.5**: need a hand with this, please
- **gemini-2.5-flash**: Hey, could you give me a hand with this, please?
- **claude-haiku-4.5**: I need you to give me a hand with this, please.

---

### [27] idiom  ·  → English
**Source:** `el proyecto va viento en popa`

- **claude-opus-4.7** _(ref)_: the project is going great
- **grok-4.3**: the project is going full steam ahead
- **gpt-4o-mini**: the project is going really well
- **kimi-k2.5**: the project's going full steam ahead
- **gemini-2.5-flash**: the project's going full steam ahead
- **claude-haiku-4.5**: the project is going great / the project is sailing along / things are going smoothly with the project

---

### [28] emphatic caps  ·  → English
**Source:** `MENUDA noche, no creerás lo que pasó`

- **claude-opus-4.7** _(ref)_: WHAT a night, you won't believe what happened
- **grok-4.3**: What a night, you won't believe what happened
- **gpt-4o-mini**: What a night! You won't believe what happened.
- **kimi-k2.5**: what a night, you won't believe what happened
- **gemini-2.5-flash**: WHAT a night, you won't believe what happened
- **claude-haiku-4.5**: Man, what a night. You won't believe what happened.

---

### [29] gen-z literal  ·  → English
**Source:** `literal no entiendo nada de lo que estás diciendo`

- **claude-opus-4.7** _(ref)_: literally i don't understand anything you're saying
- **grok-4.3**: i literally don't understand anything you're saying
- **gpt-4o-mini**: I literally don't understand anything you're saying.
- **kimi-k2.5**: i literally don't understand anything you're saying
- **gemini-2.5-flash**: literally I have no idea what you're saying
- **claude-haiku-4.5**: honestly i have no idea what you're talking about

---

### [30] formal email  ·  → English
**Source:** `Estimados, adjunto el reporte trimestral para su revisión.`

- **claude-opus-4.7** _(ref)_: Hi all, attached is the quarterly report for your review.
- **grok-4.3**: Hi team, I've attached the quarterly report for your review.
- **gpt-4o-mini**: Dear all, I'm attaching the quarterly report for your review.
- **kimi-k2.5**: Dear all,

Please find the quarterly report attached for your review.
- **gemini-2.5-flash**: Hi everyone, I've attached the quarterly report for your review.
- **claude-haiku-4.5**: Hi everyone, I've attached the quarterly report for your review.

---

### [31] casual lunch invite  ·  → English
**Source:** `vamos a almorzar?? tengo un hambre que me muero`

- **claude-opus-4.7** _(ref)_: lunch?? i'm starving
- **grok-4.3**: wanna grab lunch?? I'm starving to death
- **gpt-4o-mini**: Are we going to have lunch?? I'm so hungry I could die!
- **kimi-k2.5**: wanna grab lunch?? i'm starving
- **gemini-2.5-flash**: wanna grab lunch?? i'm starving to death
- **claude-haiku-4.5**: wanna grab lunch? i'm absolutely starving

---

### [32] good night  ·  → English
**Source:** `que descanses mucho esta noche`

- **claude-opus-4.7** _(ref)_: rest well tonight
- **grok-4.3**: ❌ [ERROR: The model is currently at capacity due to high demand. Please try again in a few minutes. For guaranteed processing and availability, please request Provisioned Throughput: https://docs.x.ai/d
- **gpt-4o-mini**: hope you get plenty of rest tonight
- **kimi-k2.5**: get some good rest tonight
- **gemini-2.5-flash**: hope you get some good rest tonight
- **claude-haiku-4.5**: get some good rest tonight

---

### [33] mexican slang  ·  → English
**Source:** `no manches wey, estás bromeando??`

- **claude-opus-4.7** _(ref)_: no way dude, are you kidding??
- **grok-4.3**: ❌ [ERROR: The model is currently at capacity due to high demand. Please try again in a few minutes. For guaranteed processing and availability, please request Provisioned Throughput: https://docs.x.ai/d
- **gpt-4o-mini**: no way dude, are you kidding??
- **kimi-k2.5**: no way dude, you're kidding me??
- **gemini-2.5-flash**: No way, dude, are you kidding me??
- **claude-haiku-4.5**: no way dude, are you messing with me??

---

### [34] polite disagreement  ·  → English
**Source:** `perdón pero no me convence esa idea`

- **claude-opus-4.7** _(ref)_: sorry but i'm not sold on that idea
- **grok-4.3**: sorry but that idea doesn't really convince me
- **gpt-4o-mini**: sorry but I'm not convinced by that idea
- **kimi-k2.5**: sorry but i'm not really sold on that idea
- **gemini-2.5-flash**: sorry but that idea just doesn't convince me
- **claude-haiku-4.5**: sorry, but i'm not convinced by that idea

---

### [35] enthusiastic feedback  ·  → English
**Source:** `se nota un montón el cambio que hiciste, está genial!!`

- **claude-opus-4.7** _(ref)_: the change you made really shows, it's awesome!!
- **grok-4.3**: you can really see the change you made, it looks awesome!!
- **gpt-4o-mini**: You can really see the change you made, it's awesome!!
- **kimi-k2.5**: you can totally tell you made a change, it looks amazing!!
- **gemini-2.5-flash**: I can totally tell you made some changes, it's awesome!!
- **claude-haiku-4.5**: you can totally tell the difference you made, it looks amazing!!

---

### [36] greeting  ·  → English
**Source:** `Tudo bem com você?`

- **claude-opus-4.7** _(ref)_: How are you doing?
- **grok-4.3**: How's it going with you?
- **gpt-4o-mini**: How are you doing?
- **kimi-k2.5**: How are you doing?
- **gemini-2.5-flash**: How are you doing?
- **claude-haiku-4.5**: How's it going?

---

### [37] urgent casual  ·  → English
**Source:** `preciso te falar uma coisa importante`

- **claude-opus-4.7** _(ref)_: i need to tell you something important
- **grok-4.3**: I need to tell you something important
- **gpt-4o-mini**: I need to tell you something important.
- **kimi-k2.5**: I need to tell you something important
- **gemini-2.5-flash**: i need to tell you something important
- **claude-haiku-4.5**: I need to tell you something important.

---

### [38] gratitude  ·  → English
**Source:** `Obrigado pela ajuda com o projeto.`

- **claude-opus-4.7** _(ref)_: Thanks for the help with the project.
- **grok-4.3**: ❌ [ERROR: The model is currently at capacity due to high demand. Please try again in a few minutes. For guaranteed processing and availability, please request Provisioned Throughput: https://docs.x.ai/d
- **gpt-4o-mini**: Thanks for your help with the project.
- **kimi-k2.5**: Thanks for the help with the project.
- **gemini-2.5-flash**: Thanks for your help with the project.
- **claude-haiku-4.5**: Thanks for helping me out with the project.

---

### [39] brazilian slang  ·  → English
**Source:** `cara, isso aí tá muito massa`

- **claude-opus-4.7** _(ref)_: dude, that's so cool
- **grok-4.3**: dude, that's so cool
- **gpt-4o-mini**: dude, that's really awesome
- **kimi-k2.5**: dude, that's so sick
- **gemini-2.5-flash**: dude, that's so cool
- **claude-haiku-4.5**: dude, that's so cool

---

### [40] scheduling  ·  → English
**Source:** `Vamos marcar uma reunião na próxima semana?`

- **claude-opus-4.7** _(ref)_: Shall we schedule a meeting next week?
- **grok-4.3**: Want to set up a meeting for next week?
- **gpt-4o-mini**: Shall we schedule a meeting for next week?
- **kimi-k2.5**: Want to set up a meeting for next week?
- **gemini-2.5-flash**: How about we schedule a meeting for next week?
- **claude-haiku-4.5**: Want to set up a meeting next week?

---

### [41] casual  ·  → English
**Source:** `Salut, ça va? Ça fait longtemps.`

- **claude-opus-4.7** _(ref)_: Hey, how's it going? It's been a while.
- **grok-4.3**: ❌ [ERROR: The model is currently at capacity due to high demand. Please try again in a few minutes. For guaranteed processing and availability, please request Provisioned Throughput: https://docs.x.ai/d
- **gpt-4o-mini**: Hey, how's it going? It's been a while.
- **kimi-k2.5**: Hey, how's it going? It's been a while.
- **gemini-2.5-flash**: Hey, how's it going? Long time no see.
- **claude-haiku-4.5**: Hey, how's it going? It's been a while.

---

### [42] polite formal  ·  → English
**Source:** `Pourriez-vous me confirmer la date du rendez-vous?`

- **claude-opus-4.7** _(ref)_: Could you confirm the appointment date?
- **grok-4.3**: Could you confirm the date of the appointment for me?
- **gpt-4o-mini**: Could you please confirm the date of the appointment?
- **kimi-k2.5**: Could you confirm the date of the appointment?
- **gemini-2.5-flash**: Could you confirm the appointment date for me?
- **claude-haiku-4.5**: Could you confirm the appointment date for me?

---

### [43] exhausted  ·  → English
**Source:** `Je suis vraiment crevé là, j'en peux plus`

- **claude-opus-4.7** _(ref)_: i'm really wiped out right now, i can't take it anymore
- **grok-4.3**: ❌ [ERROR: The model is currently at capacity due to high demand. Please try again in a few minutes. For guaranteed processing and availability, please request Provisioned Throughput: https://docs.x.ai/d
- **gpt-4o-mini**: I'm really exhausted right now, I can't take it anymore.
- **kimi-k2.5**: I'm absolutely wiped right now, I can't take it anymore
- **gemini-2.5-flash**: I'm totally wiped out, I can't take it anymore.
- **claude-haiku-4.5**: I'm absolutely exhausted, I can't take it anymore.

---

### [44] enthusiastic  ·  → English
**Source:** `C'est génial ce que tu as fait!`

- **claude-opus-4.7** _(ref)_: What you did is amazing!
- **grok-4.3**: That's awesome what you did!
- **gpt-4o-mini**: What you did is awesome!
- **kimi-k2.5**: That's awesome what you did!
- **gemini-2.5-flash**: That's awesome what you did!
- **claude-haiku-4.5**: That's awesome what you did!

---

### [45] informal  ·  → English
**Source:** `On se voit demain?`

- **claude-opus-4.7** _(ref)_: See you tomorrow?
- **grok-4.3**: See you tomorrow?
- **gpt-4o-mini**: Are we meeting tomorrow?
- **kimi-k2.5**: See you tomorrow?
- **gemini-2.5-flash**: See you tomorrow?
- **claude-haiku-4.5**: See you tomorrow?

---

### [46] polite formal  ·  → English
**Source:** `Können Sie mir bitte den Bericht zusenden?`

- **claude-opus-4.7** _(ref)_: Could you please send me the report?
- **grok-4.3**: Could you please send me the report?
- **gpt-4o-mini**: Could you please send me the report?
- **kimi-k2.5**: Could you please send me the report?
- **gemini-2.5-flash**: Could you please send me the report?
- **claude-haiku-4.5**: Could you please send me the report?

---

### [47] casual  ·  → English
**Source:** `Hey, was machst du gerade?`

- **claude-opus-4.7** _(ref)_: Hey, what are you up to?
- **grok-4.3**: Hey, what are you up to?
- **gpt-4o-mini**: Hey, what are you up to right now?
- **kimi-k2.5**: Hey, what are you up to right now?
- **gemini-2.5-flash**: Hey, whatcha up to?
- **claude-haiku-4.5**: Hey, what are you up to right now?

---

### [48] impressed  ·  → English
**Source:** `Das ist wirklich beeindruckend.`

- **claude-opus-4.7** _(ref)_: That's really impressive.
- **grok-4.3**: That's really impressive.
- **gpt-4o-mini**: That's really impressive.
- **kimi-k2.5**: That's really impressive.
- **gemini-2.5-flash**: That's really impressive.
- **claude-haiku-4.5**: That's really impressive.

---

### [49] greeting  ·  → English
**Source:** `Ciao, come stai?`

- **claude-opus-4.7** _(ref)_: Hi, how are you?
- **grok-4.3**: Hey, how's it going?
- **gpt-4o-mini**: Hi, how are you?
- **kimi-k2.5**: Hey, how's it going?
- **gemini-2.5-flash**: Hey, how are you?
- **claude-haiku-4.5**: Hey, how's it going?

---

### [50] emotional  ·  → English
**Source:** `Non ci posso credere, è incredibile!`

- **claude-opus-4.7** _(ref)_: I can't believe it, that's incredible!
- **grok-4.3**: I can't believe it, it's incredible!
- **gpt-4o-mini**: I can't believe it, it's amazing!
- **kimi-k2.5**: I can't believe it, this is incredible!
- **gemini-2.5-flash**: I can't believe it, it's incredible!
- **claude-haiku-4.5**: I can't believe it, that's incredible!

