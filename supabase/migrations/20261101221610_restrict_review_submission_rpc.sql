-- Review creation must require an authenticated user.
-- The trigger-only helper is not callable as a normal API function.
REVOKE ALL ON FUNCTION public.submit_customer_review(text, text, smallint, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.submit_customer_review(text, text, smallint, text) TO authenticated;

REVOKE ALL ON FUNCTION private.assign_content_report_salon() FROM PUBLIC;
REVOKE ALL ON FUNCTION private.assign_content_report_salon() FROM anon;
REVOKE ALL ON FUNCTION private.assign_content_report_salon() FROM authenticated;
