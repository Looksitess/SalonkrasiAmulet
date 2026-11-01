-- Tenant-scope services and customer reviews.
-- Existing rows are safely assigned to the only configured salon (Amulet).
-- Public clients use SECURITY DEFINER RPCs keyed by a public salon slug.
-- Salon admins manage only rows belonging to their own profile salon_id.

ALTER TABLE public.services
  ADD COLUMN IF NOT EXISTS salon_id uuid;

UPDATE public.services
SET salon_id = (SELECT s.id FROM public.salons s WHERE s.slug = 'amulet')
WHERE salon_id IS NULL;

ALTER TABLE public.services
  ALTER COLUMN salon_id SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'services_salon_id_fkey'
      AND conrelid = 'public.services'::regclass
  ) THEN
    ALTER TABLE public.services
      ADD CONSTRAINT services_salon_id_fkey
      FOREIGN KEY (salon_id) REFERENCES public.salons(id) ON DELETE CASCADE;
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS services_salon_active_category_idx
  ON public.services (salon_id, active, category);

CREATE UNIQUE INDEX IF NOT EXISTS services_salon_name_unique
  ON public.services (salon_id, lower(name));

ALTER TABLE public.customer_reviews
  ADD COLUMN IF NOT EXISTS salon_id uuid;

UPDATE public.customer_reviews
SET salon_id = (SELECT s.id FROM public.salons s WHERE s.slug = 'amulet')
WHERE salon_id IS NULL;

ALTER TABLE public.customer_reviews
  ALTER COLUMN salon_id SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'customer_reviews_salon_id_fkey'
      AND conrelid = 'public.customer_reviews'::regclass
  ) THEN
    ALTER TABLE public.customer_reviews
      ADD CONSTRAINT customer_reviews_salon_id_fkey
      FOREIGN KEY (salon_id) REFERENCES public.salons(id) ON DELETE CASCADE;
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS customer_reviews_salon_status_created_idx
  ON public.customer_reviews (salon_id, status, created_at DESC);

-- Services are no longer directly readable by anonymous clients.
-- The public RPC returns only active service fields for the requested salon.
DROP POLICY IF EXISTS public_read_active_services ON public.services;
DROP POLICY IF EXISTS services_admin_read_own_salon ON public.services;
DROP POLICY IF EXISTS services_admin_insert_own_salon ON public.services;
DROP POLICY IF EXISTS services_admin_update_own_salon ON public.services;
DROP POLICY IF EXISTS services_admin_delete_own_salon ON public.services;

CREATE POLICY services_admin_read_own_salon
ON public.services
FOR SELECT TO authenticated
USING (
  private.is_salon_admin()
  AND salon_id = (SELECT private.current_salon_id())
);

CREATE POLICY services_admin_insert_own_salon
ON public.services
FOR INSERT TO authenticated
WITH CHECK (
  private.is_salon_admin()
  AND salon_id = (SELECT private.current_salon_id())
);

CREATE POLICY services_admin_update_own_salon
ON public.services
FOR UPDATE TO authenticated
USING (
  private.is_salon_admin()
  AND salon_id = (SELECT private.current_salon_id())
)
WITH CHECK (
  private.is_salon_admin()
  AND salon_id = (SELECT private.current_salon_id())
);

CREATE POLICY services_admin_delete_own_salon
ON public.services
FOR DELETE TO authenticated
USING (
  private.is_salon_admin()
  AND salon_id = (SELECT private.current_salon_id())
);

REVOKE ALL ON TABLE public.services FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.services TO authenticated;

-- Review rows are tenant-scoped. Public review reads and submissions move to
-- narrow RPCs so callers cannot choose or enumerate another tenant's rows.
DROP POLICY IF EXISTS "Anonymous visitors can submit pending reviews" ON public.customer_reviews;
DROP POLICY IF EXISTS "Authenticated users can submit pending reviews" ON public.customer_reviews;
DROP POLICY IF EXISTS "Public can read approved reviews" ON public.customer_reviews;
DROP POLICY IF EXISTS "Admins can delete reviews" ON public.customer_reviews;
DROP POLICY IF EXISTS "Review admins can read all reviews" ON public.customer_reviews;
DROP POLICY IF EXISTS "Review admins can update reviews" ON public.customer_reviews;

CREATE POLICY customer_reviews_admin_read_own_salon
ON public.customer_reviews
FOR SELECT TO authenticated
USING (
  private.is_salon_admin()
  AND salon_id = (SELECT private.current_salon_id())
);

