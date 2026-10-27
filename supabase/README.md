# Supabase backend for Amulet

## Edge Functions

- `functions/create-booking/index.ts`: validates enabled master, individual working hours, blocked times, and existing bookings before creating a request.
- `functions/manage-masters/index.ts`: creates an Auth login for an empty master slot only after validating the caller's active admin profile. The service key must stay in Supabase Edge Function secrets and must never be placed in public HTML.

## Master management

The live project has 20 fixed slots in `public.master_slots`. Slot 1 is connected to the existing account. Slots 2–20 are currently placeholders and disabled until the administrator assigns a name and creates the master's own login.

A staff login lives in `public.profiles` and is linked to a slot using `profiles.master_slot_id`. The same slot ID is used by `public.work_schedule`, `public.blocked_slots`, and `public.bookings.master_id`.

- An administrator can enable/disable slots, rename them, edit phone/specialty, create a master login, and set the 7-day schedule.
- A master can read only their own schedule and assigned bookings, and create/delete blocked time windows for their own slot.
- The public roster table `public.public_masters` contains only display fields; phone numbers and Auth IDs are not exposed.
- Existing 15 bookings were preserved and assigned to the original slot 1, so they remain on that master's schedule.

## Database migrations

The migrations in `migrations/` document the database changes applied to Supabase on 2026-10-27. Apply them in version order on a fresh environment. Do not re-run them against the already migrated production project.
