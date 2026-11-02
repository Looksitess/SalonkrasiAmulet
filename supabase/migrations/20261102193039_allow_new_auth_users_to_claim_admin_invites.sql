-- Allow a newly registered Auth user with no profile to claim a valid
-- one-time salon-admin invitation. Never let an already assigned employee
-- move themselves to a different salon through an invitation code.

CREATE OR REPLACE FUNCTION public.claim_admin_invitation(invitation_code text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_salon_id uuid;
  v_profile public.profiles%ROWTYPE;
  v_profile_exists boolean := false;
  v_full_name text;
  v_claimed_profile_id uuid;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Требуется войти в аккаунт'; END IF;
  IF invitation_code IS NULL
     OR char_length(btrim(invitation_code)) < 16
     OR char_length(btrim(invitation_code)) > 256 THEN
    RAISE EXCEPTION 'Код приглашения недействителен';
  END IF;

  SELECT p.* INTO v_profile FROM public.profiles p
  WHERE p.id=v_user_id FOR UPDATE;
  v_profile_exists := FOUND;

  IF v_profile_exists AND (
    v_profile.active=false OR v_profile.salon_id IS NOT NULL
    OR v_profile.master_slot_id IS NOT NULL OR v_profile.is_admin=true
    OR v_profile.role::text='admin'
  ) THEN
    RAISE EXCEPTION 'Этот аккаунт уже привязан к сотруднику или салону';
  END IF;

  UPDATE public.admin_invitations i
  SET consumed_at=pg_catalog.clock_timestamp(),consumed_by=v_user_id
  WHERE i.token_hash=encode(
    extensions.digest(convert_to(btrim(invitation_code),'UTF8'),'sha256'),'hex'
  )
  AND i.consumed_at IS NULL
  AND i.expires_at>pg_catalog.clock_timestamp()
  RETURNING i.salon_id INTO v_salon_id;

  IF v_salon_id IS NULL THEN
    RAISE EXCEPTION 'Код недействителен, истёк или уже использован';
  END IF;

  IF v_profile_exists THEN
    v_full_name:=coalesce(nullif(btrim(v_profile.full_name),''),'Администратор');
  ELSE
    SELECT coalesce(
      nullif(btrim(u.raw_user_meta_data->>'full_name'),''),
      nullif(btrim(split_part(coalesce(u.email,''),'@',1)), ''),
      'Администратор'
    ) INTO v_full_name
    FROM auth.users u WHERE u.id=v_user_id;
    IF v_full_name IS NULL THEN RAISE EXCEPTION 'Auth-пользователь не найден'; END IF;
  END IF;

  INSERT INTO public.profiles(id,full_name,role,active,is_admin,salon_id)
  VALUES(v_user_id,v_full_name,'admin'::public.user_role,true,true,v_salon_id)
  ON CONFLICT(id) DO UPDATE
  SET full_name=EXCLUDED.full_name,
      role='admin'::public.user_role,
      active=true,is_admin=true,salon_id=EXCLUDED.salon_id
  WHERE public.profiles.salon_id IS NULL
    AND public.profiles.master_slot_id IS NULL
    AND public.profiles.is_admin=false
    AND public.profiles.role::text<>'admin'
    AND public.profiles.active=true
  RETURNING id INTO v_claimed_profile_id;

  IF v_claimed_profile_id IS NULL THEN
    RAISE EXCEPTION 'Не удалось безопасно привязать приглашение к профилю';
  END IF;

  RETURN jsonb_build_object('success',true,'role','admin','salon_id',v_salon_id);
END;
$function$;

REVOKE ALL ON FUNCTION public.claim_admin_invitation(text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.claim_admin_invitation(text) TO authenticated;
