-- The public frontend now reads staff exclusively through get_public_masters(slug).
-- Remove the old direct table exposure while keeping trigger/service-role maintenance.
DROP POLICY IF EXISTS public_masters_read_public ON public.public_masters;
REVOKE SELECT ON TABLE public.public_masters FROM anon;
REVOKE SELECT ON TABLE public.public_masters FROM authenticated;
