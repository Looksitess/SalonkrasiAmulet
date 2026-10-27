-- Added by Supabase migration 20261027173756 (master_slots_and_role_access).
BEGIN;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_admin boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS master_slot_id uuid;

CREATE TABLE IF NOT EXISTS public.master_slots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slot_number smallint NOT NULL UNIQUE CHECK (slot_number BETWEEN 1 AND 20),
  salon_id uuid NOT NULL REFERENCES public.salons(id) ON DELETE CASCADE,
  profile_id uuid UNIQUE REFERENCES public.profiles(id) ON DELETE SET NULL,
  display_name text NOT NULL,
  phone text,
  specialty text,
  enabled boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

DO $$
DECLARE v_salon_id uuid; v_profile_id uuid;
BEGIN
  SELECT id INTO v_salon_id FROM public.salons WHERE slug = 'amulet' LIMIT 1;
  IF v_salon_id IS NULL THEN RAISE EXCEPTION 'Salon amulet was not found'; END IF;
  SELECT p.id INTO v_profile_id FROM public.profiles p
  WHERE p.salon_id = v_salon_id AND p.role::text = 'master'
  ORDER BY p.created_at LIMIT 1;
  IF v_profile_id IS NULL THEN RAISE EXCEPTION 'No existing master profile found'; END IF;

  INSERT INTO public.master_slots (id,slot_number,salon_id,profile_id,display_name,phone,specialty,enabled)
  SELECT p.id,1,p.salon_id,p.id,p.full_name,p.phone,p.specialty,true
  FROM public.profiles p WHERE p.id=v_profile_id
  ON CONFLICT (slot_number) DO NOTHING;

  INSERT INTO public.master_slots (slot_number,salon_id,display_name,enabled)
  SELECT n,v_salon_id,'Вільне місце '||n::text,false
  FROM generate_series(2,20) AS n
  ON CONFLICT (slot_number) DO NOTHING;

  UPDATE public.master_slots SET profile_id=v_profile_id,salon_id=v_salon_id,updated_at=now()
  WHERE slot_number=1 AND profile_id IS NULL;

  UPDATE public.profiles p SET master_slot_id=ms.id,is_admin=true
  FROM public.master_slots ms WHERE ms.slot_number=1 AND ms.profile_id=p.id AND p.id=v_profile_id;
END $$;

ALTER TABLE public.work_schedule DROP CONSTRAINT IF EXISTS work_schedule_master_id_fkey;
ALTER TABLE public.work_schedule ADD CONSTRAINT work_schedule_master_id_fkey
  FOREIGN KEY (master_id) REFERENCES public.master_slots(id) ON DELETE RESTRICT;
ALTER TABLE public.blocked_slots DROP CONSTRAINT IF EXISTS blocked_slots_master_id_fkey;
ALTER TABLE public.blocked_slots ADD CONSTRAINT blocked_slots_master_id_fkey
  FOREIGN KEY (master_id) REFERENCES public.master_slots(id) ON DELETE RESTRICT;
ALTER TABLE public.bookings DROP CONSTRAINT IF EXISTS bookings_master_id_fkey;
ALTER TABLE public.bookings ADD CONSTRAINT bookings_master_id_fkey
  FOREIGN KEY (master_id) REFERENCES public.master_slots(id) ON DELETE SET NULL;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.profiles'::regclass AND conname='profiles_master_slot_id_fkey') THEN
    ALTER TABLE public.profiles ADD CONSTRAINT profiles_master_slot_id_fkey
      FOREIGN KEY (master_slot_id) REFERENCES public.master_slots(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_master_slot_unique ON public.profiles(master_slot_id) WHERE master_slot_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_master_slots_salon_enabled ON public.master_slots(salon_id,enabled,slot_number);
CREATE INDEX IF NOT EXISTS idx_blocked_slots_master_window ON public.blocked_slots(master_id,starts_at,ends_at);

INSERT INTO public.work_schedule (master_id,weekday,start_time,end_time,is_day_off)
SELECT ms.id,d.weekday,time '09:00',time '21:00',(d.weekday=0)
FROM public.master_slots ms CROSS JOIN generate_series(0,6) AS d(weekday)
ON CONFLICT (master_id,weekday) DO NOTHING;

CREATE OR REPLACE FUNCTION public.is_salon_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id=(SELECT auth.uid())
    AND p.active=true AND (p.is_admin=true OR p.role::text='admin'));
