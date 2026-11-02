-- Preserve moderation/audit records: a salon with reports cannot be hard-deleted.
-- content_reports.salon_id is NOT NULL, so SET NULL was an invalid referential action.

ALTER TABLE public.content_reports
  DROP CONSTRAINT IF EXISTS content_reports_salon_id_fkey;

ALTER TABLE public.content_reports
  ADD CONSTRAINT content_reports_salon_id_fkey
  FOREIGN KEY (salon_id)
  REFERENCES public.salons(id)
  ON DELETE RESTRICT;
