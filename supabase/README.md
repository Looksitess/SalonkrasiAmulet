# Supabase backend for Amulet

## Edge Functions

- `functions/create-booking/index.ts`: creates a booking only for an enabled master and an open hour in that master's schedule.
- `functions/manage-masters/index.ts`: creates a master login only after validating the caller's admin role. The service key must stay in Supabase Edge Function secrets and must never be placed in public HTML.

## Master management

The live project has 20 fixed slots in `public.master_slots`. A master profile lives in `public.profiles` and is linked to a slot via `profiles.master_slot_id`. `public.work_schedule` and `public.blocked_slots` reference slot IDs. `public.public_masters` contains only public display fields, not phone numbers or auth IDs.

The database migrations were applied to Supabase on 2026-10-27; see `migrations/` for the schema changes. Existing records were retained and the 15 legacy bookings were assigned to the original active slot so they continue to block only that master's schedule.
