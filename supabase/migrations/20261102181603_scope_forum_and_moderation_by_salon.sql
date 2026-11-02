-- Make the discussion forum salon-scoped.
-- Existing forum rows are assigned to Amulet; the current dataset is empty.

ALTER TABLE public.forum_topics
  ADD COLUMN IF NOT EXISTS salon_id uuid;

UPDATE public.forum_topics t
SET salon_id = s.id
FROM public.salons s
WHERE t.salon_id IS NULL
  AND s.slug = 'amulet';

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.forum_topics WHERE salon_id IS NULL) THEN
    RAISE EXCEPTION 'Cannot safely assign every forum topic to a salon';
  END IF;
END;
$$;

ALTER TABLE public.forum_topics
  ALTER COLUMN salon_id SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'forum_topics_salon_id_fkey'
      AND conrelid = 'public.forum_topics'::regclass
  ) THEN
    ALTER TABLE public.forum_topics
      ADD CONSTRAINT forum_topics_salon_id_fkey
      FOREIGN KEY (salon_id) REFERENCES public.salons(id) ON DELETE CASCADE;
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS forum_topics_salon_status_updated_idx
  ON public.forum_topics (salon_id, status, updated_at DESC);

DROP POLICY IF EXISTS "Admins can delete forum topics" ON public.forum_topics;
DROP POLICY IF EXISTS "Admins can update forum topics" ON public.forum_topics;
DROP POLICY IF EXISTS "Forum authors can delete own topics" ON public.forum_topics;
DROP POLICY IF EXISTS "Forum topics are public or admin-readable" ON public.forum_topics;
DROP POLICY IF EXISTS "Signed-in users can create forum topics" ON public.forum_topics;

CREATE POLICY forum_topics_admin_read_own_salon
ON public.forum_topics
FOR SELECT TO authenticated
USING (
  private.is_salon_admin()
  AND salon_id = (SELECT private.current_salon_id())
);

CREATE POLICY forum_topics_author_read_own
ON public.forum_topics
FOR SELECT TO authenticated
USING (author_id = (SELECT auth.uid()));

CREATE POLICY forum_topics_admin_update_own_salon
ON public.forum_topics
FOR UPDATE TO authenticated
USING (
  private.is_salon_admin()
  AND salon_id = (SELECT private.current_salon_id())
)
WITH CHECK (
  private.is_salon_admin()
  AND salon_id = (SELECT private.current_salon_id())
);

CREATE POLICY forum_topics_admin_delete_own_salon
ON public.forum_topics
FOR DELETE TO authenticated
USING (
  private.is_salon_admin()
  AND salon_id = (SELECT private.current_salon_id())
);

