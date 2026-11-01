-- Short-lived per-salon, per-phone booking rate limits.
-- Only the booking Edge Function's service-role client can consume a limit.
CREATE TABLE IF NOT EXISTS private.booking_rate_limits (
  key_hash text NOT NULL,
  window_start timestamptz NOT NULL,
  request_count integer NOT NULL DEFAULT 0 CHECK (request_count > 0),
  PRIMARY KEY (key_hash, window_start)
);

CREATE INDEX IF NOT EXISTS booking_rate_limits_window_start_idx
  ON private.booking_rate_limits (window_start);

ALTER TABLE private.booking_rate_limits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.booking_rate_limits FROM PUBLIC;
REVOKE ALL ON TABLE private.booking_rate_limits FROM anon;
REVOKE ALL ON TABLE private.booking_rate_limits FROM authenticated;
REVOKE ALL ON TABLE private.booking_rate_limits FROM service_role;

CREATE OR REPLACE FUNCTION public.consume_booking_rate_limit(
  p_key_hash text,
  p_limit integer DEFAULT 5,
  p_window_seconds integer DEFAULT 600
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_window_start timestamptz;
  v_count integer;
BEGIN
  IF coalesce(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'Not allowed';
  END IF;

  IF p_key_hash IS NULL OR p_key_hash !~ '^[0-9a-f]{64}$'
     OR p_limit IS NULL OR p_limit < 1 OR p_limit > 100
     OR p_window_seconds IS NULL OR p_window_seconds < 60 OR p_window_seconds > 3600 THEN
    RAISE EXCEPTION 'Invalid rate limit parameters';
  END IF;

  v_window_start :=
    to_timestamp(
      floor(extract(epoch FROM clock_timestamp()) / p_window_seconds)
      * p_window_seconds
    );

  INSERT INTO private.booking_rate_limits (key_hash, window_start, request_count)
  VALUES (p_key_hash, v_window_start, 1)
  ON CONFLICT (key_hash, window_start)
  DO UPDATE SET request_count = private.booking_rate_limits.request_count + 1
  RETURNING request_count INTO v_count;

  DELETE FROM private.booking_rate_limits
  WHERE window_start < clock_timestamp() - interval '1 day';

  RETURN v_count <= p_limit;
END;
$function$;

REVOKE ALL ON FUNCTION public.consume_booking_rate_limit(text, integer, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.consume_booking_rate_limit(text, integer, integer) FROM anon;
REVOKE ALL ON FUNCTION public.consume_booking_rate_limit(text, integer, integer) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.consume_booking_rate_limit(text, integer, integer) TO service_role;
