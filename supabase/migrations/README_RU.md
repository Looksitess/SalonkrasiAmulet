# Важное замечание о миграциях Supabase

На production-проекте Supabase применено **45 миграций**. В этой папке на 3 ноября 2026 года сохранено **35 SQL-файлов**. Десять исходных SQL-файлов старых миграций отсутствуют в доступной истории GitHub:

- `20261028133855_secure_first_admin_invitation`
- `20261030200805_add_customer_reviews`
- `20261101120400_publish_reviews_immediately_and_admin_delete`
- `20261101123015_create_public_forum_with_admin_moderation`
- `20261101123221_lock_down_forum_trigger_permissions`
- `20261101123302_use_wall_clock_for_forum_topic_updates`
- `20261101123353_restrict_forum_table_privileges`
- `20261101140200_forum_reviews_interactions_and_moderation`
- `20261101140227_review_owner_and_admin_read_policies`
- `20261101140802_review_resubmission_and_updated_timestamps`

Последние добавленные миграции для service-aware расписания и защиты публичных авторских ID:

- `20261102191249_extend_service_aware_slot_grid_to_full_day.sql`
- `20261102191609_mask_public_author_ids_for_privacy.sql`
- `20261102191855_rate_limit_content_edits.sql`
- `20261102192319_bound_public_availability_date_window.sql`
- `20261102192624_compare_booking_intervals_as_timestamps.sql`
- `20261102193039_allow_new_auth_users_to_claim_admin_invites.sql`
- `20261103133442_index_content_rate_limits_user_id.sql`

## Что это значит

- Текущая production-база работает, потому что эти миграции уже применены к ней.
- Репозиторий не содержит полной воспроизводимой цепочки для создания идентичной базы с нуля.
- Не запускайте `supabase db reset` и не считайте новую чистую базу готовой только по содержимому этой папки.
- Не создавайте пустые SQL-заглушки под отсутствующими номерами: они не восстановят реальные типы, таблицы, политики, триггеры, функции и grants.
- Для полноценного восстановления требуется получить оригинальные SQL-файлы из старой резервной копии/истории автора или создать и проверить отдельный bootstrap snapshot текущей схемы на пустой временной базе.

## Правило для новых миграций

1. Применить миграцию к нужному проекту только после проверки SQL и влияния на текущие данные.
2. Сразу получить фактическую версию из Supabase `list_migrations`.
3. Сохранить SQL в GitHub под именем `<version>_<migration_name>.sql`.
4. Повторно сверить версию с файлом в GitHub.
5. Не менять старые уже применённые миграции.