CREATE POLICY customer_reviews_admin_update_own_salon
ON public.customer_reviews
FOR UPDATE TO authenticated
USING (
  private.is_salon_admin()
  AND salon_id = (SELECT private.current_salon_id())
)
WITH CHECK (
  private.is_salon_admin()
  AND salon_id = (SELECT private.current_salon_id())
);

CREATE POLICY customer_reviews_admin_delete_own_salon
ON public.customer_reviews
FOR DELETE TO authenticated
USING (
  private.is_salon_admin()
  AND salon_id = (SELECT private.current_salon_id())
);

REVOKE ALL ON TABLE public.customer_reviews FROM anon;
REVOKE INSERT ON TABLE public.customer_reviews FROM authenticated;
GRANT SELECT, UPDATE, DELETE ON TABLE public.customer_reviews TO authenticated;

-- Public review comments are returned only through a salon-scoped RPC.
DROP POLICY IF EXISTS "Public can read review comments" ON public.review_comments;
DROP POLICY IF EXISTS "Review admins can delete comments" ON public.review_comments;
DROP POLICY IF EXISTS "Review admins can read all comments" ON public.review_comments;
DROP POLICY IF EXISTS "Review admins can update comments" ON public.review_comments;
DROP POLICY IF EXISTS "Signed-in users can comment on approved reviews" ON public.review_comments;

CREATE POLICY review_comments_admin_read_own_salon
ON public.review_comments
FOR SELECT TO authenticated
USING (
  private.is_salon_admin()
  AND EXISTS (
    SELECT 1
    FROM public.customer_reviews r
    WHERE r.id = review_comments.review_id
      AND r.salon_id = (SELECT private.current_salon_id())
  )
);

CREATE POLICY review_comments_admin_update_own_salon
ON public.review_comments
FOR UPDATE TO authenticated
USING (
  private.is_salon_admin()
  AND EXISTS (
    SELECT 1
    FROM public.customer_reviews r
    WHERE r.id = review_comments.review_id
      AND r.salon_id = (SELECT private.current_salon_id())
  )
)
WITH CHECK (
  private.is_salon_admin()
  AND EXISTS (
    SELECT 1
    FROM public.customer_reviews r
    WHERE r.id = review_comments.review_id
      AND r.salon_id = (SELECT private.current_salon_id())
  )
);

CREATE POLICY review_comments_admin_delete_own_salon
ON public.review_comments
FOR DELETE TO authenticated
USING (
  private.is_salon_admin()
  AND EXISTS (
    SELECT 1
    FROM public.customer_reviews r
    WHERE r.id = review_comments.review_id
      AND r.salon_id = (SELECT private.current_salon_id())
  )
);

CREATE OR REPLACE FUNCTION private.is_approved_review(p_review_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.customer_reviews r
    WHERE r.id = p_review_id
      AND r.status = 'approved'
  );
$function$;

