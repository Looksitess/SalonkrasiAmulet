-- Keep the legacy public_masters cache synchronized for every tenant.
-- Public clients must continue to use get_public_masters(salon_slug), not this table.

CREATE OR REPLACE FUNCTION public.sync_public_master(p_slot_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  INSERT INTO public.public_masters (id, slot_number, display_name, specialty)
  SELECT ms.id, ms.slot_number, ms.display_name, ms.specialty
  FROM public.master_slots ms
  JOIN public.profiles p ON p.id = ms.profile_id
  WHERE ms.id = p_slot_id
    AND ms.enabled = true
    AND p.active = true
    AND p.role::text = 'master'
    AND p.master_slot_id = ms.id
    AND p.salon_id = ms.salon_id
  ON CONFLICT (id) DO UPDATE
  SET slot_number = EXCLUDED.slot_number,
      display_name = EXCLUDED.display_name,
      specialty = EXCLUDED.specialty;

  IF NOT FOUND THEN
    DELETE FROM public.public_masters WHERE id = p_slot_id;
  END IF;
END;
$function$;