$$;
CREATE OR REPLACE FUNCTION public.current_active_master_slot_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT p.master_slot_id FROM public.profiles p
  JOIN public.master_slots ms ON ms.id=p.master_slot_id
  WHERE p.id=(SELECT auth.uid()) AND p.role::text='master'
    AND p.active=true AND ms.enabled=true LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.is_salon_admin() FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.current_active_master_slot_id() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.is_salon_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_active_master_slot_id() TO authenticated;

DROP VIEW IF EXISTS public.public_masters;
CREATE VIEW public.public_masters WITH (security_invoker=false) AS
SELECT ms.id,ms.slot_number,ms.display_name,ms.specialty
FROM public.master_slots ms
JOIN public.profiles p ON p.id=ms.profile_id
JOIN public.salons s ON s.id=ms.salon_id
WHERE s.slug='amulet' AND ms.enabled=true AND p.active=true AND p.role::text='master';
REVOKE ALL ON public.public_masters FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.public_masters TO anon,authenticated;

ALTER TABLE public.master_slots ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.master_slots FROM anon,authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.master_slots TO authenticated;

DROP POLICY IF EXISTS master_slots_read_own_or_admin ON public.master_slots;
CREATE POLICY master_slots_read_own_or_admin ON public.master_slots FOR SELECT TO authenticated
USING (public.is_salon_admin() OR id=(SELECT public.current_active_master_slot_id()));
DROP POLICY IF EXISTS master_slots_admin_insert ON public.master_slots;
CREATE POLICY master_slots_admin_insert ON public.master_slots FOR INSERT TO authenticated WITH CHECK (public.is_salon_admin());
DROP POLICY IF EXISTS master_slots_admin_update ON public.master_slots;
CREATE POLICY master_slots_admin_update ON public.master_slots FOR UPDATE TO authenticated USING (public.is_salon_admin()) WITH CHECK (public.is_salon_admin());
DROP POLICY IF EXISTS master_slots_admin_delete ON public.master_slots;
CREATE POLICY master_slots_admin_delete ON public.master_slots FOR DELETE TO authenticated USING (public.is_salon_admin());

DROP POLICY IF EXISTS profiles_admin_read_any ON public.profiles;
CREATE POLICY profiles_admin_read_any ON public.profiles FOR SELECT TO authenticated
USING (public.is_salon_admin() AND salon_id=(SELECT me.salon_id FROM public.profiles me WHERE me.id=(SELECT auth.uid())));
DROP POLICY IF EXISTS profiles_admin_update_any ON public.profiles;
CREATE POLICY profiles_admin_update_any ON public.profiles FOR UPDATE TO authenticated
USING (public.is_salon_admin() AND salon_id=(SELECT me.salon_id FROM public.profiles me WHERE me.id=(SELECT auth.uid())))
WITH CHECK (public.is_salon_admin() AND salon_id=(SELECT me.salon_id FROM public.profiles me WHERE me.id=(SELECT auth.uid())));

