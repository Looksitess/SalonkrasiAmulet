import { bookingRateLimitKey, validateBookingPayload } from "./validation.ts";

const now = new Date("2026-11-01T08:00:00.000Z"); // 10:00 in Europe/Kyiv
const validPayload = {
  salon_slug: "amulet",
  client_name: "Олена",
  phone: "+380 67 123 45 67",
  service_name: "Манікюр / педикюр",
  booking_date: "2026-11-02",
  booking_time: "11:00",
  master_id: "00000000-0000-4000-8000-000000000001",
  comment: "",
};

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("accepts a valid future booking payload", () => {
  const result = validateBookingPayload(validPayload, now);
  assert(result.ok, "Expected valid payload to pass");
  assert(result.data.booking_time === "11:00", "Expected normalized booking time");
});

Deno.test("rejects an impossible calendar date", () => {
  const result = validateBookingPayload({ ...validPayload, booking_date: "2026-02-30" }, now);
  assert(!result.ok && result.status === 400, "Expected invalid calendar date to fail");
});

Deno.test("rejects a booking date in the past", () => {
  const result = validateBookingPayload({ ...validPayload, booking_date: "2026-10-31" }, now);
  assert(!result.ok && result.status === 409, "Expected past date to fail");
});

Deno.test("rejects an elapsed time on the current salon-local date", () => {
  const result = validateBookingPayload(
    { ...validPayload, booking_date: "2026-11-01", booking_time: "09:00" },
    now,
  );
  assert(!result.ok && result.status === 409, "Expected elapsed time to fail");
});

Deno.test("rejects malformed phone numbers", () => {
  const result = validateBookingPayload({ ...validPayload, phone: "call me" }, now);
  assert(!result.ok && result.status === 400, "Expected invalid phone to fail");
});

Deno.test("rejects non-UUID master identifiers", () => {
  const result = validateBookingPayload({ ...validPayload, master_id: "master-1" }, now);
  assert(!result.ok && result.status === 400, "Expected invalid master id to fail");
});

Deno.test("rejects malformed request bodies", () => {
  const result = validateBookingPayload([], now);
  assert(!result.ok && result.status === 400, "Expected array payload to fail");
});

Deno.test("rejects a too-long client name instead of silently truncating it", () => {
  const result = validateBookingPayload({ ...validPayload, client_name: "A".repeat(81) }, now);
  assert(!result.ok && result.status === 400, "Expected overlong name to fail");
});

Deno.test("rejects a too-long comment instead of silently truncating it", () => {
  const result = validateBookingPayload({ ...validPayload, comment: "x".repeat(501) }, now);
  assert(!result.ok && result.status === 400, "Expected overlong comment to fail");
});

Deno.test("rejects a malformed salon slug", () => {
  const result = validateBookingPayload({ ...validPayload, salon_slug: "../other-salon" }, now);
  assert(!result.ok && result.status === 400, "Expected invalid salon slug to fail");
});

Deno.test("generates a stable HMAC rate-limit key without exposing a phone number", async () => {
  const first = await bookingRateLimitKey("amulet", "+380 67 123 45 67", "server-only-test-secret");
  const second = await bookingRateLimitKey("amulet", "380671234567", "server-only-test-secret");
  const otherPhone = await bookingRateLimitKey("amulet", "380671234568", "server-only-test-secret");
  const otherSalon = await bookingRateLimitKey("other-salon", "380671234567", "server-only-test-secret");

  assert(first === second, "Expected equivalent phone formats to share a key");
  assert(first !== otherPhone, "Expected different phone numbers to have different keys");
  assert(first !== otherSalon, "Expected keys to be isolated by salon");
  assert(/^[0-9a-f]{64}$/.test(first), "Expected a 64-character SHA-256 HMAC hex digest");
});
