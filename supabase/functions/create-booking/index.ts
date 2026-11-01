import { createClient } from "npm:@supabase/supabase-js@2";
import { bookingRateLimitKey, validateBookingPayload } from "./validation.ts";

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
    const rawBody = await req.text();
    if (rawBody.length > 4096) {
      return json({ ok: false, error: "Заявка завелика." }, 413);
    }

    let body: unknown;
    try {
      body = JSON.parse(rawBody);
    } catch {
      return json({ ok: false, error: "Некоректний формат заявки." }, 400);
    }

    const validation = validateBookingPayload(body);
    if (!validation.ok) {
      return json({ ok: false, error: validation.error }, validation.status);
    }

    const {
      salon_slug,
      client_name,
      phone,
      service_name,
      booking_date,
      booking_time,
      comment,
      master_id,
    } = validation.data;

    const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
    const secretKey = secretKeys.default;
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    if (!secretKey || !supabaseUrl) {
      throw new Error("Supabase server configuration is missing");
    }

    const supabase = createClient(supabaseUrl, secretKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: salon, error: salonError } = await supabase
      .from("salons")
      .select("id")
      .eq("slug", salon_slug)
      .single();

    if (salonError || !salon) throw new Error("Configured salon was not found");

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

    const { data: configuredServices, error: servicesError } = await supabase
      .from("services")
      .select("id, name")
      .eq("salon_id", salon.id)
      .eq("active", true);
    if (servicesError) throw servicesError;

    if (!Array.isArray(configuredServices) || configuredServices.length === 0) {
      return json({ ok: false, error: "Салон ще не налаштував послуги для онлайн-запису." }, 409);
    }

    const selectedService = configuredServices.find((service: { id: string; name: string }) =>
      service.name === service_name
    ) ?? null;
    if (!selectedService) {
      return json({ ok: false, error: "Оберіть послугу з актуального каталогу салону." }, 400);
    }

    const rateLimitKey = await bookingRateLimitKey(salon_slug, phone, secretKey);
    const { data: rateAllowed, error: rateLimitError } = await supabase.rpc(
      "consume_booking_rate_limit",
      {
        p_key_hash: rateLimitKey,
        p_limit: 5,
        p_window_seconds: 600,
      },
    );

    if (rateLimitError) throw rateLimitError;
    if (rateAllowed !== true) {
      return json(
        { ok: false, error: "Забагато заявок із цього номера. Спробуйте трохи пізніше." },
        429,
        { "Retry-After": "600" },
      );
    }

    const { data: availability, error: availabilityError } = await supabase.rpc(
      "get_public_available_times",
      { p_booking_date: booking_date, p_master_id: slot.id, p_salon_slug: salon_slug },
    );

    if (availabilityError) throw availabilityError;

    const matchingTime = (availability ?? []).find(
      (row: { booking_time: string }) => String(row.booking_time).slice(0, 5) === booking_time,
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
        service_id: selectedService?.id ?? null,
        service_name,
        booking_date,
        booking_time,
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
    console.error("Booking function failed:", error instanceof Error ? error.message : "Unknown error");
    return json({
      ok: false,
      error: "Не вдалося створити запис. Перевірте дані й спробуйте ще раз.",
    }, 500);
  }
});

function json(
  data: unknown,
  status = 200,
  extraHeaders: Record<string, string> = {},
) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...cors, ...extraHeaders },
  });
}
