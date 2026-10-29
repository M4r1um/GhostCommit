-- data checks, problem columns should all be 0
SELECT
    repo,
    count(*)                                                        AS issues,
    count(*) - count(DISTINCT number)                               AS duplicate_numbers,
    sum(CASE WHEN state = 'closed' AND (closed_at IS NULL OR CAST(closed_at AS VARCHAR) = '') THEN 1 ELSE 0 END) AS closed_without_date,
    sum(CASE WHEN state = 'open' AND CAST(closed_at AS VARCHAR) <> '' THEN 1 ELSE 0 END)                       AS open_with_close_date,
    sum(CASE WHEN CAST(updated_at AS TIMESTAMP) < CAST(created_at AS TIMESTAMP) THEN 1 ELSE 0 END)            AS updated_before_created,
    sum(CASE WHEN state = 'closed' AND coalesce(state_reason, '') = '' THEN 1 ELSE 0 END)                      AS closed_no_reason_info,
    min(CAST(created_at AS TIMESTAMP))                              AS earliest_created,
    max(CAST(created_at AS TIMESTAMP))                              AS latest_created,
    min(snapshot_at)                                                AS snapshot_at
FROM issues
GROUP BY repo
ORDER BY repo
