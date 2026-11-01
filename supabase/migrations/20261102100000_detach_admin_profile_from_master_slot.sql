-- An administrator account must not occupy a public master slot.
-- Preserve the salon's existing work schedule; only detach the incorrect profile link.
DO $$
DECLARE
  v_admin_id uuid;
  v_slot_id uuid;
  v_slot_number integer;
BEGIN
  SELECT p.id, ms.id, ms.slot_number
    INTO v_admin_id, v_slot_id, v_slot_number
  FROM public.profiles p
  JOIN public.master_slots ms ON ms.profile_id = p.id
  WHERE p.active = true
    AND (p.is_admin = true OR p.role::text = 'admin')
    AND ms.salon_id = p.salon_id
  ORDER BY ms.slot_number
  LIMIT 1;

  IF v_admin_id IS NULL THEN
    RAISE NOTICE 'No administrator profile is linked to a master slot; nothing to detach.';
    RETURN;
  END IF;

  UPDATE public.profiles
  SET master_slot_id = NULL
  WHERE id = v_admin_id
    AND master_slot_id = v_slot_id;

  UPDATE public.master_slots
  SET profile_id = NULL,
      display_name = 'Вільне місце ' || v_slot_number::text,
      phone = NULL,
      specialty = NULL,
      updated_at = now()
  WHERE id = v_slot_id
    AND profile_id = v_admin_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Could not safely detach the administrator from the master slot.';
  END IF;
END;
$$;
