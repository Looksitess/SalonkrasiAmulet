-- Apply the same content rate limits to edits so users cannot bypass
-- creation limits by repeatedly editing an existing review or forum post.

CREATE OR REPLACE FUNCTION public.update_customer_review_content(
 p_review_id uuid,p_customer_name text,p_rating smallint,p_review_text text
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_user_id uuid:=auth.uid(); v_salon_id uuid;
BEGIN
 IF v_user_id IS NULL THEN RAISE EXCEPTION 'Sign in is required'; END IF;
 IF char_length(btrim(p_customer_name)) NOT BETWEEN 2 AND 60
    OR p_rating NOT BETWEEN 1 AND 5
    OR char_length(btrim(p_review_text)) NOT BETWEEN 5 AND 1500 THEN
  RAISE EXCEPTION 'Review content is invalid';
 END IF;
 SELECT r.salon_id INTO v_salon_id FROM public.customer_reviews r
 WHERE r.id=p_review_id AND r.author_id=v_user_id
   AND r.status IN ('pending','approved','rejected');
 IF v_salon_id IS NULL THEN RAISE EXCEPTION 'Review could not be updated'; END IF;
 IF NOT private.consume_content_rate_limit(v_salon_id,v_user_id,'review',2,86400) THEN
  RAISE EXCEPTION 'Review submission limit reached. Try again later.';
 END IF;
 UPDATE public.customer_reviews
 SET customer_name=btrim(p_customer_name),rating=p_rating,
     review_text=btrim(p_review_text),status='pending',
     updated_at=pg_catalog.clock_timestamp()
 WHERE id=p_review_id AND author_id=v_user_id
   AND status IN ('pending','approved','rejected');
 IF NOT FOUND THEN RAISE EXCEPTION 'Review could not be updated'; END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_forum_topic_content(
 p_topic_id uuid,p_title text,p_body text,p_category text
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_user_id uuid:=auth.uid(); v_salon_id uuid;
BEGIN
 IF v_user_id IS NULL THEN RAISE EXCEPTION 'Sign in is required'; END IF;
 IF char_length(btrim(p_title)) NOT BETWEEN 4 AND 120
    OR char_length(btrim(p_body)) NOT BETWEEN 10 AND 3000
    OR p_category NOT IN ('Загальне','Догляд і краса','Питання майстрам','Манікюр і педикюр','Волосся') THEN
  RAISE EXCEPTION 'Forum topic content is invalid';
 END IF;
 SELECT t.salon_id INTO v_salon_id FROM public.forum_topics t
 WHERE t.id=p_topic_id AND t.author_id=v_user_id AND t.status='published';
 IF v_salon_id IS NULL THEN RAISE EXCEPTION 'Topic could not be updated'; END IF;
 IF NOT private.consume_content_rate_limit(v_salon_id,v_user_id,'forum_topic',3,3600) THEN
  RAISE EXCEPTION 'Rate limit exceeded for forum topics. Try again later.';
 END IF;
 UPDATE public.forum_topics
 SET title=btrim(p_title),body=btrim(p_body),category=p_category,
     updated_at=pg_catalog.clock_timestamp()
 WHERE id=p_topic_id AND author_id=v_user_id AND status='published';
 IF NOT FOUND THEN RAISE EXCEPTION 'Topic could not be updated'; END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_forum_post_content(p_post_id uuid,p_body text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_user_id uuid:=auth.uid(); v_salon_id uuid;
BEGIN
 IF v_user_id IS NULL THEN RAISE EXCEPTION 'Sign in is required'; END IF;
 IF char_length(btrim(p_body)) NOT BETWEEN 2 AND 2000 THEN
  RAISE EXCEPTION 'Forum reply content is invalid';
 END IF;
 SELECT t.salon_id INTO v_salon_id
 FROM public.forum_posts p JOIN public.forum_topics t ON t.id=p.topic_id
 WHERE p.id=p_post_id AND p.author_id=v_user_id AND p.status='published';
 IF v_salon_id IS NULL THEN RAISE EXCEPTION 'Reply could not be updated'; END IF;
 IF NOT private.consume_content_rate_limit(v_salon_id,v_user_id,'forum_post',20,3600) THEN
  RAISE EXCEPTION 'Rate limit exceeded for forum replies. Try again later.';
 END IF;
 UPDATE public.forum_posts SET body=btrim(p_body),updated_at=pg_catalog.clock_timestamp()
 WHERE id=p_post_id AND author_id=v_user_id AND status='published';
 IF NOT FOUND THEN RAISE EXCEPTION 'Reply could not be updated'; END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_review_comment_content(p_comment_id uuid,p_body text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_user_id uuid:=auth.uid(); v_salon_id uuid;
BEGIN
 IF v_user_id IS NULL THEN RAISE EXCEPTION 'Sign in is required'; END IF;
 IF char_length(btrim(p_body)) NOT BETWEEN 2 AND 1500 THEN
  RAISE EXCEPTION 'Comment content is invalid';
 END IF;
 SELECT r.salon_id INTO v_salon_id
 FROM public.review_comments c JOIN public.customer_reviews r ON r.id=c.review_id
 WHERE c.id=p_comment_id AND c.author_id=v_user_id AND c.status='published';
 IF v_salon_id IS NULL THEN RAISE EXCEPTION 'Comment could not be updated'; END IF;
 IF NOT private.consume_content_rate_limit(v_salon_id,v_user_id,'review_comment',20,3600) THEN
  RAISE EXCEPTION 'Comment limit reached. Try again later.';
 END IF;
 UPDATE public.review_comments
 SET body=btrim(p_body),updated_at=pg_catalog.clock_timestamp()
 WHERE id=p_comment_id AND author_id=v_user_id AND status='published';
 IF NOT FOUND THEN RAISE EXCEPTION 'Comment could not be updated'; END IF;
END;
$function$;
