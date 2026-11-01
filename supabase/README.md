# Supabase backend — Amulet Salon SaaS

## Current production snapshot (2 Nov 2026)

- Supabase project: `hqbjlvryecmqemmajqyo`
- PostgreSQL 17, one configured salon with slug `amulet`.
- 20 master slots, one enabled but currently unassigned slot, no active public masters.
- 133 work-schedule rows preserved after detaching the administrator profile from the master slot.
- 14 services imported from the currently published Amulet price list. Original labels such as `від 350 грн` are preserved in `services.price_label`.
- No production bookings, reviews, or review comments were present at the last check.
- The public booking flow is active, but a real end-to-end booking cannot succeed until a real master account is assigned and has an enabled schedule.

These are live facts from the last audit, not example data. Do not create dummy customers, masters, reviews, or passwords.

## Edge Functions

- `functions/create-booking/index.ts` — ACTIVE version 15. Public endpoint. Validates payloads and salon slug, verifies the selected master and service belong to that salon, checks availability, creates a booking, and applies a per-salon/per-phone HMAC rate limit of 5 validated attempts per 10 minutes.
- `functions/manage-masters/index.ts` — ACTIVE version 9. Verifies the caller's JWT and active salon-admin profile, scopes every slot operation to that profile's salon, creates and removes master Auth accounts, prevents duplicate concurrent slot claims, and protects future bookings before removal.
- `functions/admin-password-reset/index.ts` — legacy endpoint intentionally disabled with HTTP 410. Do not re-enable the old shared-secret reset flow. Use the supported Supabase Auth recovery process if password recovery is needed.

The Supabase service-role/secret key must remain in Edge Function secrets. It must never appear in browser JavaScript, Android source, or GitHub.

## Tenant model

- `salons` owns each tenant.
- `profiles.salon_id` identifies the tenant for staff/admin profiles.
- `master_slots.salon_id` scopes each slot. Slot numbering is unique within a salon using `(salon_id, slot_number)`.
- `bookings.salon_id` is NOT NULL and has a foreign key to `salons`; composite foreign keys require `master_id` and `service_id` to belong to the same salon as the booking. Deleting a master/service clears only the corresponding nullable reference and preserves the booking.
- `services.salon_id` and `customer_reviews.salon_id` scope catalogue and reviews.
- `review_comments` inherits tenant scope through its parent review.
- Review-related `content_reports` inherit salon_id from the linked review; forum reports remain global because the forum is a shared platform community.
- Public pages resolve data by a public salon slug through narrow RPCs: `get_public_masters`, `get_public_services`, `get_public_available_times`, `get_public_approved_reviews`, and `get_public_review_comments`.
- Public clients do not have direct SELECT on `public_masters`, `services`, `customer_reviews`, or `review_comments`.

## Booking rate limit

The booking limiter stores only an HMAC hash of normalized phone digits + salon slug. It does not persist raw phone numbers in the limiter table. Only `service_role` can call `consume_booking_rate_limit`; anon/authenticated clients cannot read or mutate the private limiter table.

## Migration history warning

The production database has 25 applied migrations, but only 15 original SQL migration files are currently present in `migrations/`. Ten older original migration files are missing from the accessible Git history. See [migrations/README_RU.md](migrations/README_RU.md).

- Do not run `supabase db reset` on production.
- Do not claim a clean-room deploy is reproducible with the currently checked-in migration files.
- Do not invent empty placeholder migrations.
- Before creating a new environment, recover the missing original SQL from a backup or create and test a complete bootstrap snapshot on a separate empty database.
- Every future migration must be applied, then immediately saved to GitHub under the exact version returned by Supabase.

## Android admin

- `android-admin` is a native Android WebView wrapper around `https://looksitess.github.io/SalonkrasiAmulet/admin/`. It automatically uses the latest deployed admin website; no duplicate Supabase logic is embedded in Java.
- `android-app` is the Capacitor wrapper. `scripts/prepare-web.mjs` downloads the online admin shell and PWA assets from the repo.
- Android release signing uses GitHub Actions secrets. The workflow skips release builds until all four protected signing secrets exist; once enabled, its download artifact contains only the APK/AAB, never the keystore or passwords. Never commit keystore files or signing passwords.

## Important remaining release checks

1. Assign a real master account to the free enabled slot; do not reuse an admin account as a master.
2. Verify the master schedule and real availability; current booking slots are fixed to 60 minutes, so the displayed 60 minutes is a scheduler slot, not confirmed procedure duration.
3. Perform a real end-to-end booking and admin/master review after a real master is configured.
4. Enable Supabase Auth leaked-password protection in the Dashboard.
5. Test a second salon with separate real test admin/master accounts before selling the multi-tenant service.
6. Confirm GitHub Actions quality workflow has completed successfully.
7. Complete onboarding, subscriptions/payments, data export/deletion, privacy terms, backups, and support before commercial SaaS launch.
