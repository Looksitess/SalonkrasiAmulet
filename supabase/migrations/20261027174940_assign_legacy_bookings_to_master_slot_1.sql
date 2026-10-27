-- Preserve legacy booking ownership by assigning old unassigned Amulet records to slot 1.
-- Idempotent: only bookings without a master are updated.
UPDATE public.bookings
SET master_id = (SELECT id FROM public.master_slots WHERE slot_number = 1),
    updated_at = now()
WHERE salon_id = (SELECT id FROM public.salons WHERE slug = 'amulet')
  AND master_id IS NULL;