REVOKE ALL ON FUNCTION private.is_approved_review(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.is_approved_review(uuid) TO authenticated;

CREATE POLICY review_comments_insert_on_approved_review
ON public.review_comments
FOR INSERT TO authenticated
WITH CHECK (
  author_id = (SELECT auth.uid())
  AND status = 'published'
  AND private.is_approved_review(review_id)
);

REVOKE ALL ON TABLE public.review_comments FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.review_comments TO authenticated;

-- Tenant-aware public catalog and booking queries.
CREATE OR REPLACE FUNCTION public.get_public_masters(p_salon_slug text)
RETURNS TABLE (
  id uuid,
  slot_number integer,
  display_name text,
  specialty text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT ms.id, ms.slot_number, ms.display_name, ms.specialty
  FROM public.master_slots ms
  JOIN public.profiles p ON p.id = ms.profile_id
  JOIN public.salons s ON s.id = ms.salon_id
  WHERE s.slug = lower(btrim(p_salon_slug))
    AND ms.enabled = true
    AND p.active = true
    AND p.role::text = 'master'
    AND p.master_slot_id = ms.id
    AND p.salon_id = ms.salon_id
  ORDER BY ms.slot_number;
$function$;

CREATE OR REPLACE FUNCTION public.get_public_services(p_salon_slug text)
RETURNS TABLE (
  id uuid,
  name text,
  category text,
  description text,
  price numeric,
  duration_minutes integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT sv.id, sv.name, sv.category, sv.description, sv.price, sv.duration_minutes
  FROM public.services sv
  JOIN public.salons s ON s.id = sv.salon_id
  WHERE s.slug = lower(btrim(p_salon_slug))
    AND sv.active = true
  ORDER BY sv.category NULLS LAST, sv.name;
$function$;

CREATE OR REPLACE FUNCTION public.get_public_approved_reviews(p_salon_slug text)
RETURNS TABLE (
  id uuid,
  customer_name text,
  rating smallint,
  review_text text,
  created_at timestamptz,
  author_id uuid
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT r.id, r.customer_name, r.rating, r.review_text, r.created_at, r.author_id
  FROM public.customer_reviews r
  JOIN public.salons s ON s.id = r.salon_id
  WHERE s.slug = lower(btrim(p_salon_slug))
    AND r.status = 'approved'
  ORDER BY r.created_at DESC
  LIMIT 20;
$function$;

CREATE OR REPLACE FUNCTION public.get_public_review_comments(
  p_salon_slug text,
  p_review_id uuid
)
RETURNS TABLE (
  id uuid,
  review_id uuid,
  parent_id uuid,
  author_id uuid,
  author_name text,
  body text,
  status text,
  created_at timestamptz,
  updated_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT c.id, c.review_id, c.parent_id, c.author_id, c.author_name,
         c.body, c.status, c.created_at, c.updated_at
  FROM public.review_comments c
  JOIN public.customer_reviews r ON r.id = c.review_id
  JOIN public.salons s ON s.id = r.salon_id
  WHERE s.slug = lower(btrim(p_salon_slug))
    AND r.id = p_review_id
    AND r.status = 'approved'
    AND c.status = 'published'
  ORDER BY c.created_at ASC
  LIMIT 300;
$function$;

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

-- Replace the old Amulet-only availability RPC with one that validates the
-- public salon slug against the selected master's actual tenant.
DROP FUNCTION IF EXISTS public.get_public_available_times(date, uuid);

CREATE FUNCTION public.get_public_available_times(
  p_booking_date date,
  p_master_id uuid,
  p_salon_slug text
)
RETURNS TABLE (
  booking_time time without time zone,
  is_booked boolean,
  is_blocked boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  WITH chosen_master AS (
    SELECT ms.id, ms.salon_id
    FROM public.master_slots ms
    JOIN public.profiles p ON p.id = ms.profile_id
    JOIN public.salons s ON s.id = ms.salon_id
    WHERE ms.id = p_master_id
      AND s.slug = lower(btrim(p_salon_slug))
      AND ms.enabled = true
      AND p.active = true
      AND p.role::text = 'master'
      AND p.master_slot_id = ms.id
      AND p.salon_id = ms.salon_id
  ),
  working_day AS (
    SELECT ws.start_time, ws.end_time, cm.salon_id
    FROM public.work_schedule ws
    JOIN chosen_master cm ON cm.id = ws.master_id
    WHERE ws.weekday = EXTRACT(DOW FROM p_booking_date)::integer
      AND ws.is_day_off = false
  ),
  slots AS (
    SELECT (time '09:00' + g.n * interval '1 hour')::time AS slot_time
    FROM generate_series(0, 11) AS g(n)
  )
  SELECT
    slots.slot_time,
    EXISTS (
      SELECT 1
      FROM public.bookings b
      JOIN working_day wd ON wd.salon_id = b.salon_id
      WHERE b.booking_date = p_booking_date
        AND b.booking_time = slots.slot_time
        AND b.status IN ('new', 'confirmed')
        AND (b.master_id = p_master_id OR b.master_id IS NULL)
    ),
    EXISTS (
      SELECT 1
      FROM public.blocked_slots bl
      WHERE bl.master_id = p_master_id
        AND bl.starts_at < ((p_booking_date::timestamp + slots.slot_time + interval '1 hour') AT TIME ZONE 'Europe/Kyiv')
        AND bl.ends_at > ((p_booking_date::timestamp + slots.slot_time) AT TIME ZONE 'Europe/Kyiv')
    )
  FROM slots
  WHERE EXISTS (SELECT 1 FROM chosen_master)
    AND EXISTS (
      SELECT 1
      FROM working_day wd
      WHERE slots.slot_time >= wd.start_time
        AND slots.slot_time + interval '1 hour' <= wd.end_time
    )
  ORDER BY slots.slot_time;
$function$;

REVOKE ALL ON FUNCTION public.get_public_masters(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_public_services(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_public_approved_reviews(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_public_review_comments(text, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.submit_customer_review(text, text, smallint, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_public_available_times(date, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.get_public_masters(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_public_services(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_public_approved_reviews(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_public_review_comments(text, uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.submit_customer_review(text, text, smallint, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_public_available_times(date, uuid, text) TO anon, authenticated;
