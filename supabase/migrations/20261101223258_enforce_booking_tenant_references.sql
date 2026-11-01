-- Enforce tenant consistency at the database level for every booking.
-- Existing production table is empty; the precheck found no null or cross-tenant rows.

ALTER TABLE public.master_slots
  ADD CONSTRAINT master_slots_id_salon_id_key UNIQUE (id, salon_id);

ALTER TABLE public.services
  ADD CONSTRAINT services_id_salon_id_key UNIQUE (id, salon_id);

ALTER TABLE public.bookings
  ALTER COLUMN salon_id SET NOT NULL;

ALTER TABLE public.bookings
  ADD CONSTRAINT bookings_salon_id_fkey
  FOREIGN KEY (salon_id) REFERENCES public.salons(id)
  ON DELETE RESTRICT;

ALTER TABLE public.bookings
  DROP CONSTRAINT bookings_master_id_fkey;

ALTER TABLE public.bookings
  ADD CONSTRAINT bookings_master_salon_fkey
  FOREIGN KEY (master_id, salon_id)
  REFERENCES public.master_slots(id, salon_id)
  ON DELETE SET NULL (master_id);

ALTER TABLE public.bookings
  DROP CONSTRAINT bookings_service_id_fkey;

ALTER TABLE public.bookings
  ADD CONSTRAINT bookings_service_salon_fkey
  FOREIGN KEY (service_id, salon_id)
  REFERENCES public.services(id, salon_id)
  ON DELETE SET NULL (service_id);

CREATE INDEX IF NOT EXISTS bookings_master_salon_idx
  ON public.bookings(master_id, salon_id);

CREATE INDEX IF NOT EXISTS bookings_service_salon_idx
  ON public.bookings(service_id, salon_id);
