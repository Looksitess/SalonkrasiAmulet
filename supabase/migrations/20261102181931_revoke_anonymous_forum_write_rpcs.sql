-- Only signed-in users may create topics and replies.
-- Supabase projects may have explicit anon EXECUTE grants independent of PUBLIC.

REVOKE ALL ON FUNCTION public.create_forum_topic(text, text, text, text, text)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_forum_post(text, uuid, uuid, text, text)
  FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.create_forum_topic(text, text, text, text, text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_forum_post(text, uuid, uuid, text, text)
  TO authenticated;
