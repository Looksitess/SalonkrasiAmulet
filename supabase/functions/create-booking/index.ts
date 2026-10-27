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

  try {
    const body = await req.json();
    const client_name = clean(body.client_name);
    const phone = clean(body.phone);
    const service_name = clean(body.service_name);
    const booking_date = clean(body.booking_date);
    const booking_time = clean(body.booking_time);
    const comment = clean(body.comment);
    const master_id = clean(body.master_id);

    if (!client_name || !phone || !booking_date || !booking_time || !master_id) {
      return json({ ok: false, error: "Вкажіть ім’я, телефон, майстра, дату та час." }, 400);
    }
    if (!/^\d{4}-\d{2}-\d{2}$/.test(booking_date) ||
        !/^([01]\d|2[0-3]):[0-5]\d(:[0-5]\d)?$/.test(booking_time)) {
      return json({ ok: false, error: "Неправильна дата або час." }, 400);
    }

    const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
    const secretKey = secretKeys.default;
    if (!secretKey) throw new Error("Supabase secret key is not configured");

    const supabase = createClient(Deno.env.get("SUPABASE_URL")!, secretKey);
    const { data: salon, error: salonError } = await supabase
      .from("salons").select("id").eq("slug", "amulet").single();
    if (salonError || !salon) throw new Error("Салон Амулет не знайдено");

    const { data: slot, error: slotError } = await supabase
      .from("master_slots")
      .select("id, slot_number, profile_id, salon_id, enabled")
      .eq("id", master_id)
      .eq("salon_id", salon.id)
      .eq("enabled", true)
      .maybeSingle();

    if (slotError) throw slotError;
    if (!slot || !slot.profile_id) {
      return json({ ok: false, error: "Цей майстер зараз недоступний для запису." }, 409);
    }

    const { data: profile, error: profileError } = await supabase
      .from("profiles")
      .select("id, role, active")
      .eq("id", slot.profile_id)
      .eq("salon_id", salon.id)
      .maybeSingle();

    if (profileError) throw profileError;
    if (!profile || profile.role !== "master" || !profile.active) {
      return json({ ok: false, error: "Цей майстер зараз не приймає записи." }, 409);
    }

    const requestedTime = booking_time.slice(0, 5);
    const { data: availability, error: availabilityError } = await supabase.rpc(
      "get_public_available_times",
      { p_booking_date: booking_date, p_master_id: slot.id }
    );
    if (availabilityError) throw availabilityError;

    const matchingTime = (availability ?? []).find((row: { booking_time: string }) =>
      String(row.booking_time).slice(0, 5) === requestedTime
    );
    if (!matchingTime) {
      return json({ ok: false, error: "Майстер не працює у вибраний час." }, 409);
    }
    if (matchingTime.is_booked) {
      return json({ ok: false, error: "Цей час уже заброньовано." }, 409);
    }
    if (matchingTime.is_blocked) {
      return json({ ok: false, error: "Майстер закрив цей час для запису." }, 409);
    }

    const { data: booking, error } = await supabase
      .from("bookings")
      .insert({
        salon_id: salon.id,
        master_id: slot.id,
        client_name,
        phone,
        service_name: service_name || null,
        booking_date,
        booking_time: requestedTime,
        comment: comment || null,
        status: "new",
      })
      .select("id")
      .single();

    if (error?.code === "23505") {
      return json({ ok: false, error: "Цей час щойно зайняли. Оберіть інший." }, 409);
    }
    if (error) throw error;

    return json({ ok: true, booking_id: booking.id, message: "Запис успішно створено" });
  } catch (error) {
    console.error(error);
    return json({ ok: false, error: "Не вдалося створити запис. Перевірте дані й спробуйте ще раз." }, 500);
  }
});

function clean(value: unknown): string {
  return String(value ?? "").trim().slice(0, 1000);
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: cors });
}
