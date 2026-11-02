-- Prevent staff profiles from referencing a deleted or non-existent salon.
-- Keep salon_id nullable for a newly registered account awaiting an invitation.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'profiles_salon_id_fkey'
      AND conrelid = 'public.profiles'::regclass
  ) THEN
    ALTER TABLE public.profiles
      ADD CONSTRAINT profiles_salon_id_fkey
      FOREIGN KEY (salon_id)
      REFERENCES public.salons(id)
      ON DELETE RESTRICT;
  END IF;
END;
$$;
