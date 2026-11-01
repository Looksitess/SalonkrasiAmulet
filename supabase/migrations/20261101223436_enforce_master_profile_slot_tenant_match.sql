CREATE OR REPLACE FUNCTION private.current_active_master_slot_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT ms.id
  FROM public.profiles p
  JOIN public.master_slots ms
    ON ms.id = p.master_slot_id
   AND ms.salon_id = p.salon_id
  WHERE p.id = (SELECT auth.uid())
    AND p.role::text = 'master'
    AND p.active = true
    AND p.master_slot_id IS NOT NULL
    AND ms.enabled = true
  LIMIT 1;
$function$;

REVOKE ALL ON FUNCTION private.current_active_master_slot_id() FROM PUBLIC;
REVOKE ALL ON FUNCTION private.current_active_master_slot_id() FROM anon;
GRANT EXECUTE ON FUNCTION private.current_active_master_slot_id() TO authenticated;
