-- Preserve the currently published Amulet price labels in the tenant-aware catalogue.
-- The scheduler still supports fixed one-hour booking slots; durations stay at 60 minutes.

ALTER TABLE public.services
  ADD COLUMN IF NOT EXISTS price_label text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'services_price_label_length_check'
      AND conrelid = 'public.services'::regclass
  ) THEN
    ALTER TABLE public.services
      ADD CONSTRAINT services_price_label_length_check
      CHECK (price_label IS NULL OR char_length(price_label) <= 60);
  END IF;
END;
$$;

DROP FUNCTION IF EXISTS public.get_public_services(text);

CREATE FUNCTION public.get_public_services(p_salon_slug text)
RETURNS TABLE (
  id uuid,
  name text,
  category text,
  description text,
  price numeric,
  price_label text,
  duration_minutes integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT sv.id, sv.name, sv.category, sv.description,
         sv.price, sv.price_label, sv.duration_minutes
  FROM public.services sv
  JOIN public.salons s ON s.id = sv.salon_id
  WHERE s.slug = lower(btrim(p_salon_slug))
    AND sv.active = true
  ORDER BY sv.category NULLS LAST, sv.name;
$function$;

REVOKE ALL ON FUNCTION public.get_public_services(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_public_services(text) FROM anon;
REVOKE ALL ON FUNCTION public.get_public_services(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_public_services(text) TO anon, authenticated;

INSERT INTO public.services (
  salon_id, name, category, description, price, price_label,
  duration_minutes, active
)
SELECT s.id, v.name, v.category, NULL, v.price, v.price_label, 60, true
FROM public.salons s
CROSS JOIN (
  VALUES
    ('Жіноча стрижка + укладка', 'Перукарський зал', 350::numeric, 'від 350 грн'),
    ('Чоловіча стильна стрижка', 'Перукарський зал', 250::numeric, 'від 250 грн'),
    ('Дитяча стрижка (до 10 років)', 'Перукарський зал', 180::numeric, 'від 180 грн'),
    ('Плетіння коси (ексклюзив)', 'Перукарський зал', 150::numeric, 'від 150 грн'),
    ('Складне фарбування (Airtouch)', 'Перукарський зал', 1500::numeric, 'від 1500 грн'),
    ('Комбінований манікюр', 'Манікюр та педикюр', 250::numeric, '250 грн'),
    ('Манікюр + покриття гель-лаком', 'Манікюр та педикюр', 550::numeric, '550 грн'),
    ('Апаратний педикюр (комплекс)', 'Манікюр та педикюр', 650::numeric, '650 грн'),
    ('Дизайн нігтів (за 1 елемент)', 'Манікюр та педикюр', 30::numeric, 'від 30 грн'),
    ('Зняття чужого покриття', 'Манікюр та педикюр', 100::numeric, '100 грн'),
    ('Апаратна Ендосфера тіла', 'Косметологія та догляд', 800::numeric, 'від 800 грн'),
    ('Елос-епіляція (зона)', 'Косметологія та догляд', 400::numeric, 'від 400 грн'),
    ('Розслабляючий SPA-масаж', 'Косметологія та догляд', 700::numeric, '700 грн'),
    ('Турбо-солярій (за 1 хвилину)', 'Косметологія та догляд', 15::numeric, '15 грн')
) AS v(name, category, price, price_label)
WHERE s.slug = 'amulet'
ON CONFLICT DO NOTHING;
