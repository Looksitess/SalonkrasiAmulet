-- The public booking UI and Edge Function now use the service-aware
-- four-argument RPC. Revoke access to the obsolete hourly-only overload.

REVOKE ALL ON FUNCTION public.get_public_available_times(date, uuid, text)
  FROM PUBLIC, anon, authenticated;
