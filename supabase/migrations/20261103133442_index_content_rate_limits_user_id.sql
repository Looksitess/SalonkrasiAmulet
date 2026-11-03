-- Index the user side of the content-rate-limit foreign key.
-- The primary key starts with salon_id, so it does not cover user_id lookups.
create index if not exists content_rate_limits_user_id_idx
on private.content_rate_limits (user_id);
