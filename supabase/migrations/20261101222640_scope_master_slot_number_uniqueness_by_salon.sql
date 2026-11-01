-- Master slot numbers are local to each salon, not globally unique.
-- A duplicate check is performed before applying this migration.
ALTER TABLE public.master_slots
  DROP CONSTRAINT IF EXISTS master_slots_slot_number_key;

ALTER TABLE public.master_slots
  ADD CONSTRAINT master_slots_salon_slot_number_key
  UNIQUE (salon_id, slot_number);
