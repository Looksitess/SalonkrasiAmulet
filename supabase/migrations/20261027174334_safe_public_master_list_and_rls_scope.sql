-- Match the live migration 20261027174334_safe_public_master_list_and_rls_scope.
BEGIN;

DROP VIEW IF EXISTS public.public_masters;
CREATE TABLE IF NOT EXISTS public.public_masters (
  id uuid PRIMARY KEY REFERENCES public.master_slots(id) ON DELETE CASCADE,
  slot_number smallint NOT NULL,
  display_name text NOT NULL,
  specialty text
);
ALTER TABLE public.public_masters ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.public_masters FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.public_masters TO anon, authenticated;
DROP POLICY IF EXISTS public_masters_read_public ON public.public_masters;
CREATE POLICY public_masters_read_public ON public.public_masters
FOR SELECT TO anon, authenticated USING (true);

CREATE OR REPLACE FUNCTION public.sync_public_master(p_slot_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.public_masters (id,slot_number,display_name,specialty)
  SELECT ms.id,ms.slot_number,ms.display_name,ms.specialty
  FROM public.master_slots ms
  JOIN public.profiles p ON p.id=ms.profile_id
  JOIN public.salons s ON s.id=ms.salon_id
  WHERE ms.id=p_slot_id AND ms.enabled=true AND p.active=true
    AND p.role::text='master' AND p.master_slot_id=ms.id
    AND p.salon_id=ms.salon_id AND s.slug='amulet'
  ON CONFLICT (id) DO UPDATE SET
    slot_number=EXCLUDED.slot_number,
    display_name=EXCLUDED.display_name,
    specialty=EXCLUDED.specialty;

  IF NOT FOUND THEN
    DELETE FROM public.public_masters WHERE id=p_slot_id;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.sync_public_master(uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.sync_public_master_slot_trigger()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  PERFORM public.sync_public_master(NEW.id);
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.sync_public_master_slot_trigger() FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS sync_public_master_after_slot_change ON public.master_slots;
CREATE TRIGGER sync_public_master_after_slot_change
AFTER INSERT OR UPDATE OF enabled,profile_id,display_name,specialty,slot_number,salon_id
ON public.master_slots FOR EACH ROW
EXECUTE FUNCTION public.sync_public_master_slot_trigger();

CREATE OR REPLACE FUNCTION public.sync_public_master_profile_trigger()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
BEGIN
  IF TG_OP='UPDATE' AND OLD.master_slot_id IS DISTINCT FROM NEW.master_slot_id
     AND OLD.master_slot_id IS NOT NULL THEN
    PERFORM public.sync_public_master(OLD.master_slot_id);
  END IF;
  IF NEW.master_slot_id IS NOT NULL THEN
    PERFORM public.sync_public_master(NEW.master_slot_id);
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.sync_public_master_profile_trigger() FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS sync_public_master_after_profile_change ON public.profiles;
CREATE TRIGGER sync_public_master_after_profile_change
AFTER INSERT OR UPDATE OF full_name,role,active,master_slot_id,salon_id,specialty
ON public.profiles FOR EACH ROW
EXECUTE FUNCTION public.sync_public_master_profile_trigger();

DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT id FROM public.master_slots LOOP
    PERFORM public.sync_public_master(r.id);
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.current_salon_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT p.salon_id FROM public.profiles p
  WHERE p.id=(SELECT auth.uid()) LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.current_salon_id() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.current_salon_id() TO authenticated;

DROP POLICY IF EXISTS profiles_admin_read_any ON public.profiles;
CREATE POLICY profiles_admin_read_any ON public.profiles FOR SELECT TO authenticated
USING (public.is_salon_admin() AND salon_id=(SELECT public.current_salon_id()));
DROP POLICY IF EXISTS profiles_admin_update_any ON public.profiles;
CREATE POLICY profiles_admin_update_any ON public.profiles FOR UPDATE TO authenticated
USING (public.is_salon_admin() AND salon_id=(SELECT public.current_salon_id()))
WITH CHECK (public.is_salon_admin() AND salon_id=(SELECT public.current_salon_id()));

DROP POLICY IF EXISTS bookings_admin_select ON public.bookings;
CREATE POLICY bookings_admin_select ON public.bookings FOR SELECT TO authenticated
USING (public.is_salon_admin() AND salon_id=(SELECT public.current_salon_id()));
DROP POLICY IF EXISTS bookings_master_select ON public.bookings;
CREATE POLICY bookings_master_select ON public.bookings FOR SELECT TO authenticated
USING (master_id=(SELECT public.current_active_master_slot_id()) AND salon_id=(SELECT public.current_salon_id()));
DROP POLICY IF EXISTS bookings_admin_update ON public.bookings;
CREATE POLICY bookings_admin_update ON public.bookings FOR UPDATE TO authenticated
USING (public.is_salon_admin() AND salon_id=(SELECT public.current_salon_id()))
WITH CHECK (public.is_salon_admin() AND salon_id=(SELECT public.current_salon_id()));
DROP POLICY IF EXISTS bookings_master_update ON public.bookings;
CREATE POLICY bookings_master_update ON public.bookings FOR UPDATE TO authenticated
USING (master_id=(SELECT public.current_active_master_slot_id()) AND salon_id=(SELECT public.current_salon_id()))
WITH CHECK (master_id=(SELECT public.current_active_master_slot_id()) AND salon_id=(SELECT public.current_salon_id()));
DROP POLICY IF EXISTS bookings_admin_delete ON public.bookings;
CREATE POLICY bookings_admin_delete ON public.bookings FOR DELETE TO authenticated
USING (public.is_salon_admin() AND salon_id=(SELECT public.current_salon_id()));

DROP POLICY IF EXISTS work_schedule_admin_select ON public.work_schedule;
CREATE POLICY work_schedule_admin_select ON public.work_schedule FOR SELECT TO authenticated
USING (public.is_salon_admin() AND EXISTS (SELECT 1 FROM public.master_slots ms
 WHERE ms.id=work_schedule.master_id AND ms.salon_id=(SELECT public.current_salon_id())));
DROP POLICY IF EXISTS work_schedule_admin_insert ON public.work_schedule;
CREATE POLICY work_schedule_admin_insert ON public.work_schedule FOR INSERT TO authenticated
WITH CHECK (public.is_salon_admin() AND EXISTS (SELECT 1 FROM public.master_slots ms
 WHERE ms.id=work_schedule.master_id AND ms.salon_id=(SELECT public.current_salon_id())));
DROP POLICY IF EXISTS work_schedule_admin_update ON public.work_schedule;
CREATE POLICY work_schedule_admin_update ON public.work_schedule FOR UPDATE TO authenticated
USING (public.is_salon_admin() AND EXISTS (SELECT 1 FROM public.master_slots ms
 WHERE ms.id=work_schedule.master_id AND ms.salon_id=(SELECT public.current_salon_id())))
WITH CHECK (public.is_salon_admin() AND EXISTS (SELECT 1 FROM public.master_slots ms
 WHERE ms.id=work_schedule.master_id AND ms.salon_id=(SELECT public.current_salon_id())));
DROP POLICY IF EXISTS work_schedule_admin_delete ON public.work_schedule;
CREATE POLICY work_schedule_admin_delete ON public.work_schedule FOR DELETE TO authenticated
USING (public.is_salon_admin() AND EXISTS (SELECT 1 FROM public.master_slots ms
 WHERE ms.id=work_schedule.master_id AND ms.salon_id=(SELECT public.current_salon_id())));

DROP POLICY IF EXISTS blocked_slots_admin_select ON public.blocked_slots;
CREATE POLICY blocked_slots_admin_select ON public.blocked_slots FOR SELECT TO authenticated
USING (public.is_salon_admin() AND EXISTS (SELECT 1 FROM public.master_slots ms
 WHERE ms.id=blocked_slots.master_id AND ms.salon_id=(SELECT public.current_salon_id())));
DROP POLICY IF EXISTS blocked_slots_admin_insert ON public.blocked_slots;
CREATE POLICY blocked_slots_admin_insert ON public.blocked_slots FOR INSERT TO authenticated
WITH CHECK (public.is_salon_admin() AND EXISTS (SELECT 1 FROM public.master_slots ms
 WHERE ms.id=blocked_slots.master_id AND ms.salon_id=(SELECT public.current_salon_id())));
DROP POLICY IF EXISTS blocked_slots_admin_delete ON public.blocked_slots;
CREATE POLICY blocked_slots_admin_delete ON public.blocked_slots FOR DELETE TO authenticated
USING (public.is_salon_admin() AND EXISTS (SELECT 1 FROM public.master_slots ms
 WHERE ms.id=blocked_slots.master_id AND ms.salon_id=(SELECT public.current_salon_id())));

ALTER TABLE public.blocked_slots DROP CONSTRAINT IF EXISTS blocked_slots_valid_window;
ALTER TABLE public.blocked_slots ADD CONSTRAINT blocked_slots_valid_window CHECK (ends_at > starts_at);
GRANT EXECUTE ON FUNCTION public.get_public_available_times(date,uuid) TO service_role;

NOTIFY pgrst,'reload schema';
COMMIT;
