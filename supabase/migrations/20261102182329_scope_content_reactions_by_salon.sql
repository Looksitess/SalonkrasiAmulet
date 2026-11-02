-- Tenant-scope every reaction and move public access behind narrow RPCs.
-- Existing reaction rows are backfilled from their target's owning salon.

ALTER TABLE public.content_reactions
  ADD COLUMN IF NOT EXISTS salon_id uuid;

UPDATE public.content_reactions cr
SET salon_id = CASE cr.target_type
  WHEN 'forum_topic' THEN (
    SELECT t.salon_id FROM public.forum_topics t WHERE t.id = cr.target_id
  )
  WHEN 'forum_post' THEN (
    SELECT t.salon_id
    FROM public.forum_posts p
    JOIN public.forum_topics t ON t.id = p.topic_id
    WHERE p.id = cr.target_id
  )
  WHEN 'customer_review' THEN (
    SELECT r.salon_id FROM public.customer_reviews r WHERE r.id = cr.target_id
  )
  WHEN 'review_comment' THEN (
    SELECT r.salon_id
    FROM public.review_comments c
    JOIN public.customer_reviews r ON r.id = c.review_id
    WHERE c.id = cr.target_id
  )
  ELSE NULL
END
WHERE cr.salon_id IS NULL;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.content_reactions WHERE salon_id IS NULL) THEN
    RAISE EXCEPTION 'Cannot safely assign every reaction to a salon';
  END IF;
END;
$$;

ALTER TABLE public.content_reactions
  ALTER COLUMN salon_id SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'content_reactions_salon_id_fkey'
      AND conrelid = 'public.content_reactions'::regclass
  ) THEN
    ALTER TABLE public.content_reactions
      ADD CONSTRAINT content_reactions_salon_id_fkey
      FOREIGN KEY (salon_id) REFERENCES public.salons(id) ON DELETE CASCADE;
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS content_reactions_salon_target_idx
  ON public.content_reactions (salon_id, target_type, target_id);

CREATE OR REPLACE FUNCTION private.assign_content_reaction_salon()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF NEW.target_type = 'forum_topic' THEN
    SELECT t.salon_id INTO NEW.salon_id
    FROM public.forum_topics t
    WHERE t.id = NEW.target_id
      AND t.status = 'published';
  ELSIF NEW.target_type = 'forum_post' THEN
    SELECT t.salon_id INTO NEW.salon_id
    FROM public.forum_posts p
    JOIN public.forum_topics t ON t.id = p.topic_id
    WHERE p.id = NEW.target_id
      AND p.status = 'published'
      AND t.status = 'published';
  ELSIF NEW.target_type = 'customer_review' THEN
    SELECT r.salon_id INTO NEW.salon_id
    FROM public.customer_reviews r
    WHERE r.id = NEW.target_id
      AND r.status = 'approved';
  ELSIF NEW.target_type = 'review_comment' THEN
    SELECT r.salon_id INTO NEW.salon_id
    FROM public.review_comments c
    JOIN public.customer_reviews r ON r.id = c.review_id
    WHERE c.id = NEW.target_id
      AND c.status = 'published'
      AND r.status = 'approved';
  ELSE
    RAISE EXCEPTION 'Unsupported reaction target type';
  END IF;

  IF NEW.salon_id IS NULL THEN
    RAISE EXCEPTION 'Reaction target is not publicly available';
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS content_reactions_assign_salon ON public.content_reactions;
CREATE TRIGGER content_reactions_assign_salon
BEFORE INSERT OR UPDATE OF target_type, target_id
ON public.content_reactions
FOR EACH ROW EXECUTE FUNCTION private.assign_content_reaction_salon();

REVOKE ALL ON FUNCTION private.assign_content_reaction_salon() FROM PUBLIC, anon, authenticated;

DROP POLICY IF EXISTS "Reactions are readable" ON public.content_reactions;
DROP POLICY IF EXISTS "Users can react as themselves" ON public.content_reactions;
DROP POLICY IF EXISTS "Users can remove their own reactions" ON public.content_reactions;

REVOKE ALL ON TABLE public.content_reactions FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_public_content_reactions(
  p_salon_slug text,
  p_target_type text,
  p_target_ids uuid[]
)
RETURNS TABLE (
  target_id uuid,
  reaction_count bigint,
  liked_by_caller boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT
    cr.target_id,
    count(*)::bigint AS reaction_count,
    coalesce(bool_or(cr.user_id = (SELECT auth.uid())), false) AS liked_by_caller
  FROM public.content_reactions cr
  JOIN public.salons s ON s.id = cr.salon_id
  WHERE s.slug = lower(btrim(p_salon_slug))
    AND cr.target_type = p_target_type
    AND p_target_type IN ('forum_topic', 'forum_post', 'customer_review', 'review_comment')
    AND cr.target_id = ANY(p_target_ids)
  GROUP BY cr.target_id;
$function$;

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

REVOKE ALL ON FUNCTION public.get_public_content_reactions(text, text, uuid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.toggle_public_content_reaction(text, text, uuid) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.get_public_content_reactions(text, text, uuid[]) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.toggle_public_content_reaction(text, text, uuid) TO authenticated;
