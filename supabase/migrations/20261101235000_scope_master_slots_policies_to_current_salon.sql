-- Scope every salon-admin operation on master_slots to the caller's own salon.
-- Master accounts retain read access to their own active slot only.

DROP POLICY IF EXISTS master_slots_admin_delete ON public.master_slots;
CREATE POLICY master_slots_admin_delete
ON public.master_slots
FOR DELETE
TO authenticated
USING (
  private.is_salon_admin()
  AND salon_id = (SELECT private.current_salon_id())
);

DROP POLICY IF EXISTS master_slots_admin_insert ON public.master_slots;
CREATE POLICY master_slots_admin_insert
ON public.master_slots
FOR INSERT
TO authenticated
WITH CHECK (
  private.is_salon_admin()
  AND salon_id = (SELECT private.current_salon_id())
);

DROP POLICY IF EXISTS master_slots_admin_update ON public.master_slots;
CREATE POLICY master_slots_admin_update
ON public.master_slots
FOR UPDATE
TO authenticated
USING (
  private.is_salon_admin()
  AND salon_id = (SELECT private.current_salon_id())
)
WITH CHECK (
  private.is_salon_admin()
  AND salon_id = (SELECT private.current_salon_id())
);

DROP POLICY IF EXISTS master_slots_read_own_or_admin ON public.master_slots;
CREATE POLICY master_slots_read_own_or_admin
ON public.master_slots
FOR SELECT
TO authenticated
USING (
  (
    private.is_salon_admin()
    AND salon_id = (SELECT private.current_salon_id())
  )
  OR id = (SELECT private.current_active_master_slot_id())
);
