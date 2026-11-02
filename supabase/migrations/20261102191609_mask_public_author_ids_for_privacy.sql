-- Do not expose stable Auth user UUIDs to unrelated public visitors.
-- The author_id remains available to the author for their own edit controls.

CREATE OR REPLACE FUNCTION public.get_public_approved_reviews(p_salon_slug text)
RETURNS TABLE (
  id uuid,
  customer_name text,
  rating smallint,
  review_text text,
  created_at timestamptz,
  author_id uuid
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT r.id,r.customer_name,r.rating,r.review_text,r.created_at,
    CASE WHEN r.author_id=(SELECT auth.uid()) THEN r.author_id ELSE NULL::uuid END
  FROM public.customer_reviews r
  JOIN public.salons s ON s.id=r.salon_id
  WHERE s.slug=lower(btrim(p_salon_slug)) AND r.status='approved'
  ORDER BY r.created_at DESC LIMIT 20;
$function$;

CREATE OR REPLACE FUNCTION public.get_public_review_comments(p_salon_slug text,p_review_id uuid)
RETURNS TABLE (
  id uuid,review_id uuid,parent_id uuid,author_id uuid,author_name text,body text,
  status text,created_at timestamptz,updated_at timestamptz
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT c.id,c.review_id,c.parent_id,
    CASE WHEN c.author_id=(SELECT auth.uid()) THEN c.author_id ELSE NULL::uuid END,
    c.author_name,c.body,c.status,c.created_at,c.updated_at
  FROM public.review_comments c
  JOIN public.customer_reviews r ON r.id=c.review_id
  JOIN public.salons s ON s.id=r.salon_id
  WHERE s.slug=lower(btrim(p_salon_slug))
    AND r.id=p_review_id AND r.status='approved' AND c.status='published'
  ORDER BY c.created_at ASC LIMIT 300;
$function$;

CREATE OR REPLACE FUNCTION public.get_public_forum_topics(p_salon_slug text,p_search text DEFAULT NULL)
RETURNS TABLE (
  id uuid,title text,category text,body text,author_id uuid,author_name text,
  created_at timestamptz,updated_at timestamptz,is_locked boolean,post_count bigint
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT t.id,t.title,t.category,t.body,
    CASE WHEN t.author_id=(SELECT auth.uid()) THEN t.author_id ELSE NULL::uuid END,
    t.author_name,t.created_at,t.updated_at,t.is_locked,count(p.id)::bigint
  FROM public.forum_topics t
  JOIN public.salons s ON s.id=t.salon_id
  LEFT JOIN public.forum_posts p ON p.topic_id=t.id AND p.status='published'
  WHERE s.slug=lower(btrim(p_salon_slug))
    AND t.status='published'
    AND (
      nullif(btrim(p_search),'') IS NULL
      OR t.title ILIKE '%'||btrim(p_search)||'%'
      OR t.body ILIKE '%'||btrim(p_search)||'%'
      OR t.author_name ILIKE '%'||btrim(p_search)||'%'
      OR EXISTS (
        SELECT 1 FROM public.forum_posts sp
        WHERE sp.topic_id=t.id AND sp.status='published'
          AND (sp.body ILIKE '%'||btrim(p_search)||'%' OR sp.author_name ILIKE '%'||btrim(p_search)||'%')
      )
    )
  GROUP BY t.id
  ORDER BY t.updated_at DESC LIMIT 1000;
$function$;

CREATE OR REPLACE FUNCTION public.get_public_forum_posts(p_salon_slug text,p_topic_id uuid)
RETURNS TABLE (
  id uuid,topic_id uuid,parent_id uuid,author_id uuid,author_name text,
  body text,created_at timestamptz,updated_at timestamptz
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  SELECT p.id,p.topic_id,p.parent_id,
    CASE WHEN p.author_id=(SELECT auth.uid()) THEN p.author_id ELSE NULL::uuid END,
    p.author_name,p.body,p.created_at,p.updated_at
  FROM public.forum_posts p
  JOIN public.forum_topics t ON t.id=p.topic_id
  JOIN public.salons s ON s.id=t.salon_id
  WHERE s.slug=lower(btrim(p_salon_slug))
    AND t.id=p_topic_id AND t.status='published' AND p.status='published'
  ORDER BY p.created_at ASC LIMIT 500;
$function$;

REVOKE ALL ON FUNCTION public.get_public_approved_reviews(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_approved_reviews(text) TO anon,authenticated;
REVOKE ALL ON FUNCTION public.get_public_review_comments(text,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_review_comments(text,uuid) TO anon,authenticated;
REVOKE ALL ON FUNCTION public.get_public_forum_topics(text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_forum_topics(text,text) TO anon,authenticated;
REVOKE ALL ON FUNCTION public.get_public_forum_posts(text,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_forum_posts(text,uuid) TO anon,authenticated;
