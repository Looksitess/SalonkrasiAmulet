-- Multi-master foundation for the existing Amulet Supabase schema.
-- The project already uses public.profiles as the master/staff table.
-- This migration is additive and preserves existing bookings and schedules.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS specialty text;

CREATE INDEX IF NOT EXISTS idx_profiles_salon_role_active
  ON public.profiles (salon_id, role, active);

CREATE INDEX IF NOT EXISTS idx_bookings_salon_master_date_time
  ON public.bookings (salon_id, master_id, booking_date, booking_time);

-- A public-safe read-only view: exposes only display fields for active masters
-- at Amulet, never phone numbers or other profile data.
CREATE OR REPLACE VIEW public.public_masters
WITH (security_invoker = false)
AS
SELECT
  p.id,
  p.full_name,
  p.specialty,
  p.avatar_url
FROM public.profiles AS p
JOIN public.salons AS s ON s.id = p.salon_id
WHERE s.slug = 'amulet'
  AND p.role::text = 'master'
  AND p.active = true;

GRANT SELECT ON public.public_masters TO anon, authenticated;

-- Prevent two active bookings from claiming the same slot for the same master.
-- Existing bookings are currently unassigned (master_id IS NULL), so no data is rewritten.
CREATE UNIQUE INDEX IF NOT EXISTS uq_bookings_active_master_slot
  ON public.bookings (salon_id, master_id, booking_date, booking_time)
  WHERE master_id IS NOT NULL
    AND status IN ('new', 'confirmed');

-- Keep the existing RPC name but allow a selected master_id.
-- If master_id is omitted, behaviour stays compatible with the current website.
-- Legacy bookings without a master_id block that time for every master.
DROP FUNCTION IF EXISTS public.get_public_booked_times(date);

CREATE FUNCTION public.get_public_booked_times(
  p_booking_date date,
  p_master_id uuid DEFAULT NULL
)
RETURNS TABLE (booking_time time without time zone)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT b.booking_time
  FROM public.bookings AS b
  JOIN public.salons AS s ON s.id = b.salon_id
  WHERE s.slug = 'amulet'
    AND b.booking_date = p_booking_date
    AND b.status IN ('new', 'confirmed')
    AND (
      p_master_id IS NULL
      OR b.master_id = p_master_id
      OR b.master_id IS NULL
    )
  ORDER BY b.booking_time;
$function$;

REVOKE ALL ON FUNCTION public.get_public_booked_times(date, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_booked_times(date, uuid) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
