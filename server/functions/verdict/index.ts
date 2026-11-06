// Supabase Edge Function "verdict": one short line of flavour text for the failure screen.
// The Gemini key is read from the GEMINI_API_KEY secret (set in the Supabase dashboard); it is never sent to the game.
// The game sends only a mode, a level number and an end reason - no free text - so there is nothing to inject into the prompt.
const MODES = ["endless", "ruthless"];
const REASONS = ["failure", "invalidated", "completed"];
const MODEL = "gemini-2.5-flash-lite";
const PER_USER_PER_HOUR = 20;
const GLOBAL_PER_DAY = 3000;

const perUser = new Map<string, number[]>();
let dayKey = "";
let dayCount = 0;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } });
}

function userOf(req: Request): string {
  const token = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
  try {
    return JSON.parse(atob(token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/"))).sub ?? "";
  } catch {
    return "";
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, apikey, content-type" } });
  const user = userOf(req); // the platform has already verified the JWT signature
  if (user === "") return json({ ok: false, error: "not_logged_in" }, 401);
  let input: { mode?: string; level?: number; reason?: string };
  try { input = await req.json(); } catch { return json({ ok: false, error: "bad_request" }, 400); }
  const level = Math.trunc(Number(input.level));
  if (!MODES.includes(String(input.mode)) || !REASONS.includes(String(input.reason)) || !(level >= 1 && level <= 9999)) return json({ ok: false, error: "bad_request" }, 400);

  const now = Date.now();
  const recent = (perUser.get(user) ?? []).filter((t) => now - t < 3600_000);
  if (recent.length >= PER_USER_PER_HOUR) return json({ ok: false, error: "rate_limited" }, 429);
  const today = new Date().toISOString().slice(0, 10);
  if (today !== dayKey) { dayKey = today; dayCount = 0; }
  if (dayCount >= GLOBAL_PER_DAY) return json({ ok: false, error: "budget_reached" }, 429);
  recent.push(now); perUser.set(user, recent); dayCount++;

  const key = Deno.env.get("GEMINI_API_KEY");
  if (!key) return json({ ok: false, error: "not_configured" }, 503);
  const prompt =
    `You write one line (max 14 words, no quotes, no emoji) for a dark-fantasy game where the player pulls a sword from a stump in a forest. ` +
    `Mode: ${input.mode}. Swords drawn: ${level}. Ending: ${input.reason} ` +
    `(failure = the sword held fast; invalidated = the player left the forest; completed = all 9999 swords drawn). ` +
    `Be solemn, poetic, a little wry. Output only the line.`;
  try {
    const r = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": key },
      body: JSON.stringify({ contents: [{ parts: [{ text: prompt }] }], generationConfig: { maxOutputTokens: 60, temperature: 0.9 } }),
      signal: AbortSignal.timeout(6000),
    });
    if (!r.ok) return json({ ok: false, error: "upstream" }, 502);
    const data = await r.json();
    let text = String(data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "").replace(/["\n\r*]/g, " ").trim();
    if (text === "" || text.length > 140) return json({ ok: false, error: "empty" }, 502);
    return json({ ok: true, text });
  } catch {
    return json({ ok: false, error: "upstream" }, 502);
  }
});
