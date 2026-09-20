import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { translateWithOpenRouter } from "./openrouter.ts";

// The model chain is exercised with a stubbed fetch: no network, no key.
function withFetch(stub: typeof fetch, run: () => Promise<void>): Promise<void> {
  const original = globalThis.fetch;
  globalThis.fetch = stub;
  Deno.env.set("OPENROUTER_API_KEY", "test-key");
  Deno.env.set("OPENROUTER_MODELS", "model-a,model-b");
  return run().finally(() => {
    globalThis.fetch = original;
  });
}

function completion(text: string): Response {
  return new Response(JSON.stringify({ choices: [{ message: { content: text } }] }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.test("an aborted speculative call is not retried on the next model", async () => {
  const calls: string[] = [];
  const controller = new AbortController();
  controller.abort();
  await withFetch(((_url: RequestInfo | URL, init?: RequestInit) => {
    calls.push(JSON.parse(String(init?.body)).model);
    if (init?.signal?.aborted) {
      return Promise.reject(new DOMException("The signal has been aborted", "AbortError"));
    }
    return Promise.resolve(completion("hola"));
  }) as typeof fetch, async () => {
    await assertRejects(
      () => translateWithOpenRouter("hello", "Translate.", { signal: controller.signal }),
      DOMException,
    );
  });
  assertEquals(calls, ["model-a"]);
});

Deno.test("a model failure still falls through to the next model", async () => {
  const calls: string[] = [];
  await withFetch(((_url: RequestInfo | URL, init?: RequestInit) => {
    const model = JSON.parse(String(init?.body)).model;
    calls.push(model);
    if (model === "model-a") return Promise.reject(new Error("boom"));
    return Promise.resolve(completion("hola"));
  }) as typeof fetch, async () => {
    const result = await translateWithOpenRouter("hello", "Translate.");
    assertEquals(result.translatedText, "hola");
    assertEquals(result.model, "model-b");
    assertEquals(result.fallbackUsed, true);
  });
  assertEquals(calls, ["model-a", "model-b"]);
});

Deno.test("the user turn is delimited and the markers are stripped from the answer", async () => {
  let userTurn = "";
  await withFetch(((_url: RequestInfo | URL, init?: RequestInit) => {
    const body = JSON.parse(String(init?.body));
    userTurn = body.messages[1].content;
    return Promise.resolve(completion("<<<TEXT\nhola\nTEXT>>>"));
  }) as typeof fetch, async () => {
    const result = await translateWithOpenRouter("hello", "Translate.");
    assertEquals(result.translatedText, "hola");
  });
  assertEquals(userTurn, "<<<TEXT\nhello\nTEXT>>>");
});

// Hedge behaviour. The stub rejects on abort like a real fetch would.
function stubFetch(handler: (model: string, signal: AbortSignal | null | undefined, n: number) => Promise<Response>): { fetch: typeof fetch; calls: number[] } {
  const state = { calls: [] as number[] };
  let n = 0;
  const impl = ((_url: RequestInfo | URL, init?: RequestInit) => {
    n += 1;
    state.calls.push(n);
    const model = JSON.parse(String(init?.body)).model;
    return handler(model, init?.signal, n);
  }) as typeof fetch;
  return { fetch: impl, calls: state.calls };
}
const hang = (signal: AbortSignal | null | undefined) =>
  new Promise<Response>((_, reject) => signal?.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError"))));

Deno.test("hedge: a stalled first request is beaten by the second one", async () => {
  const stub = stubFetch((_model, signal, n) => n === 1 ? hang(signal) : Promise.resolve(completion("hola")));
  await withFetch(stub.fetch, async () => {
    const result = await translateWithOpenRouter("hello", "Translate.", { hedgeAfterMs: 20 });
    assertEquals(result.translatedText, "hola");
    assertEquals(result.model, "model-a");
  });
  assertEquals(stub.calls.length, 2);
});

Deno.test("hedge: a fast failure does not wait for a hedge", async () => {
  const started = performance.now();
  const stub = stubFetch((model, _signal, n) => {
    if (model === "model-a" && n === 1) return Promise.reject(new Error("boom"));
    return Promise.resolve(completion("hola"));
  });
  await withFetch(stub.fetch, async () => {
    const result = await translateWithOpenRouter("hello", "Translate.", { hedgeAfterMs: 500 });
    assertEquals(result.model, "model-b");
  });
  assertEquals(stub.calls.length, 2); // model-a once, model-b once, no hedge
  assertEquals(performance.now() - started < 400, true);
});

Deno.test("hedge: a fast success never starts a second request", async () => {
  const stub = stubFetch(() => Promise.resolve(completion("hola")));
  await withFetch(stub.fetch, async () => {
    await translateWithOpenRouter("hello", "Translate.", { hedgeAfterMs: 20 });
    await new Promise((r) => setTimeout(r, 60));
  });
  assertEquals(stub.calls.length, 1);
});

Deno.test("hedge: caller abort cancels both requests and no fallback runs", async () => {
  const controller = new AbortController();
  const stub = stubFetch((_model, signal) => hang(signal));
  await withFetch(stub.fetch, async () => {
    const pending = translateWithOpenRouter("hello", "Translate.", { hedgeAfterMs: 20, signal: controller.signal });
    setTimeout(() => controller.abort(), 50);
    await assertRejects(() => pending, DOMException);
  });
  assertEquals(stub.calls.length, 2); // first + hedge, both on model-a; model-b never tried
});
