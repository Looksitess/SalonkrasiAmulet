// Deprecated legacy endpoint.
// The old implementation changed the hard-coded admin@amulet.test account
// using a shared x-reset-token secret. No frontend calls this endpoint.
// Keep a safe 410 response so old integrations cannot change account passwords.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

Deno.serve((req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  return new Response(
    JSON.stringify({
      error: "This legacy password reset endpoint is disabled. Use the supported Supabase Auth recovery flow.",
    }),
    {
      status: 410,
      headers: { ...corsHeaders, "Cache-Control": "no-store" },
    },
  );
});
