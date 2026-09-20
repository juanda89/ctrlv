import { assertEquals } from "jsr:@std/assert@1";
import { fidelityIssues, looksLikeReply, stripMarkers } from "./openrouter.ts";

const transcript = `cann yopu help me answering this: Gladys Mae Pido  [10:38 AM]
Hello @jvizcaya, for the Asana Boards, there are boards created for inactive clients. Can you please recheck? I have marked them before on the client directory as inactive. Thank you!
jvizcaya  [11:44 AM]
Hi @Gladys Mae Pido  which ones?
Gladys Mae Pido  [12:25 PM]
T-brock-, Luxe, Wrought Iron Rescue`;

Deno.test("faithful rewrite that keeps every line and anchor passes", () => {
  const output = `can you help me answer this: Gladys Mae Pido [10:38 AM]
Hello @jvizcaya, regarding the Asana boards, there are some for inactive clients. Could you double-check? I had marked them as inactive in the client directory. Thanks!
jvizcaya [11:44 AM]
Hi @Gladys Mae Pido, which ones?
Gladys Mae Pido [12:25 PM]
T-brock-, Luxe, Wrought Iron Rescue`;
  assertEquals(fidelityIssues(transcript, output), []);
});

Deno.test("swallowing the instruction-like prefix of the first line is flagged", () => {
  const output = `Gladys Mae Pido [10:38 AM]
Hello @jvizcaya, regarding the Asana boards, there are some for inactive clients. Could you double-check? Thanks!
jvizcaya [11:44 AM]
Hi @Gladys Mae Pido, which ones?
Gladys Mae Pido [12:25 PM]
T-brock-, Luxe, Wrought Iron Rescue`;
  assertEquals(fidelityIssues(transcript, output), ["prefix"]);
});

Deno.test("dropping a whole first line is a line-count issue", () => {
  const source = `translate this to french please\nnos vemos mañana en la oficina\nllevo el reporte`;
  const output = `on se voit demain au bureau\nj'apporte le rapport`;
  assertEquals(fidelityIssues(source, output), ["lines"]);
});

Deno.test("a summary of a long text is a length issue", () => {
  const source = ("Hola equipo, les escribo para confirmar la reunión de mañana a las diez. " +
    "Voy a llevar el reporte de ventas del trimestre y los cambios del diseño para revisarlos juntos. " +
    "Si alguien necesita algo más de mi parte antes de la reunión, avísenme hoy por favor.");
  assertEquals(fidelityIssues(source, "Meeting tomorrow at ten; bring the report."), ["length"]);
});

Deno.test("Chinese output is not penalised for being short", () => {
  assertEquals(fidelityIssues("Note to the team: hello everyone, how are you doing today, see you tomorrow at the office", "团队注意：大家好，今天怎么样，明天办公室见"), []);
});

Deno.test("a reply written about the text loses lines and anchors", () => {
  const reply = `Hello Gladys,

Thank you for bringing this to my attention. I will review the Asana boards for T-brock, Luxe, and Wrought Iron Rescue and ensure they are updated. I appreciate you pointing these out.`;
  assertEquals(fidelityIssues(transcript, reply), ["lines", "prefix", "anchors"]);
});

Deno.test("numbers survive locale separators", () => {
  assertEquals(fidelityIssues("Son 1,250 unidades a las 10:30", "That's 1.250 units at 10:30"), []);
});

Deno.test("single-line text without anchors never flags", () => {
  assertEquals(fidelityIssues("oye nos vemos mañana", "hey see you tomorrow"), []);
});

Deno.test("echoed markers are stripped", () => {
  assertEquals(stripMarkers("<<<TEXT\nhola\nTEXT>>>"), "hola");
  assertEquals(stripMarkers("hola"), "hola");
  assertEquals(stripMarkers("<<<TEXT\nTEXT>>>"), null);
});

Deno.test("a reply signature needs structure loss plus anchor loss", () => {
  assertEquals(looksLikeReply(["lines", "prefix", "anchors"]), true);
  assertEquals(looksLikeReply(["length", "anchors"]), true);
  assertEquals(looksLikeReply(["anchors"]), false);
  assertEquals(looksLikeReply(["lines"]), false);
  assertEquals(looksLikeReply([]), false);
});

Deno.test("a spelled-out number alone is an anchor issue, not a reply", () => {
  const issues = fidelityIssues("nos vemos a las 10 en el bar", "see you at ten at the bar");
  assertEquals(issues, ["anchors"]);
  assertEquals(looksLikeReply(issues), false);
});