DROP POLICY IF EXISTS staff_read_bookings ON public.bookings;
DROP POLICY IF EXISTS staff_update_bookings ON public.bookings;
DROP POLICY IF EXISTS bookings_admin_select ON public.bookings;
CREATE POLICY bookings_admin_select ON public.bookings FOR SELECT TO authenticated
USING (public.is_salon_admin() AND salon_id=(SELECT me.salon_id FROM public.profiles me WHERE me.id=(SELECT auth.uid())));
DROP POLICY IF EXISTS bookings_master_select ON public.bookings;
CREATE POLICY bookings_master_select ON public.bookings FOR SELECT TO authenticated
USING (master_id=(SELECT public.current_active_master_slot_id()) AND salon_id=(SELECT me.salon_id FROM public.profiles me WHERE me.id=(SELECT auth.uid())));
DROP POLICY IF EXISTS bookings_admin_update ON public.bookings;
CREATE POLICY bookings_admin_update ON public.bookings FOR UPDATE TO authenticated
USING (public.is_salon_admin() AND salon_id=(SELECT me.salon_id FROM public.profiles me WHERE me.id=(SELECT auth.uid())))
WITH CHECK (public.is_salon_admin() AND salon_id=(SELECT me.salon_id FROM public.profiles me WHERE me.id=(SELECT auth.uid())));
DROP POLICY IF EXISTS bookings_master_update ON public.bookings;
CREATE POLICY bookings_master_update ON public.bookings FOR UPDATE TO authenticated
USING (master_id=(SELECT public.current_active_master_slot_id()) AND salon_id=(SELECT me.salon_id FROM public.profiles me WHERE me.id=(SELECT auth.uid())))
WITH CHECK (master_id=(SELECT public.current_active_master_slot_id()) AND salon_id=(SELECT me.salon_id FROM public.profiles me WHERE me.id=(SELECT auth.uid())));
DROP POLICY IF EXISTS bookings_admin_delete ON public.bookings;
CREATE POLICY bookings_admin_delete ON public.bookings FOR DELETE TO authenticated
USING (public.is_salon_admin() AND salon_id=(SELECT me.salon_id FROM public.profiles me WHERE me.id=(SELECT auth.uid())));

DROP POLICY IF EXISTS staff_read_schedule ON public.work_schedule;
DROP POLICY IF EXISTS work_schedule_admin_select ON public.work_schedule;
CREATE POLICY work_schedule_admin_select ON public.work_schedule FOR SELECT TO authenticated
USING (public.is_salon_admin() AND EXISTS (SELECT 1 FROM public.master_slots ms WHERE ms.id=work_schedule.master_id AND ms.salon_id=(SELECT me.salon_id FROM public.profiles me WHERE me.id=(SELECT auth.uid()))));
DROP POLICY IF EXISTS work_schedule_master_select ON public.work_schedule;
CREATE POLICY work_schedule_master_select ON public.work_schedule FOR SELECT TO authenticated
USING (master_id=(SELECT public.current_active_master_slot_id()));
DROP POLICY IF EXISTS work_schedule_admin_insert ON public.work_schedule;
CREATE POLICY work_schedule_admin_insert ON public.work_schedule FOR INSERT TO authenticated
WITH CHECK (public.is_salon_admin() AND EXISTS (SELECT 1 FROM public.master_slots ms WHERE ms.id=work_schedule.master_id AND ms.salon_id=(SELECT me.salon_id FROM public.profiles me WHERE me.id=(SELECT auth.uid()))));
DROP POLICY IF EXISTS work_schedule_admin_update ON public.work_schedule;
CREATE POLICY work_schedule_admin_update ON public.work_schedule FOR UPDATE TO authenticated
USING (public.is_salon_admin() AND EXISTS (SELECT 1 FROM public.master_slots ms WHERE ms.id=work_schedule.master_id AND ms.salon_id=(SELECT me.salon_id FROM public.profiles me WHERE me.id=(SELECT auth.uid()))))
WITH CHECK (public.is_salon_admin() AND EXISTS (SELECT 1 FROM public.master_slots ms WHERE ms.id=work_schedule.master_id AND ms.salon_id=(SELECT me.salon_id FROM public.profiles me WHERE me.id=(SELECT auth.uid()))));
DROP POLICY IF EXISTS work_schedule_admin_delete ON public.work_schedule;
CREATE POLICY work_schedule_admin_delete ON public.work_schedule FOR DELETE TO authenticated
USING (public.is_salon_admin() AND EXISTS (SELECT 1 FROM public.master_slots ms WHERE ms.id=work_schedule.master_id AND ms.salon_id=(SELECT me.salon_id FROM public.profiles me WHERE me.id=(SELECT auth.uid()))));

