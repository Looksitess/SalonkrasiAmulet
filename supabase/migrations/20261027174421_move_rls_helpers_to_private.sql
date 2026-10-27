-- Match the live migration 20261027174421_move_rls_helpers_to_private.
BEGIN;
CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC,anon;
GRANT USAGE ON SCHEMA private TO authenticated;

CREATE OR REPLACE FUNCTION private.is_salon_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT EXISTS (SELECT 1 FROM public.profiles p
    WHERE p.id=(SELECT auth.uid()) AND p.active=true
      AND (p.is_admin=true OR p.role::text='admin'));
$$;
CREATE OR REPLACE FUNCTION private.current_salon_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT p.salon_id FROM public.profiles p WHERE p.id=(SELECT auth.uid()) LIMIT 1;
$$;
CREATE OR REPLACE FUNCTION private.current_active_master_slot_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
  SELECT p.master_slot_id FROM public.profiles p
  JOIN public.master_slots ms ON ms.id=p.master_slot_id
  WHERE p.id=(SELECT auth.uid()) AND p.role::text='master'
    AND p.active=true AND ms.enabled=true LIMIT 1;
$$;

REVOKE ALL ON FUNCTION private.is_salon_admin() FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION private.current_salon_id() FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION private.current_active_master_slot_id() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION private.is_salon_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION private.current_salon_id() TO authenticated;
GRANT EXECUTE ON FUNCTION private.current_active_master_slot_id() TO authenticated;

DROP POLICY IF EXISTS master_slots_read_own_or_admin ON public.master_slots;
CREATE POLICY master_slots_read_own_or_admin ON public.master_slots FOR SELECT TO authenticated
USING (private.is_salon_admin() OR id=(SELECT private.current_active_master_slot_id()));
DROP POLICY IF EXISTS master_slots_admin_insert ON public.master_slots;
CREATE POLICY master_slots_admin_insert ON public.master_slots FOR INSERT TO authenticated WITH CHECK (private.is_salon_admin());
DROP POLICY IF EXISTS master_slots_admin_update ON public.master_slots;
CREATE POLICY master_slots_admin_update ON public.master_slots FOR UPDATE TO authenticated
USING (private.is_salon_admin()) WITH CHECK (private.is_salon_admin());
DROP POLICY IF EXISTS master_slots_admin_delete ON public.master_slots;
CREATE POLICY master_slots_admin_delete ON public.master_slots FOR DELETE TO authenticated USING (private.is_salon_admin());

DROP POLICY IF EXISTS profiles_admin_read_any ON public.profiles;
CREATE POLICY profiles_admin_read_any ON public.profiles FOR SELECT TO authenticated
USING (private.is_salon_admin() AND salon_id=(SELECT private.current_salon_id()));
DROP POLICY IF EXISTS profiles_admin_update_any ON public.profiles;
CREATE POLICY profiles_admin_update_any ON public.profiles FOR UPDATE TO authenticated
USING (private.is_salon_admin() AND salon_id=(SELECT private.current_salon_id()))
WITH CHECK (private.is_salon_admin() AND salon_id=(SELECT private.current_salon_id()));

DROP POLICY IF EXISTS bookings_admin_select ON public.bookings;
CREATE POLICY bookings_admin_select ON public.bookings FOR SELECT TO authenticated
USING (private.is_salon_admin() AND salon_id=(SELECT private.current_salon_id()));
DROP POLICY IF EXISTS bookings_master_select ON public.bookings;
CREATE POLICY bookings_master_select ON public.bookings FOR SELECT TO authenticated
USING (master_id=(SELECT private.current_active_master_slot_id()) AND salon_id=(SELECT private.current_salon_id()));
DROP POLICY IF EXISTS bookings_admin_update ON public.bookings;
CREATE POLICY bookings_admin_update ON public.bookings FOR UPDATE TO authenticated
USING (private.is_salon_admin() AND salon_id=(SELECT private.current_salon_id()))
WITH CHECK (private.is_salon_admin() AND salon_id=(SELECT private.current_salon_id()));
DROP POLICY IF EXISTS bookings_master_update ON public.bookings;
CREATE POLICY bookings_master_update ON public.bookings FOR UPDATE TO authenticated
USING (master_id=(SELECT private.current_active_master_slot_id()) AND salon_id=(SELECT private.current_salon_id()))
WITH CHECK (master_id=(SELECT private.current_active_master_slot_id()) AND salon_id=(SELECT private.current_salon_id()));
DROP POLICY IF EXISTS bookings_admin_delete ON public.bookings;
CREATE POLICY bookings_admin_delete ON public.bookings FOR DELETE TO authenticated
USING (private.is_salon_admin() AND salon_id=(SELECT private.current_salon_id()));

