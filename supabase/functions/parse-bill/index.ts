// CAP-02: read a bill photo with Claude Haiku and return structured lines.
// Secrets: ANTHROPIC_API_KEY (set with `supabase secrets set`).
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const MODEL = "claude-haiku-5-5";

const TOOL = {
  name: "record_bill",
  description: "Record every purchased line on the bill.",
  input_schema: {
    type: "object",
    properties: {
      merchant: { type: ["string", "null"], description: "Shop or restaurant name" },
      total: { type: ["number", "null"], description: "Final amount payable printed on the bill, after tax and discounts" },
      items: {
        type: "array",
        items: {
          type: "object",
          properties: {
            name: { type: "string" },
            amount: { type: "number", description: "Line total in rupees (qty x price)" },
            category: { type: "string" },
            confidence: { type: "number", description: "0 to 1: how sure you are of the name and amount" },
          },
          required: ["name", "amount", "category", "confidence"],
        },
      },
    },
    required: ["merchant", "total", "items"],
  },
};

Deno.serve(async (req) => {
  const auth = req.headers.get("Authorization");
  if (!auth) return new Response("Unauthorized", { status: 401 });
  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: { user } } = await supabase.auth.getUser(auth.replace("Bearer ", ""));
  if (!user) return new Response("Unauthorized", { status: 401 });

  const { image, media_type, categories } = await req.json();
  if (!image || typeof image !== "string" || image.length > 7_000_000) {
    return new Response("Bad image", { status: 400 });
  }

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": Deno.env.get("ANTHROPIC_API_KEY")!,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 2048,
      tools: [TOOL],
      tool_choice: { type: "tool", name: "record_bill" },
      messages: [{
        role: "user",
        content: [
          { type: "image", source: { type: "base64", media_type: media_type ?? "image/jpeg", data: image } },
          {
            type: "text",
            text: `This is an Indian shop bill, receipt or payment screenshot. List each purchased line with its line total in rupees. ` +
              `Treat taxes (GST, CGST, SGST), service charge, delivery or packing fees as their own lines; never output negative amounts: ` +
              `subtract an item discount from its line; leave out a bill-wide discount but still report the printed final total. ` +
              `Pick each category from: ${(categories ?? []).join(", ")}. Use "other" if none fit. ` +
              `Lower the confidence for faded, handwritten or cut-off lines. If this is not a bill, return an empty items list.`,
          },
        ],
      }],
    }),
  });

  if (!res.ok) return new Response(`Parser error ${res.status}`, { status: 502 });
  const body = await res.json();
  const tool = body.content?.find((c: { type: string }) => c.type === "tool_use");
  const out = tool?.input ?? { merchant: null, total: null, items: [] };
  out.items = (out.items ?? []).filter((i: { amount: number }) => typeof i.amount === "number" && i.amount > 0);

  await supabase.from("parse_log").insert({
    user_id: user.id, model: MODEL,
    input_tokens: body.usage?.input_tokens, output_tokens: body.usage?.output_tokens,
    line_count: out.items.length,
  });

  return Response.json(out);
});