DROP POLICY IF EXISTS staff_read_blocked_slots ON public.blocked_slots;
DROP POLICY IF EXISTS blocked_slots_admin_select ON public.blocked_slots;
CREATE POLICY blocked_slots_admin_select ON public.blocked_slots FOR SELECT TO authenticated
USING (public.is_salon_admin() AND EXISTS (SELECT 1 FROM public.master_slots ms WHERE ms.id=blocked_slots.master_id AND ms.salon_id=(SELECT me.salon_id FROM public.profiles me WHERE me.id=(SELECT auth.uid()))));
DROP POLICY IF EXISTS blocked_slots_master_select ON public.blocked_slots;
CREATE POLICY blocked_slots_master_select ON public.blocked_slots FOR SELECT TO authenticated
USING (master_id=(SELECT public.current_active_master_slot_id()));
DROP POLICY IF EXISTS blocked_slots_admin_insert ON public.blocked_slots;
CREATE POLICY blocked_slots_admin_insert ON public.blocked_slots FOR INSERT TO authenticated
WITH CHECK (public.is_salon_admin() AND EXISTS (SELECT 1 FROM public.master_slots ms WHERE ms.id=blocked_slots.master_id AND ms.salon_id=(SELECT me.salon_id FROM public.profiles me WHERE me.id=(SELECT auth.uid()))));
DROP POLICY IF EXISTS blocked_slots_master_insert ON public.blocked_slots;
CREATE POLICY blocked_slots_master_insert ON public.blocked_slots FOR INSERT TO authenticated
WITH CHECK (master_id=(SELECT public.current_active_master_slot_id()));
DROP POLICY IF EXISTS blocked_slots_admin_delete ON public.blocked_slots;
CREATE POLICY blocked_slots_admin_delete ON public.blocked_slots FOR DELETE TO authenticated
USING (public.is_salon_admin() AND EXISTS (SELECT 1 FROM public.master_slots ms WHERE ms.id=blocked_slots.master_id AND ms.salon_id=(SELECT me.salon_id FROM public.profiles me WHERE me.id=(SELECT auth.uid()))));
DROP POLICY IF EXISTS blocked_slots_master_delete ON public.blocked_slots;
CREATE POLICY blocked_slots_master_delete ON public.blocked_slots FOR DELETE TO authenticated
USING (master_id=(SELECT public.current_active_master_slot_id()));

DROP FUNCTION IF EXISTS public.get_public_booked_times(date,uuid);
DROP FUNCTION IF EXISTS public.get_public_booked_times(date);
CREATE FUNCTION public.get_public_available_times(p_booking_date date,p_master_id uuid)
RETURNS TABLE(booking_time time without time zone,is_booked boolean,is_blocked boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  WITH chosen_master AS (
    SELECT ms.id FROM public.master_slots ms
    JOIN public.profiles p ON p.id=ms.profile_id
    JOIN public.salons s ON s.id=ms.salon_id
    WHERE ms.id=p_master_id AND ms.enabled=true AND p.active=true
      AND p.role::text='master' AND s.slug='amulet'
  ),
  working_day AS (
    SELECT ws.start_time,ws.end_time FROM public.work_schedule ws
    JOIN chosen_master cm ON cm.id=ws.master_id
    WHERE ws.weekday=EXTRACT(DOW FROM p_booking_date)::integer AND ws.is_day_off=false
  ),
  slots AS (
    SELECT (time '09:00'+g.n*interval '1 hour')::time AS slot_time FROM generate_series(0,11) AS g(n)
  )
  SELECT slots.slot_time,
    EXISTS (SELECT 1 FROM public.bookings b JOIN public.salons s ON s.id=b.salon_id
      WHERE s.slug='amulet' AND b.booking_date=p_booking_date AND b.booking_time=slots.slot_time
        AND b.status IN ('new','confirmed') AND (b.master_id=p_master_id OR b.master_id IS NULL)),
    EXISTS (SELECT 1 FROM public.blocked_slots bl
      WHERE bl.master_id=p_master_id
        AND bl.starts_at < ((p_booking_date::timestamp+slots.slot_time+interval '1 hour') AT TIME ZONE 'Europe/Kyiv')
        AND bl.ends_at > ((p_booking_date::timestamp+slots.slot_time) AT TIME ZONE 'Europe/Kyiv'))
  FROM slots
  WHERE EXISTS (SELECT 1 FROM chosen_master)
    AND EXISTS (SELECT 1 FROM working_day wd
      WHERE slots.slot_time>=wd.start_time AND slots.slot_time+interval '1 hour'<=wd.end_time)
  ORDER BY slots.slot_time;
$$;
REVOKE ALL ON FUNCTION public.get_public_available_times(date,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_available_times(date,uuid) TO anon,authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
