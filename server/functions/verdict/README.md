# verdict (Gemini flavour text)
The game calls `POST /functions/v1/verdict` with `{mode, level, reason}`; this function holds the Gemini key.

You do (in the Supabase dashboard, never in the game or in chat):
1. Edge Functions -> Deploy a new function -> name `verdict` -> paste `index.ts` (JWT verification stays ON).
2. Edge Functions -> Secrets -> add `GEMINI_API_KEY` = your key.
Limits: 20 calls/user/hour, 3000/day in total (best-effort per instance). Without the function or secret the game shows its built-in lines.