DROP POLICY IF EXISTS work_schedule_admin_select ON public.work_schedule;
CREATE POLICY work_schedule_admin_select ON public.work_schedule FOR SELECT TO authenticated
USING (private.is_salon_admin() AND EXISTS (SELECT 1 FROM public.master_slots ms
 WHERE ms.id=work_schedule.master_id AND ms.salon_id=(SELECT private.current_salon_id())));
DROP POLICY IF EXISTS work_schedule_master_select ON public.work_schedule;
CREATE POLICY work_schedule_master_select ON public.work_schedule FOR SELECT TO authenticated
USING (master_id=(SELECT private.current_active_master_slot_id()));
DROP POLICY IF EXISTS work_schedule_admin_insert ON public.work_schedule;
CREATE POLICY work_schedule_admin_insert ON public.work_schedule FOR INSERT TO authenticated
WITH CHECK (private.is_salon_admin() AND EXISTS (SELECT 1 FROM public.master_slots ms
 WHERE ms.id=work_schedule.master_id AND ms.salon_id=(SELECT private.current_salon_id())));
DROP POLICY IF EXISTS work_schedule_admin_update ON public.work_schedule;
CREATE POLICY work_schedule_admin_update ON public.work_schedule FOR UPDATE TO authenticated
USING (private.is_salon_admin() AND EXISTS (SELECT 1 FROM public.master_slots ms
 WHERE ms.id=work_schedule.master_id AND ms.salon_id=(SELECT private.current_salon_id())))
WITH CHECK (private.is_salon_admin() AND EXISTS (SELECT 1 FROM public.master_slots ms
 WHERE ms.id=work_schedule.master_id AND ms.salon_id=(SELECT private.current_salon_id())));
DROP POLICY IF EXISTS work_schedule_admin_delete ON public.work_schedule;
CREATE POLICY work_schedule_admin_delete ON public.work_schedule FOR DELETE TO authenticated
USING (private.is_salon_admin() AND EXISTS (SELECT 1 FROM public.master_slots ms
 WHERE ms.id=work_schedule.master_id AND ms.salon_id=(SELECT private.current_salon_id())));

DROP POLICY IF EXISTS blocked_slots_admin_select ON public.blocked_slots;
CREATE POLICY blocked_slots_admin_select ON public.blocked_slots FOR SELECT TO authenticated
USING (private.is_salon_admin() AND EXISTS (SELECT 1 FROM public.master_slots ms
 WHERE ms.id=blocked_slots.master_id AND ms.salon_id=(SELECT private.current_salon_id())));
DROP POLICY IF EXISTS blocked_slots_master_select ON public.blocked_slots;
CREATE POLICY blocked_slots_master_select ON public.blocked_slots FOR SELECT TO authenticated
USING (master_id=(SELECT private.current_active_master_slot_id()));
DROP POLICY IF EXISTS blocked_slots_admin_insert ON public.blocked_slots;
CREATE POLICY blocked_slots_admin_insert ON public.blocked_slots FOR INSERT TO authenticated
WITH CHECK (private.is_salon_admin() AND EXISTS (SELECT 1 FROM public.master_slots ms
 WHERE ms.id=blocked_slots.master_id AND ms.salon_id=(SELECT private.current_salon_id())));
DROP POLICY IF EXISTS blocked_slots_master_insert ON public.blocked_slots;
CREATE POLICY blocked_slots_master_insert ON public.blocked_slots FOR INSERT TO authenticated
WITH CHECK (master_id=(SELECT private.current_active_master_slot_id()));
DROP POLICY IF EXISTS blocked_slots_admin_delete ON public.blocked_slots;
CREATE POLICY blocked_slots_admin_delete ON public.blocked_slots FOR DELETE TO authenticated
USING (private.is_salon_admin() AND EXISTS (SELECT 1 FROM public.master_slots ms
 WHERE ms.id=blocked_slots.master_id AND ms.salon_id=(SELECT private.current_salon_id())));
DROP POLICY IF EXISTS blocked_slots_master_delete ON public.blocked_slots;
CREATE POLICY blocked_slots_master_delete ON public.blocked_slots FOR DELETE TO authenticated
USING (master_id=(SELECT private.current_active_master_slot_id()));

DROP FUNCTION IF EXISTS public.is_salon_admin();
DROP FUNCTION IF EXISTS public.current_salon_id();
DROP FUNCTION IF EXISTS public.current_active_master_slot_id();

DROP POLICY IF EXISTS staff_read_own_profile ON public.profiles;
CREATE POLICY staff_read_own_profile ON public.profiles FOR SELECT TO authenticated
USING (id=(SELECT auth.uid()));

NOTIFY pgrst,'reload schema';
COMMIT;
