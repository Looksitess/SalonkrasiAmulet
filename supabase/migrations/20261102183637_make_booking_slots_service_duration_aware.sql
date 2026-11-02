-- Make booking duration service-aware while preserving a snapshot on each booking.
-- Existing service durations and bookings remain at 60 minutes until the salon
-- owner sets real durations in the service catalog.

ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS duration_minutes integer NOT NULL DEFAULT 60;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'bookings_duration_minutes_valid'
      AND conrelid = 'public.bookings'::regclass
  ) THEN
    ALTER TABLE public.bookings
      ADD CONSTRAINT bookings_duration_minutes_valid
      CHECK (duration_minutes BETWEEN 15 AND 480 AND duration_minutes % 15 = 0);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'services_duration_minutes_valid'
      AND conrelid = 'public.services'::regclass
  ) THEN
    ALTER TABLE public.services
      ADD CONSTRAINT services_duration_minutes_valid
      CHECK (duration_minutes BETWEEN 15 AND 480 AND duration_minutes % 15 = 0);
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS bookings_salon_master_date_status_idx
  ON public.bookings (salon_id, master_id, booking_date, status);

CREATE OR REPLACE FUNCTION public.get_public_available_times(
  p_booking_date date,
  p_master_id uuid,
  p_salon_slug text,
  p_service_id uuid
)
RETURNS TABLE (
  booking_time time without time zone,
  is_booked boolean,
  is_blocked boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  WITH chosen_master AS (
    SELECT ms.id, ms.salon_id
    FROM public.master_slots ms
    JOIN public.profiles p ON p.id = ms.profile_id
    JOIN public.salons s ON s.id = ms.salon_id
    WHERE ms.id = p_master_id
      AND s.slug = lower(btrim(p_salon_slug))
      AND ms.enabled = true
      AND p.active = true
      AND p.role::text = 'master'
      AND p.master_slot_id = ms.id
      AND p.salon_id = ms.salon_id
  ),
  chosen_service AS (
    SELECT sv.id, sv.salon_id, sv.duration_minutes
    FROM public.services sv
    JOIN public.salons s ON s.id = sv.salon_id
    WHERE sv.id = p_service_id
      AND s.slug = lower(btrim(p_salon_slug))
      AND sv.active = true
      AND sv.duration_minutes BETWEEN 15 AND 480
      AND sv.duration_minutes % 15 = 0
  ),
  working_day AS (
    SELECT ws.start_time, ws.end_time, cm.salon_id
    FROM public.work_schedule ws
    JOIN chosen_master cm ON cm.id = ws.master_id
    WHERE ws.weekday = EXTRACT(DOW FROM p_booking_date)::integer
      AND ws.is_day_off = false
  ),
  slots AS (
    SELECT (time '09:00' + g.n * interval '15 minutes')::time AS slot_time
    FROM generate_series(0, 44) AS g(n)
  )
  SELECT
    slots.slot_time,
    EXISTS (
      SELECT 1
      FROM public.bookings b
      JOIN chosen_master cm ON cm.salon_id = b.salon_id
      WHERE b.master_id = p_master_id
        AND b.booking_date = p_booking_date
        AND b.status IN ('new', 'confirmed')
        AND slots.slot_time <
          b.booking_time + pg_catalog.make_interval(mins => b.duration_minutes)
        AND b.booking_time <
          slots.slot_time + pg_catalog.make_interval(mins => chosen_service.duration_minutes)
    ),
    EXISTS (
      SELECT 1
      FROM public.blocked_slots bl
      WHERE bl.master_id = p_master_id
        AND bl.starts_at <
          ((p_booking_date::timestamp + slots.slot_time
            + pg_catalog.make_interval(mins => chosen_service.duration_minutes))
            AT TIME ZONE 'Europe/Kyiv')
        AND bl.ends_at >
          ((p_booking_date::timestamp + slots.slot_time) AT TIME ZONE 'Europe/Kyiv')
    )
  FROM slots
  CROSS JOIN chosen_service
  WHERE EXISTS (SELECT 1 FROM chosen_master)
    AND EXISTS (
      SELECT 1
      FROM working_day wd
      WHERE slots.slot_time >= wd.start_time
        AND slots.slot_time
          + pg_catalog.make_interval(mins => chosen_service.duration_minutes)
          <= wd.end_time
    )
  ORDER BY slots.slot_time;
$function$;

REVOKE ALL ON FUNCTION public.get_public_available_times(date, uuid, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_available_times(date, uuid, text, uuid)
  TO anon, authenticated;

CREATE OR REPLACE FUNCTION private.prevent_booking_time_overlap()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_start timestamp without time zone;
  v_end timestamp without time zone;
  v_start_tz timestamptz;
  v_end_tz timestamptz;
BEGIN
  IF NEW.master_id IS NULL OR NEW.status::text NOT IN ('new','confirmed') THEN
    RETURN NEW;
  END IF;

  IF NEW.duration_minutes NOT BETWEEN 15 AND 480
     OR NEW.duration_minutes % 15 <> 0 THEN
    RAISE EXCEPTION 'Booking duration is invalid';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      NEW.salon_id::text || ':' || NEW.master_id::text || ':' || NEW.booking_date::text,
      0
    )
  );

  v_start := NEW.booking_date::timestamp + NEW.booking_time;
  v_end := v_start + pg_catalog.make_interval(mins => NEW.duration_minutes);
  v_start_tz := v_start AT TIME ZONE 'Europe/Kyiv';
  v_end_tz := v_end AT TIME ZONE 'Europe/Kyiv';

  IF EXISTS (
    SELECT 1
    FROM public.bookings b
    WHERE b.salon_id = NEW.salon_id
      AND b.master_id = NEW.master_id
      AND b.booking_date = NEW.booking_date
      AND b.status IN ('new','confirmed')
      AND b.id IS DISTINCT FROM NEW.id
      AND v_start < (b.booking_date::timestamp + b.booking_time
        + pg_catalog.make_interval(mins => b.duration_minutes))
      AND (b.booking_date::timestamp + b.booking_time) < v_end
  ) THEN
    RAISE EXCEPTION 'This master already has an overlapping active booking';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.blocked_slots bl
    WHERE bl.master_id = NEW.master_id
      AND bl.starts_at < v_end_tz
      AND bl.ends_at > v_start_tz
  ) THEN
    RAISE EXCEPTION 'This time is blocked for the selected master';
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION private.prevent_booking_time_overlap() FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS bookings_prevent_time_overlap ON public.bookings;
CREATE TRIGGER bookings_prevent_time_overlap
BEFORE INSERT OR UPDATE OF salon_id, master_id, booking_date, booking_time, duration_minutes, status
ON public.bookings
FOR EACH ROW EXECUTE FUNCTION private.prevent_booking_time_overlap();
