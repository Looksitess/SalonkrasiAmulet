-- Public review form: allow anonymous submissions, but only as pending reviews.
-- Moderation remains mandatory; anonymous users cannot publish or edit reviews.
DROP POLICY IF EXISTS "Anonymous visitors can submit pending reviews" ON public.customer_reviews;
CREATE POLICY "Anonymous visitors can submit pending reviews"
ON public.customer_reviews
FOR INSERT
TO anon
WITH CHECK (
  author_id IS NULL
  AND status = 'pending'
  AND char_length(btrim(customer_name)) BETWEEN 2 AND 60
  AND rating BETWEEN 1 AND 5
  AND char_length(btrim(review_text)) BETWEEN 5 AND 1500
);

-- Cover foreign keys used for joins/deletes and reduce avoidable table scans.
CREATE INDEX IF NOT EXISTS admin_invitations_consumed_by_idx ON public.admin_invitations(consumed_by);
CREATE INDEX IF NOT EXISTS admin_invitations_salon_id_idx ON public.admin_invitations(salon_id);
CREATE INDEX IF NOT EXISTS bookings_service_id_idx ON public.bookings(service_id);
CREATE INDEX IF NOT EXISTS content_reactions_user_id_idx ON public.content_reactions(user_id);
CREATE INDEX IF NOT EXISTS content_reports_reporter_id_idx ON public.content_reports(reporter_id);
CREATE INDEX IF NOT EXISTS review_comments_author_id_idx ON public.review_comments(author_id);
CREATE INDEX IF NOT EXISTS user_notifications_actor_id_idx ON public.user_notifications(actor_id);
