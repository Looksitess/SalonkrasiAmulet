import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-reset-token",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const json = (data: unknown, status = 200) =>
    new Response(JSON.stringify(data), {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  if (req.method !== "POST") {
    return json({ error: "Use POST" }, 405);
  }

  const expectedToken = Deno.env.get("ADMIN_RESET_TOKEN");
  const suppliedToken = req.headers.get("x-reset-token");

  if (!expectedToken || !suppliedToken || suppliedToken !== expectedToken) {
    return json({ error: "Unauthorized" }, 401);
  }

  try {
    const body = await req.json();
    const password = body?.password;

    if (
      typeof password !== "string" ||
      password.length < 12 ||
      password.length > 128
    ) {
      return json({ error: "Password must be 12-128 characters" }, 400);
    }

    const url = Deno.env.get("SUPABASE_URL");
    const secretKeys = Deno.env.get("SUPABASE_SECRET_KEYS");
    const secretKey = secretKeys
      ? JSON.parse(secretKeys)["default"]
      : Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!url || !secretKey) {
      return json({ error: "Server configuration is missing" }, 500);
    }

    const admin = createClient(url, secretKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    });

    const { data, error: listError } =
      await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });

    if (listError) {
      return json({ error: "Could not find the account" }, 500);
    }

    const user = data.users.find(
      (u) => u.email?.toLowerCase() === "admin@amulet.test"
    );

    if (!user) {
      return json({ error: "Admin account not found" }, 404);
    }

    const { error } = await admin.auth.admin.updateUserById(user.id, {
      password,
    });

    if (error) {
      return json({ error: error.message }, 500);
    }

    return json({
      success: true,
      email: "admin@amulet.test",
      message: "Password updated",
    });
  } catch {
    return json({ error: "Unexpected server error" }, 500);
  }
});