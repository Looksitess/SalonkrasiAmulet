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

    const rawBody = await req.text();
    if (rawBody.length > 4096) {
      return json({ ok: false, error: "Занадто великий запит." }, 413);
    }

    let body: Record<string, unknown>;
    try {
      const parsed = JSON.parse(rawBody);
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
        return json({ ok: false, error: "Некоректні дані запиту." }, 400);
      }
      body = parsed as Record<string, unknown>;
    } catch {
      return json({ ok: false, error: "Некоректний формат запиту." }, 400);
    }

    const action = clean(body.action, 40);
    if (action !== "create_master" && action !== "remove_master") {
      return json({ ok: false, error: "Невідома дія." }, 400);
    }

    const slotId = clean(body.slot_id, 64);
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(slotId)) {
      return json({ ok: false, error: "Некоректний ідентифікатор місця майстра." }, 400);
    }
    const email = clean(body.email, 254).toLowerCase();
    const password = typeof body.password === "string" ? body.password : "";
    const fullName = clean(body.full_name, 80);
    const phone = clean(body.phone, 25);
    const specialty = clean(body.specialty, 120);

    if (!slotId) {
      return json({ ok: false, error: "Не вказано місце майстра." }, 400);
    }

    const { data: slot, error: slotError } = await adminClient
      .from("master_slots")
      .select("id, slot_number, salon_id, profile_id, enabled, display_name, phone, specialty")
      .eq("id", slotId)
      .eq("salon_id", actorProfile.salon_id)
      .maybeSingle();

    if (slotError) throw slotError;
    if (!slot) return json({ ok: false, error: "Місце майстра не знайдено." }, 404);

    if (action === "remove_master") {
      const { data: profiles, error: profilesError } = await adminClient
        .from("profiles").select("id, role, is_admin, master_slot_id")
        .eq("master_slot_id", slot.id);
      if (profilesError) throw profilesError;
      const masterProfile = (profiles || []).find((p) => p.role === "master" && !p.is_admin);
      if (!masterProfile) return json({ ok: false, error: "У цьому місці немає звичайного акаунта майстра." }, 404);

      const today = new Date().toISOString().slice(0, 10);
      const { data: futureBookings, error: bookingsError } = await adminClient
        .from("bookings").select("id").eq("master_id", slot.id)
        .gte("booking_date", today).in("status", ["new", "confirmed"]).limit(1);
      if (bookingsError) throw bookingsError;
      if (futureBookings && futureBookings.length) {
        return json({ ok: false, error: "У майстра є майбутні активні записи. Спочатку перенесіть або скасуйте їх, потім видаліть майстра." }, 409);
      }

      const { error: scheduleError } = await adminClient.from("work_schedule").delete().eq("master_id", slot.id);
      if (scheduleError) throw scheduleError;
      const { error: blocksError } = await adminClient.from("blocked_slots").delete().eq("master_id", slot.id);
      if (blocksError) throw blocksError;
      const { error: resetError } = await adminClient.from("master_slots").update({
        profile_id: null, enabled: false, display_name: "Вільне місце " + slot.slot_number,
        phone: null, specialty: null, updated_at: new Date().toISOString()
      }).eq("id", slot.id);
      if (resetError) throw resetError;
      const { error: profileError } = await adminClient.from("profiles").delete().eq("id", masterProfile.id);
      if (profileError) throw profileError;
      const { error: userError } = await adminClient.auth.admin.deleteUser(masterProfile.id);
      if (userError) throw userError;

      return json({ ok: true, slot_number: slot.slot_number,
        message: "Майстра видалено. Місце №" + slot.slot_number + " очищено та вимкнено. Увімкніть його в адмінці, щоб додати нового майстра." });
    }

    if (!slot.enabled) {
      return json({ ok: false, error: "Спочатку увімкніть це місце для запису." }, 409);
    }
    if (!email || !password || !fullName) {
      return json({ ok: false, error: "Вкажіть ім’я, email і тимчасовий пароль." }, 400);
    }
    if (password.length < 12 || password.length > 128) {
      return json({ ok: false, error: "Пароль має містити від 12 до 128 символів." }, 400);
    }
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      return json({ ok: false, error: "Перевірте правильність email." }, 400);
    }
    if (fullName.length < 2 || fullName.length > 80 || phone.length > 25 || specialty.length > 120) {
      return json({ ok: false, error: "Перевірте довжину імені, телефону та спеціалізації." }, 400);
    }
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

      const { data: claimedSlot, error: slotUpdateError } = await adminClient
        .from("master_slots")
        .update({
          profile_id: newUserId,
          display_name: fullName,
          phone: phone || null,
          specialty: specialty || null,
          updated_at: new Date().toISOString(),
        })
        .eq("id", slot.id)
        .eq("salon_id", actorProfile.salon_id)
        .is("profile_id", null)
        .select("id")
        .maybeSingle();
      if (slotUpdateError) throw slotUpdateError;
      if (!claimedSlot) throw new Error("This master slot was already assigned by another request.");
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

function clean(value: unknown, maxLength = 1000): string {
  if (typeof value !== "string") return "";
  const cleaned = value.trim();
  return cleaned.length <= maxLength ? cleaned : "";
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: cors });
}
