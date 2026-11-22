// Reads one UPI/bank notification the app's built-in rules couldn't settle.
// Every call is logged in alert_log so missed wordings can be added to the rules.
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const MODEL = "claude-haiku-5-5";

const TOOL = {
  name: "record_alert",
  description: "Record what this payment notification means.",
  input_schema: {
    type: "object",
    properties: {
      kind: {
        type: "string",
        enum: ["payment", "atm", "other"],
        description: "payment = money the user paid or sent; atm = cash withdrawn; other = anything else (money received, refund, request, offer, failed or pending payment, balance)",
      },
      amount: { type: ["number", "null"], description: "Amount in rupees" },
      payee: { type: ["string", "null"], description: "Who was paid (shop or person), for payments only" },
    },
    required: ["kind", "amount", "payee"],
    additionalProperties: false,
  },
  strict: true,
};

Deno.serve(async (req) => {
  const auth = req.headers.get("Authorization");
  if (!auth) return new Response("Unauthorized", { status: 401 });
  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: { user } } = await supabase.auth.getUser(auth.replace("Bearer ", ""));
  if (!user) return new Response("Unauthorized", { status: 401 });

  const { app, title, text } = await req.json();
  const body = `${title ?? ""}\n${text ?? ""}`.slice(0, 1000);
  if (!body.trim()) return new Response("Empty alert", { status: 400 });

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": Deno.env.get("ANTHROPIC_API_KEY")!,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 1024,
      tools: [TOOL],
      tool_choice: { type: "auto" },
      messages: [{
        role: "user",
        content: `Call record_alert for this notification from the Indian payments app "${app}". ` +
          `Only an outgoing payment the user made counts as "payment".\n\n<notification>\n${body}\n</notification>`,
      }],
    }),
  });
  if (!res.ok) return new Response(`Reader error ${res.status}`, { status: 502 });
  const out = await res.json();
  const tool = out.content?.find((c: { type: string }) => c.type === "tool_use");
  const r = tool?.input ?? { kind: "other", amount: null, payee: null };

  await supabase.from("alert_log").insert({
    user_id: user.id, app, alert_text: body, kind: r.kind, amount: r.amount, payee: r.payee,
    input_tokens: out.usage?.input_tokens, output_tokens: out.usage?.output_tokens,
  });
  return Response.json(r);
});
