-- Pin SECURITY DEFINER routines to an empty search_path.
-- All referenced application objects are schema-qualified in these functions.
-- This prevents objects created in writable schemas from shadowing trusted names.

ALTER FUNCTION public.bump_forum_topic_updated_at()
  SET search_path = '';

ALTER FUNCTION public.notify_forum_reply()
  SET search_path = '';

ALTER FUNCTION public.notify_review_comment()
  SET search_path = '';

ALTER FUNCTION public.update_customer_review_content(uuid, text, smallint, text)
  SET search_path = '';

ALTER FUNCTION public.update_forum_post_content(uuid, text)
  SET search_path = '';

ALTER FUNCTION public.update_forum_topic_content(uuid, text, text, text)
  SET search_path = '';

ALTER FUNCTION public.update_review_comment_content(uuid, text)
  SET search_path = '';

ALTER FUNCTION public.validate_content_target()
  SET search_path = '';
