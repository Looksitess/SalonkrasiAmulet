-- Restrict public availability lookups to today through 365 days ahead
-- in the salon's local timezone. This mirrors the Edge Function validation.

CREATE OR REPLACE FUNCTION public.get_public_available_times(
 p_booking_date date,p_master_id uuid,p_salon_slug text,p_service_id uuid
)
RETURNS TABLE(booking_time time without time zone,is_booked boolean,is_blocked boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
 WITH local_today AS (
  SELECT (pg_catalog.now() AT TIME ZONE 'Europe/Kyiv')::date AS day
 ),
 chosen_master AS (
  SELECT ms.id,ms.salon_id
  FROM public.master_slots ms
  JOIN public.profiles p ON p.id=ms.profile_id
  JOIN public.salons s ON s.id=ms.salon_id
  WHERE ms.id=p_master_id AND s.slug=lower(btrim(p_salon_slug))
   AND ms.enabled=true AND p.active=true AND p.role::text='master'
   AND p.master_slot_id=ms.id AND p.salon_id=ms.salon_id
 ),
 chosen_service AS (
  SELECT sv.id,sv.salon_id,sv.duration_minutes
  FROM public.services sv JOIN public.salons s ON s.id=sv.salon_id
  WHERE sv.id=p_service_id AND s.slug=lower(btrim(p_salon_slug))
   AND sv.active=true AND sv.duration_minutes BETWEEN 15 AND 480
   AND sv.duration_minutes%15=0
 ),
 working_day AS (
  SELECT ws.start_time,ws.end_time,cm.salon_id
  FROM public.work_schedule ws JOIN chosen_master cm ON cm.id=ws.master_id
  WHERE ws.weekday=EXTRACT(DOW FROM p_booking_date)::integer AND ws.is_day_off=false
 ),
 slots AS (
  SELECT (time '00:00'+g.n*interval '15 minutes')::time AS slot_time
  FROM generate_series(0,95) AS g(n)
 )
 SELECT slots.slot_time,
  EXISTS(
   SELECT 1 FROM public.bookings b JOIN chosen_master cm ON cm.salon_id=b.salon_id
   WHERE b.master_id=p_master_id AND b.booking_date=p_booking_date
    AND b.status IN ('new','confirmed')
    AND slots.slot_time < b.booking_time+pg_catalog.make_interval(mins=>b.duration_minutes)
    AND b.booking_time < slots.slot_time+pg_catalog.make_interval(mins=>chosen_service.duration_minutes)
  ),
  EXISTS(
   SELECT 1 FROM public.blocked_slots bl
   WHERE bl.master_id=p_master_id
    AND bl.starts_at<((p_booking_date::timestamp+slots.slot_time
       +pg_catalog.make_interval(mins=>chosen_service.duration_minutes)) AT TIME ZONE 'Europe/Kyiv')
    AND bl.ends_at>((p_booking_date::timestamp+slots.slot_time) AT TIME ZONE 'Europe/Kyiv')
  )
 FROM slots CROSS JOIN chosen_service
 WHERE p_booking_date >= (SELECT day FROM local_today)
  AND p_booking_date <= (SELECT day+365 FROM local_today)
  AND EXISTS(SELECT 1 FROM chosen_master)
  AND EXISTS(
   SELECT 1 FROM working_day wd
   WHERE slots.slot_time>=wd.start_time
    AND slots.slot_time+pg_catalog.make_interval(mins=>chosen_service.duration_minutes)<=wd.end_time
  )
 ORDER BY slots.slot_time;
$function$;

REVOKE ALL ON FUNCTION public.get_public_available_times(date,uuid,text,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_available_times(date,uuid,text,uuid)
 TO anon,authenticated;
