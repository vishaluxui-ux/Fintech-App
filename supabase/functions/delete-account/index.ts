// ACC-03: delete the signed-in user and all their rows (FKs cascade from auth.users).
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

Deno.serve(async (req) => {
  const auth = req.headers.get("Authorization");
  if (!auth) return new Response("Unauthorized", { status: 401 });
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: { user } } = await admin.auth.getUser(auth.replace("Bearer ", ""));
  if (!user) return new Response("Unauthorized", { status: 401 });

  for (const t of ["items", "captures", "withdrawals", "parse_log", "alert_log"]) {
    const { error } = await admin.from(t).delete().eq("user_id", user.id);
    if (error) return new Response(error.message, { status: 500 });
  }
  const { error } = await admin.auth.admin.deleteUser(user.id);
  if (error) return new Response(error.message, { status: 500 });
  return Response.json({ deleted: true });
});
