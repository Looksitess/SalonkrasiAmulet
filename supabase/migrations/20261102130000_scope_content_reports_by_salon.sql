-- Assign review-related reports to their salon and scope admin moderation.
-- Forum reports remain platform-wide because the forum is a shared community.

ALTER TABLE public.content_reports
  ADD COLUMN IF NOT EXISTS salon_id uuid;

UPDATE public.content_reports cr
SET salon_id = r.salon_id
FROM public.customer_reviews r
WHERE cr.target_type = 'customer_review'
  AND cr.target_id = r.id
  AND cr.salon_id IS NULL;

UPDATE public.content_reports cr
SET salon_id = r.salon_id
FROM public.review_comments c
JOIN public.customer_reviews r ON r.id = c.review_id
WHERE cr.target_type = 'review_comment'
  AND cr.target_id = c.id
  AND cr.salon_id IS NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'content_reports_salon_id_fkey'
      AND conrelid = 'public.content_reports'::regclass
  ) THEN
    ALTER TABLE public.content_reports
      ADD CONSTRAINT content_reports_salon_id_fkey
      FOREIGN KEY (salon_id) REFERENCES public.salons(id) ON DELETE SET NULL;
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS content_reports_salon_status_created_idx
  ON public.content_reports (salon_id, status, created_at DESC);

CREATE OR REPLACE FUNCTION private.assign_content_report_salon()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF NEW.target_type IN ('forum_topic', 'forum_post') THEN
    NEW.salon_id := NULL;
  ELSIF NEW.target_type = 'customer_review' THEN
    SELECT r.salon_id INTO NEW.salon_id
    FROM public.customer_reviews r
    WHERE r.id = NEW.target_id;

    IF NEW.salon_id IS NULL THEN
      RAISE EXCEPTION 'Review report target was not found';
    END IF;
  ELSIF NEW.target_type = 'review_comment' THEN
    SELECT r.salon_id INTO NEW.salon_id
    FROM public.review_comments c
    JOIN public.customer_reviews r ON r.id = c.review_id
    WHERE c.id = NEW.target_id;

    IF NEW.salon_id IS NULL THEN
      RAISE EXCEPTION 'Review comment report target was not found';
    END IF;
  ELSE
    RAISE EXCEPTION 'Unsupported report target type';
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS content_reports_assign_salon ON public.content_reports;
CREATE TRIGGER content_reports_assign_salon
BEFORE INSERT OR UPDATE OF target_type, target_id
ON public.content_reports
FOR EACH ROW
EXECUTE FUNCTION private.assign_content_report_salon();

DROP POLICY IF EXISTS "Admins can read reports" ON public.content_reports;
DROP POLICY IF EXISTS "Admins can update reports" ON public.content_reports;

CREATE POLICY content_reports_admin_read_global_or_own_salon
ON public.content_reports
FOR SELECT TO authenticated
USING (
  private.is_salon_admin()
  AND (
    salon_id IS NULL
    OR salon_id = (SELECT private.current_salon_id())
  )
);

CREATE POLICY content_reports_admin_update_global_or_own_salon
ON public.content_reports
FOR UPDATE TO authenticated
USING (
  private.is_salon_admin()
  AND (
    salon_id IS NULL
    OR salon_id = (SELECT private.current_salon_id())
  )
)
WITH CHECK (
  private.is_salon_admin()
  AND (
    salon_id IS NULL
    OR salon_id = (SELECT private.current_salon_id())
  )
);