CREATE POLICY forum_topics_author_delete_own
ON public.forum_topics
FOR DELETE TO authenticated
USING (author_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Admins can delete forum replies" ON public.forum_posts;
DROP POLICY IF EXISTS "Admins can update forum replies" ON public.forum_posts;
DROP POLICY IF EXISTS "Forum authors can delete own replies" ON public.forum_posts;
DROP POLICY IF EXISTS "Forum replies are public or admin-readable" ON public.forum_posts;
DROP POLICY IF EXISTS "Signed-in users can reply to open topics" ON public.forum_posts;

CREATE POLICY forum_posts_admin_read_own_salon
ON public.forum_posts
FOR SELECT TO authenticated
USING (
  private.is_salon_admin()
  AND EXISTS (
    SELECT 1 FROM public.forum_topics t
    WHERE t.id = forum_posts.topic_id
      AND t.salon_id = (SELECT private.current_salon_id())
  )
);

CREATE POLICY forum_posts_author_read_own
ON public.forum_posts
FOR SELECT TO authenticated
USING (author_id = (SELECT auth.uid()));

CREATE POLICY forum_posts_admin_update_own_salon
ON public.forum_posts
FOR UPDATE TO authenticated
USING (
  private.is_salon_admin()
  AND EXISTS (
    SELECT 1 FROM public.forum_topics t
    WHERE t.id = forum_posts.topic_id
      AND t.salon_id = (SELECT private.current_salon_id())
  )
)
WITH CHECK (
  private.is_salon_admin()
  AND EXISTS (
    SELECT 1 FROM public.forum_topics t
    WHERE t.id = forum_posts.topic_id
      AND t.salon_id = (SELECT private.current_salon_id())
  )
);

CREATE POLICY forum_posts_admin_delete_own_salon
ON public.forum_posts
FOR DELETE TO authenticated
USING (
  private.is_salon_admin()
  AND EXISTS (
    SELECT 1 FROM public.forum_topics t
    WHERE t.id = forum_posts.topic_id
      AND t.salon_id = (SELECT private.current_salon_id())
  )
);

CREATE POLICY forum_posts_author_delete_own
ON public.forum_posts
FOR DELETE TO authenticated
USING (author_id = (SELECT auth.uid()));

REVOKE ALL ON TABLE public.forum_topics FROM anon;
REVOKE INSERT ON TABLE public.forum_topics FROM authenticated;
GRANT SELECT, UPDATE, DELETE ON TABLE public.forum_topics TO authenticated;

REVOKE ALL ON TABLE public.forum_posts FROM anon;
REVOKE INSERT ON TABLE public.forum_posts FROM authenticated;
GRANT SELECT, UPDATE, DELETE ON TABLE public.forum_posts TO authenticated;

CREATE OR REPLACE FUNCTION public.get_public_forum_topics(
  p_salon_slug text,
  p_search text DEFAULT NULL
)
RETURNS TABLE (
  id uuid,
  title text,
  category text,
  body text,
  author_id uuid,
  author_name text,
  created_at timestamptz,
  updated_at timestamptz,
  is_locked boolean,
  post_count bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT
    t.id, t.title, t.category, t.body, t.author_id, t.author_name,
    t.created_at, t.updated_at, t.is_locked, count(p.id)::bigint AS post_count
  FROM public.forum_topics t
  JOIN public.salons s ON s.id = t.salon_id
  LEFT JOIN public.forum_posts p
    ON p.topic_id = t.id
   AND p.status = 'published'
  WHERE s.slug = lower(btrim(p_salon_slug))
    AND t.status = 'published'
    AND (
      nullif(btrim(p_search), '') IS NULL
      OR t.title ILIKE '%' || btrim(p_search) || '%'
      OR t.body ILIKE '%' || btrim(p_search) || '%'
      OR t.author_name ILIKE '%' || btrim(p_search) || '%'
      OR EXISTS (
        SELECT 1
        FROM public.forum_posts sp
        WHERE sp.topic_id = t.id
          AND sp.status = 'published'
          AND (
            sp.body ILIKE '%' || btrim(p_search) || '%'
            OR sp.author_name ILIKE '%' || btrim(p_search) || '%'
          )
      )
    )
  GROUP BY t.id
  ORDER BY t.updated_at DESC
  LIMIT 1000;
$function$;

CREATE OR REPLACE FUNCTION public.get_public_forum_posts(
  p_salon_slug text,
  p_topic_id uuid
)
RETURNS TABLE (
  id uuid,
  topic_id uuid,
  parent_id uuid,
  author_id uuid,
  author_name text,
  body text,
  created_at timestamptz,
  updated_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT p.id, p.topic_id, p.parent_id, p.author_id, p.author_name,
         p.body, p.created_at, p.updated_at
  FROM public.forum_posts p
  JOIN public.forum_topics t ON t.id = p.topic_id
  JOIN public.salons s ON s.id = t.salon_id
  WHERE s.slug = lower(btrim(p_salon_slug))
    AND t.id = p_topic_id
    AND t.status = 'published'
    AND p.status = 'published'
  ORDER BY p.created_at ASC
  LIMIT 500;
$function$;

CREATE OR REPLACE FUNCTION public.create_forum_topic(
  p_salon_slug text,
  p_title text,
  p_body text,
  p_category text,
  p_author_name text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_salon_id uuid;
  v_topic_id uuid;
  v_title text := btrim(p_title);
  v_body text := btrim(p_body);
  v_author_name text := btrim(p_author_name);
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Sign in is required';
  END IF;

  IF char_length(v_title) NOT BETWEEN 4 AND 120
     OR char_length(v_body) NOT BETWEEN 10 AND 3000
     OR char_length(v_author_name) NOT BETWEEN 2 AND 50
     OR p_category NOT IN (
       'Загальне', 'Догляд і краса', 'Питання майстрам',
       'Манікюр і педикюр', 'Волосся'
     ) THEN
    RAISE EXCEPTION 'Forum topic content is invalid';
  END IF;

  SELECT s.id INTO v_salon_id
  FROM public.salons s
  WHERE s.slug = lower(btrim(p_salon_slug));

  IF v_salon_id IS NULL THEN
    RAISE EXCEPTION 'Salon not found';
  END IF;

  INSERT INTO public.forum_topics (
    salon_id, title, category, body, author_id, author_name, status, is_locked
  )
  VALUES (
    v_salon_id, v_title, p_category, v_body, v_user_id,
    v_author_name, 'published', false
  )
  RETURNING id INTO v_topic_id;

  RETURN v_topic_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_forum_post(
  p_salon_slug text,
  p_topic_id uuid,
  p_parent_id uuid,
  p_body text,
  p_author_name text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_salon_id uuid;
  v_post_id uuid;
  v_body text := btrim(p_body);
  v_author_name text := btrim(p_author_name);
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Sign in is required';
  END IF;

  IF char_length(v_body) NOT BETWEEN 2 AND 2000
     OR char_length(v_author_name) NOT BETWEEN 2 AND 50 THEN
    RAISE EXCEPTION 'Forum reply content is invalid';
  END IF;

  SELECT s.id INTO v_salon_id
  FROM public.salons s
  WHERE s.slug = lower(btrim(p_salon_slug));

  IF v_salon_id IS NULL THEN
    RAISE EXCEPTION 'Salon not found';
  END IF;

  PERFORM 1
  FROM public.forum_topics t
  WHERE t.id = p_topic_id
    AND t.salon_id = v_salon_id
    AND t.status = 'published'
    AND t.is_locked = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Topic is not available for replies';
  END IF;

  IF p_parent_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.forum_posts parent
    WHERE parent.id = p_parent_id
      AND parent.topic_id = p_topic_id
      AND parent.status = 'published'
  ) THEN
    RAISE EXCEPTION 'Parent reply is not available';
  END IF;

  INSERT INTO public.forum_posts (
    topic_id, parent_id, author_id, author_name, body, status
  )
  VALUES (
    p_topic_id, p_parent_id, v_user_id, v_author_name, v_body, 'published'
  )
  RETURNING id INTO v_post_id;

  RETURN v_post_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_public_forum_topics(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_public_forum_posts(text, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_forum_topic(text, text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_forum_post(text, uuid, uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.get_public_forum_topics(text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_public_forum_posts(text, uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_forum_topic(text, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_forum_post(text, uuid, uuid, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION private.assign_content_report_salon()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF NEW.target_type = 'forum_topic' THEN
    SELECT t.salon_id INTO NEW.salon_id
    FROM public.forum_topics t
    WHERE t.id = NEW.target_id;
  ELSIF NEW.target_type = 'forum_post' THEN
    SELECT t.salon_id INTO NEW.salon_id
    FROM public.forum_posts p
    JOIN public.forum_topics t ON t.id = p.topic_id
    WHERE p.id = NEW.target_id;
  ELSIF NEW.target_type = 'customer_review' THEN
    SELECT r.salon_id INTO NEW.salon_id
    FROM public.customer_reviews r
    WHERE r.id = NEW.target_id;
  ELSIF NEW.target_type = 'review_comment' THEN
    SELECT r.salon_id INTO NEW.salon_id
    FROM public.review_comments c
    JOIN public.customer_reviews r ON r.id = c.review_id
    WHERE c.id = NEW.target_id;
  ELSE
    RAISE EXCEPTION 'Unsupported report target type';
  END IF;

  IF NEW.salon_id IS NULL THEN
    RAISE EXCEPTION 'Report target was not found';
  END IF;

  RETURN NEW;
END;
$function$;

DROP POLICY IF EXISTS content_reports_admin_read_global_or_own_salon ON public.content_reports;
DROP POLICY IF EXISTS content_reports_admin_update_global_or_own_salon ON public.content_reports;

CREATE POLICY content_reports_admin_read_own_salon
ON public.content_reports
FOR SELECT TO authenticated
USING (
  private.is_salon_admin()
  AND salon_id = (SELECT private.current_salon_id())
);

CREATE POLICY content_reports_admin_update_own_salon
ON public.content_reports
FOR UPDATE TO authenticated
USING (
  private.is_salon_admin()
  AND salon_id = (SELECT private.current_salon_id())
)
WITH CHECK (
  private.is_salon_admin()
  AND salon_id = (SELECT private.current_salon_id())
);

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.content_reports WHERE salon_id IS NULL) THEN
    RAISE EXCEPTION 'Cannot safely scope existing content reports';
  END IF;
END;
$$;

ALTER TABLE public.content_reports
  ALTER COLUMN salon_id SET NOT NULL;

ALTER FUNCTION public.validate_content_target()
  SET search_path = '';
