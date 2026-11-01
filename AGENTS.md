# Project-wide instructions for Codex

This repository contains a live salon-booking website and Supabase backend. Work carefully and preserve production behavior.

## Mandatory workflow
1. Inspect the relevant frontend, Edge Function, migration, database policy, and deployment files before editing.
2. Trace each feature from UI to server/database and back.
3. Make small, reviewable, reversible changes. Keep migrations additive.
4. Test success, invalid-input, unauthorized, and cross-tenant cases when applicable.
5. Report exact files changed, tests run, untested cases, and deployment status.
6. Never claim a feature is secure, tested, deployed, or complete without evidence.

## Security rules
- Never expose or commit service-role keys, secret keys, passwords, reset tokens, private keys, or real customer data.
- A Supabase publishable key may appear in browser code; a service-role/secret key must never appear there.
- Do not disable RLS, broaden grants, or remove authorization checks to make errors disappear.
- Admin/master privileges must be checked server-side on every privileged operation.
- Never trust a client-supplied salon_id alone. Derive tenant access from the authenticated profile/membership.
- SECURITY DEFINER functions need a safe search_path, schema-qualified objects, strict authorization, and limited EXECUTE grants.
- CORS is not authentication.
- Do not run destructive production SQL without a backup, reviewed plan, and explicit approval.
- Use synthetic test records only. Do not export or inspect real customer records unnecessarily.

## Tenant model
- Treat each salon as an isolated tenant. Bookings, staff, services, schedules, blocked times, reviews, notifications, and admin data must be tenant-scoped unless explicitly designed as shared community content.
- Any public tenant identity (slug/domain) must be resolved server-side and validated.
- A salon A admin or master must never access salon B private records.
- Test with at least two separate tenant fixtures before claiming multi-tenant readiness.

## Booking rules
- Validate name, phone, service, master, date, time, salon, availability, and conflicts on the server.
- Re-check availability at insertion time and rely on a database constraint/transaction to prevent double-booking races.
- Validate calendar dates, salon timezone, past-date rules, and field lengths.
- Public booking endpoints need abuse/rate controls and generic error messages.

## Migration-history warning

The production Supabase database has 24 applied migrations, but only 14 original SQL migration files are currently present in `supabase/migrations/`. See `supabase/migrations/README_RU.md` for the ten missing historical files. Do not run `supabase db reset` or claim a clean-room deploy is reproducible until a tested bootstrap snapshot or the original migrations have been recovered. Never fabricate empty placeholder migrations.

## Release rules
- Preserve the live Amulet flow during SaaS refactoring.
- Keep deployed Edge Function source synchronized with the repository.
- Do not remove indexes solely because early advisor output says they are unused.
- Treat prototype, pilot, and production-ready as different states.
