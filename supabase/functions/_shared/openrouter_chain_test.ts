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
