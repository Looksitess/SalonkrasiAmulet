-- Add tenant/user/action scoped anti-abuse limits for interactive content.
-- The table stores only salon_id, auth user id, action key and counters.
-- It does not store IP addresses, names, phone numbers, or submitted text.

CREATE TABLE IF NOT EXISTS private.content_rate_limits (
  salon_id uuid NOT NULL REFERENCES public.salons(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  action text NOT NULL CHECK (
    action IN ('forum_topic','forum_post','review','review_comment','content_report','reaction')
  ),
  window_started_at timestamptz NOT NULL,
  hit_count integer NOT NULL CHECK (hit_count >= 1),
  updated_at timestamptz NOT NULL,
  PRIMARY KEY (salon_id, user_id, action)
);

ALTER TABLE private.content_rate_limits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.content_rate_limits FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION private.consume_content_rate_limit(
  p_salon_id uuid,
  p_user_id uuid,
  p_action text,
  p_max_hits integer,
  p_window_seconds integer
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_now timestamptz := pg_catalog.clock_timestamp();
  v_count integer;
  v_expiry timestamptz;
BEGIN
  IF p_salon_id IS NULL OR p_user_id IS NULL THEN
    RETURN false;
  END IF;

  IF p_action NOT IN (
    'forum_topic','forum_post','review','review_comment','content_report','reaction'
  )
  OR p_max_hits NOT BETWEEN 1 AND 1000
  OR p_window_seconds NOT BETWEEN 1 AND 86400 THEN
    RAISE EXCEPTION 'Invalid content rate limit configuration';
  END IF;

  v_expiry := v_now - pg_catalog.make_interval(secs => p_window_seconds);

  INSERT INTO private.content_rate_limits (
    salon_id, user_id, action, window_started_at, hit_count, updated_at
  )
  VALUES (p_salon_id, p_user_id, p_action, v_now, 1, v_now)
  ON CONFLICT (salon_id, user_id, action)
  DO UPDATE SET
    window_started_at = CASE
      WHEN private.content_rate_limits.window_started_at <= v_expiry
      THEN v_now
      ELSE private.content_rate_limits.window_started_at
    END,
    hit_count = CASE
      WHEN private.content_rate_limits.window_started_at <= v_expiry
      THEN 1
      WHEN private.content_rate_limits.hit_count >= p_max_hits + 1
      THEN p_max_hits + 1
      ELSE private.content_rate_limits.hit_count + 1
    END,
    updated_at = v_now
  RETURNING hit_count INTO v_count;

  RETURN v_count <= p_max_hits;
END;
$function$;

REVOKE ALL ON FUNCTION private.consume_content_rate_limit(uuid, uuid, text, integer, integer)
  FROM PUBLIC, anon, authenticated, service_role;

-- Topic publishing: 3 topics/hour/user/salon.
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

  IF NOT private.consume_content_rate_limit(v_salon_id, v_user_id, 'forum_topic', 3, 3600) THEN
    RAISE EXCEPTION 'Rate limit exceeded for forum topics. Try again later.';
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

-- Replies: 20 replies/hour/user/salon.
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

  IF NOT private.consume_content_rate_limit(v_salon_id, v_user_id, 'forum_post', 20, 3600) THEN
    RAISE EXCEPTION 'Rate limit exceeded for forum replies. Try again later.';
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

-- Reviews: 2 submissions/day/user/salon.
CREATE OR REPLACE FUNCTION public.submit_customer_review(
  p_salon_slug text,
  p_customer_name text,
  p_rating smallint,
  p_review_text text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_author_id uuid := auth.uid();
  v_salon_id uuid;
  v_review_id uuid;
  v_name text := btrim(p_customer_name);
  v_review text := btrim(p_review_text);
BEGIN
  IF v_author_id IS NULL THEN
    RAISE EXCEPTION 'Sign in is required to submit a review';
  END IF;

  IF v_name IS NULL OR char_length(v_name) NOT BETWEEN 2 AND 60
     OR p_rating IS NULL OR p_rating NOT BETWEEN 1 AND 5
     OR v_review IS NULL OR char_length(v_review) NOT BETWEEN 5 AND 1500 THEN
    RAISE EXCEPTION 'Review content is invalid';
  END IF;

  SELECT s.id INTO v_salon_id
  FROM public.salons s
  WHERE s.slug = lower(btrim(p_salon_slug));

  IF v_salon_id IS NULL THEN
    RAISE EXCEPTION 'Salon not found';
  END IF;

  IF NOT private.consume_content_rate_limit(v_salon_id, v_author_id, 'review', 2, 86400) THEN
    RAISE EXCEPTION 'Review submission limit reached. Try again later.';
  END IF;

  INSERT INTO public.customer_reviews (
    salon_id, author_id, customer_name, rating, review_text, status
  )
  VALUES (
    v_salon_id, v_author_id, v_name, p_rating, v_review, 'pending'
  )
  RETURNING id INTO v_review_id;

  RETURN v_review_id;
END;
$function$;

-- Reactions: 60 toggles/minute/user/salon.
CREATE OR REPLACE FUNCTION public.toggle_public_content_reaction(
  p_salon_slug text,
  p_target_type text,
  p_target_id uuid
)
RETURNS TABLE (
  reaction_count bigint,
  liked_by_caller boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_salon_id uuid;
  v_target_salon_id uuid;
  v_reaction_id uuid;
  v_liked boolean;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Sign in is required to react';
  END IF;

  IF p_target_type NOT IN ('forum_topic', 'forum_post', 'customer_review', 'review_comment') THEN
    RAISE EXCEPTION 'Unsupported reaction target type';
  END IF;

  SELECT s.id INTO v_salon_id
  FROM public.salons s
  WHERE s.slug = lower(btrim(p_salon_slug));

  IF v_salon_id IS NULL THEN
    RAISE EXCEPTION 'Salon not found';
  END IF;

  IF p_target_type = 'forum_topic' THEN
    SELECT t.salon_id INTO v_target_salon_id
    FROM public.forum_topics t
    WHERE t.id = p_target_id AND t.status = 'published';
  ELSIF p_target_type = 'forum_post' THEN
    SELECT t.salon_id INTO v_target_salon_id
    FROM public.forum_posts p
    JOIN public.forum_topics t ON t.id = p.topic_id
    WHERE p.id = p_target_id
      AND p.status = 'published'
      AND t.status = 'published';
  ELSIF p_target_type = 'customer_review' THEN
    SELECT r.salon_id INTO v_target_salon_id
    FROM public.customer_reviews r
    WHERE r.id = p_target_id AND r.status = 'approved';
  ELSE
    SELECT r.salon_id INTO v_target_salon_id
    FROM public.review_comments c
    JOIN public.customer_reviews r ON r.id = c.review_id
    WHERE c.id = p_target_id
      AND c.status = 'published'
      AND r.status = 'approved';
  END IF;

  IF v_target_salon_id IS NULL OR v_target_salon_id <> v_salon_id THEN
    RAISE EXCEPTION 'Reaction target is not available for this salon';
  END IF;

  IF NOT private.consume_content_rate_limit(v_salon_id, v_user_id, 'reaction', 60, 60) THEN
    RAISE EXCEPTION 'Reaction limit reached. Try again later.';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      v_user_id::text || ':' || p_target_type || ':' || p_target_id::text,
      0
    )
  );

  SELECT cr.id INTO v_reaction_id
  FROM public.content_reactions cr
  WHERE cr.salon_id = v_salon_id
    AND cr.target_type = p_target_type
    AND cr.target_id = p_target_id
    AND cr.user_id = v_user_id;

  IF v_reaction_id IS NOT NULL THEN
    DELETE FROM public.content_reactions cr WHERE cr.id = v_reaction_id;
    v_liked := false;
  ELSE
    INSERT INTO public.content_reactions (salon_id, target_type, target_id, user_id)
    VALUES (v_salon_id, p_target_type, p_target_id, v_user_id);
    v_liked := true;
  END IF;

  RETURN QUERY
  SELECT count(*)::bigint, v_liked
  FROM public.content_reactions cr
  WHERE cr.salon_id = v_salon_id
    AND cr.target_type = p_target_type
    AND cr.target_id = p_target_id;
END;
$function$;

-- Review comments are inserted directly under RLS. The trigger verifies the
-- author and review before consuming a 20/hour comment allowance.
CREATE OR REPLACE FUNCTION private.rate_limit_review_comment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_salon_id uuid;
BEGIN
  IF v_user_id IS NULL OR NEW.author_id IS DISTINCT FROM v_user_id THEN
    RAISE EXCEPTION 'Sign in is required to comment';
  END IF;

  SELECT r.salon_id INTO v_salon_id
  FROM public.customer_reviews r
  WHERE r.id = NEW.review_id
    AND r.status = 'approved';

  IF v_salon_id IS NULL THEN
    RAISE EXCEPTION 'Review is not available for comments';
  END IF;

  IF NOT private.consume_content_rate_limit(v_salon_id, v_user_id, 'review_comment', 20, 3600) THEN
    RAISE EXCEPTION 'Comment limit reached. Try again later.';
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION private.rate_limit_review_comment() FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS review_comments_z_rate_limit ON public.review_comments;
CREATE TRIGGER review_comments_z_rate_limit
BEFORE INSERT ON public.review_comments
FOR EACH ROW EXECUTE FUNCTION private.rate_limit_review_comment();

-- Reports are inserted directly under RLS. This trigger executes after the
-- existing target-to-salon resolver and target validity trigger.
CREATE OR REPLACE FUNCTION private.rate_limit_content_report()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL OR NEW.reporter_id IS DISTINCT FROM v_user_id THEN
    RAISE EXCEPTION 'Sign in is required to submit a report';
  END IF;

  IF NEW.salon_id IS NULL THEN
    RAISE EXCEPTION 'Report target is not associated with a salon';
  END IF;

  IF NOT private.consume_content_rate_limit(NEW.salon_id, v_user_id, 'content_report', 5, 3600) THEN
    RAISE EXCEPTION 'Report limit reached. Try again later.';
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION private.rate_limit_content_report() FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS content_reports_z_rate_limit ON public.content_reports;
CREATE TRIGGER content_reports_z_rate_limit
BEFORE INSERT ON public.content_reports
FOR EACH ROW EXECUTE FUNCTION private.rate_limit_content_report();
