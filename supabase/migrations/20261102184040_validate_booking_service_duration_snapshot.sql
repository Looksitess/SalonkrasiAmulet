-- Ensure the duration snapshot on a new booking matches the active
-- service in the same salon at the exact moment the booking is written.

CREATE OR REPLACE FUNCTION private.validate_booking_service_duration()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_service_duration integer;
BEGIN
  IF NEW.service_id IS NULL THEN
    IF NEW.duration_minutes <> 60 THEN
      RAISE EXCEPTION 'A booking without a service must use the 60-minute fallback';
    END IF;
    RETURN NEW;
  END IF;

  SELECT sv.duration_minutes INTO v_service_duration
  FROM public.services sv
  WHERE sv.id = NEW.service_id
    AND sv.salon_id = NEW.salon_id
    AND sv.active = true;

  IF v_service_duration IS NULL THEN
    RAISE EXCEPTION 'Selected service is no longer active for this salon';
  END IF;

  IF v_service_duration <> NEW.duration_minutes THEN
    RAISE EXCEPTION 'Service duration changed. Refresh the booking form and try again';
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION private.validate_booking_service_duration()
  FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS bookings_validate_service_duration ON public.bookings;
CREATE TRIGGER bookings_validate_service_duration
BEFORE INSERT OR UPDATE OF service_id, salon_id, duration_minutes
ON public.bookings
FOR EACH ROW EXECUTE FUNCTION private.validate_booking_service_duration();
