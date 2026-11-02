export type BookingRequest = {
  salon_slug: string;
  client_name: string;
  phone: string;
  service_name: string;
  service_id: string;
  booking_date: string;
  booking_time: string;
  master_id: string;
  comment: string;
};

export type BookingValidation =
  | { ok: true; data: BookingRequest }
  | { ok: false; status: number; error: string };

function textField(input: Record<string, unknown>, key: string): string {
  const value = input[key];
  return typeof value === "string" ? value.trim() : "";
}

function kyivDateAndTime(now: Date): { date: string; time: string } {
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: "Europe/Kyiv",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(now);

  const values = Object.fromEntries(
    parts.filter((part) => part.type !== "literal").map((part) => [part.type, part.value] as const),
  );

  return {
    date: `${values.year}-${values.month}-${values.day}`,
    time: `${values.hour}:${values.minute}`,
  };
}

export function validateBookingPayload(value: unknown, now: Date = new Date()): BookingValidation {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return { ok: false, status: 400, error: "Некоректні дані заявки." };
  }

  const input = value as Record<string, unknown>;
  if (input.comment != null && typeof input.comment !== "string") {
    return { ok: false, status: 400, error: "Перевірте поле коментаря." };
  }

  const data: BookingRequest = {
    salon_slug: textField(input, "salon_slug"),
    client_name: textField(input, "client_name"),
    phone: textField(input, "phone"),
    service_name: textField(input, "service_name"),
    service_id: textField(input, "service_id"),
    booking_date: textField(input, "booking_date"),
    booking_time: textField(input, "booking_time"),
    master_id: textField(input, "master_id"),
    comment: textField(input, "comment"),
  };

  if (data.comment.length > 500) {
    return { ok: false, status: 400, error: "Коментар має бути не довшим за 500 символів." };
  }

  if (
    data.salon_slug.length < 2 ||
    data.salon_slug.length > 80 ||
    !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(data.salon_slug)
  ) {
    return { ok: false, status: 400, error: "Невідомий сайт салону." };
  }

  if (
    data.client_name.length < 2 ||
    data.client_name.length > 80 ||
    data.service_name.length < 2 ||
    data.service_name.length > 120
  ) {
    return { ok: false, status: 400, error: "Вкажіть ім’я та послугу. Перевірте довжину полів." };
  }

  const phoneDigits = data.phone.replace(/\D/g, "");
  if (
    data.phone.length < 7 ||
    data.phone.length > 25 ||
    !/^[0-9+().\s-]+$/.test(data.phone) ||
    phoneDigits.length < 7 ||
    phoneDigits.length > 15
  ) {
    return { ok: false, status: 400, error: "Вкажіть коректний номер телефону." };
  }

  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(data.service_id)) {
    return { ok: false, status: 400, error: "Оберіть послугу зі списку." };
  }

  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(data.master_id)) {
    return { ok: false, status: 400, error: "Оберіть майстра зі списку." };
  }

  if (!/^\d{4}-\d{2}-\d{2}$/.test(data.booking_date)) {
    return { ok: false, status: 400, error: "Неправильна дата запису." };
  }

  const parsedDate = new Date(`${data.booking_date}T00:00:00.000Z`);
  if (
    Number.isNaN(parsedDate.getTime()) ||
    parsedDate.toISOString().slice(0, 10) !== data.booking_date
  ) {
    return { ok: false, status: 400, error: "Такої календарної дати не існує." };
  }

  if (!/^(?:[01]\d|2[0-3]):(?:00|15|30|45)(?::00)?$/.test(data.booking_time)) {
    return { ok: false, status: 400, error: "Оберіть час із доступного списку." };
  }

  const requestedTime = data.booking_time.slice(0, 5);
  const localNow = kyivDateAndTime(now);

  const maxDate = new Date(`${localNow.date}T00:00:00.000Z`);
  maxDate.setUTCDate(maxDate.getUTCDate() + 365);
  if (data.booking_date > maxDate.toISOString().slice(0, 10)) {
    return { ok: false, status: 400, error: "Запис доступний не далі ніж на рік уперед." };
  }

  if (
    data.booking_date < localNow.date ||
    (data.booking_date === localNow.date && requestedTime <= localNow.time)
  ) {
    return { ok: false, status: 409, error: "Оберіть майбутню дату та час." };
  }

  return { ok: true, data: { ...data, booking_time: requestedTime } };
}

export async function bookingRateLimitKey(
  salonSlug: string,
  phone: string,
  serverSecret: string,
): Promise<string> {
  if (!serverSecret) throw new Error("Rate limit secret is missing");

  const phoneDigits = phone.replace(/\D/g, "");
  if (!phoneDigits) throw new Error("Phone number is invalid");

  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(serverSecret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode("booking-rate-limit:" + salonSlug + ":" + phoneDigits),
  );

  return Array.from(new Uint8Array(signature))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}
