-- Multi-master foundation for Amulet salon
-- Run this once in Supabase Dashboard -> SQL Editor -> New query.
-- This migration is additive: it does not remove existing bookings or schedule rows.
BEGIN;

CREATE TABLE IF NOT EXISTS public.masters (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  specialty text,
  bio text,
  photo_url text,
  is_active boolean NOT NULL DEFAULT true,
  display_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Add a nullable relationship to bookings so the current booking endpoint keeps working
-- until the client form and Edge Function are updated to pass a selected master.
ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS master_id uuid;

-- Keep the existing work_schedule structure and connect its existing master IDs to masters.
DO $$
DECLARE
  master_total integer;
BEGIN
  INSERT INTO public.masters (id, name, display_order)
  SELECT
    source.master_id,
    CASE
      WHEN source.total = 1 THEN 'Основний майстер'
      ELSE 'Майстер ' || source.position::text
    END,
    source.position - 1
  FROM (
    SELECT
      ids.master_id,
      row_number() OVER (ORDER BY ids.master_id)::integer AS position,
      count(*) OVER ()::integer AS total
    FROM (
      SELECT DISTINCT ws.master_id
      FROM public.work_schedule AS ws
      WHERE ws.master_id IS NOT NULL
    ) AS ids
  ) AS source
  ON CONFLICT (id) DO NOTHING;

  -- If the app has older bookings that already contain master_id, preserve those IDs too.
  INSERT INTO public.masters (id, name, display_order)
  SELECT DISTINCT b.master_id, 'Майстер (наявні записи)', 1000
  FROM public.bookings AS b
  WHERE b.master_id IS NOT NULL
  ON CONFLICT (id) DO NOTHING;

  SELECT count(*) INTO master_total FROM public.masters;
  IF master_total = 0 THEN
    INSERT INTO public.masters (name, specialty, display_order)
    VALUES ('Основний майстер', 'Не вказано', 0);
  END IF;
END
$$;

-- Add foreign keys only if they do not already exist.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.bookings'::regclass
      AND conname = 'bookings_master_id_fkey'
  ) THEN
    ALTER TABLE public.bookings
      ADD CONSTRAINT bookings_master_id_fkey
      FOREIGN KEY (master_id) REFERENCES public.masters(id)
      ON DELETE SET NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.work_schedule'::regclass
      AND conname = 'work_schedule_master_id_fkey'
  ) THEN
    ALTER TABLE public.work_schedule
      ADD CONSTRAINT work_schedule_master_id_fkey
      FOREIGN KEY (master_id) REFERENCES public.masters(id)
      ON DELETE RESTRICT;
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_masters_active_order
  ON public.masters (is_active, display_order);

CREATE INDEX IF NOT EXISTS idx_bookings_master_date_time
  ON public.bookings (master_id, booking_date, booking_time);

CREATE INDEX IF NOT EXISTS idx_work_schedule_master_weekday
  ON public.work_schedule (master_id, weekday);

-- Public clients may read active master profiles for the future master selector.
-- No public INSERT/UPDATE/DELETE policy is created.
ALTER TABLE public.masters ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read active masters" ON public.masters;
CREATE POLICY "Anyone can read active masters"
  ON public.masters
  FOR SELECT
  TO anon, authenticated
  USING (is_active = true);

GRANT SELECT ON public.masters TO anon, authenticated;

COMMIT;
