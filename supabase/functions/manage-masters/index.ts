import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, error: "Method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization") ?? "";
  const accessToken = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!accessToken) return json({ ok: false, error: "Войдите как администратор." }, 401);

  try {
    const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
    const secretKey = secretKeys.default;
    const url = Deno.env.get("SUPABASE_URL");
    if (!secretKey || !url) throw new Error("Supabase server configuration is missing");

    const adminClient = createClient(url, secretKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: authData, error: authError } = await adminClient.auth.getUser(accessToken);
    const actor = authData?.user;
    if (authError || !actor) return json({ ok: false, error: "Сесія недійсна. Увійдіть повторно." }, 401);

    const { data: actorProfile, error: actorProfileError } = await adminClient
      .from("profiles")
      .select("id, role, is_admin, active, salon_id")
      .eq("id", actor.id)
      .maybeSingle();
    if (actorProfileError) throw actorProfileError;
    if (!actorProfile?.active || !(actorProfile.is_admin || actorProfile.role === "admin")) {
      return json({ ok: false, error: "Недостатньо прав адміністратора." }, 403);
    }

    const body = await req.json();
    const action = String(body.action ?? "");
    if (action !== "create_master") {
      return json({ ok: false, error: "Невідома дія." }, 400);
    }

    const slotId = clean(body.slot_id);
    const email = clean(body.email).toLowerCase();
    const password = String(body.password ?? "");
    const fullName = clean(body.full_name);
    const phone = clean(body.phone);
    const specialty = clean(body.specialty);

    if (!slotId || !email || !password || !fullName) {
      return json({ ok: false, error: "Вкажіть ім’я, email і тимчасовий пароль." }, 400);
    }
    if (password.length < 8) {
      return json({ ok: false, error: "Пароль має містити щонайменше 8 символів." }, 400);
    }
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      return json({ ok: false, error: "Перевірте правильність email." }, 400);
    }

    const { data: slot, error: slotError } = await adminClient
      .from("master_slots")
      .select("id, slot_number, salon_id, profile_id, enabled, display_name, phone, specialty")
      .eq("id", slotId)
      .eq("salon_id", actorProfile.salon_id)
      .maybeSingle();

    if (slotError) throw slotError;
    if (!slot) return json({ ok: false, error: "Місце майстра не знайдено." }, 404);
    if (slot.profile_id) return json({ ok: false, error: "До цього місця вже прив’язаний акаунт." }, 409);

    const { data: userData, error: createUserError } = await adminClient.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { full_name: fullName },
    });
    if (createUserError || !userData.user) {
      return json({ ok: false, error: createUserError?.message ?? "Не вдалося створити акаунт." }, 400);
    }

    const newUserId = userData.user.id;
    try {
      const { error: profileError } = await adminClient.from("profiles").insert({
        id: newUserId,
        full_name: fullName,
        role: "master",
        phone: phone || null,
        specialty: specialty || null,
        active: Boolean(slot.enabled),
        is_admin: false,
        salon_id: slot.salon_id,
        master_slot_id: slot.id,
      });
      if (profileError) throw profileError;

      const { error: slotUpdateError } = await adminClient
        .from("master_slots")
        .update({
          profile_id: newUserId,
          display_name: fullName,
          phone: phone || null,
          specialty: specialty || null,
          updated_at: new Date().toISOString(),
        })
        .eq("id", slot.id);
      if (slotUpdateError) throw slotUpdateError;
    } catch (e) {
      await adminClient.from("profiles").delete().eq("id", newUserId);
      await adminClient.auth.admin.deleteUser(newUserId);
      throw e;
    }

    return json({
      ok: true,
      slot_number: slot.slot_number,
      message: `Майстра додано до місця №${slot.slot_number}. Передайте майстру email і пароль окремо.`,
    });
  } catch (error) {
    console.error(error);
    return json({ ok: false, error: "Не вдалося створити акаунт майстра." }, 500);
  }
});

function clean(value: unknown): string {
  return String(value ?? "").trim().slice(0, 1000);
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: cors });
}
