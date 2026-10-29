-- summary by repo and issue type
-- fixed = closed as completed (not_planned/duplicate don't count)
SELECT
    repo,
    category,
    count(*)                                                                   AS issues,
    round(100.0 * avg(CASE WHEN state = 'closed' AND coalesce(state_reason,'') NOT IN ('not_planned','duplicate') THEN 1 ELSE 0 END), 1) AS pct_fixed,
    round(100.0 * avg(CASE WHEN closed_without_fix THEN 1 ELSE 0 END), 1)    AS pct_closed_no_fix,
    round(100.0 * avg(CASE WHEN state = 'open' THEN 1 ELSE 0 END), 1)        AS pct_still_open,
    round(median(CASE WHEN state = 'closed' AND coalesce(state_reason,'') NOT IN ('not_planned','duplicate') THEN days_to_close END), 1) AS median_days_to_fix,
    round(median(CASE WHEN state = 'open' THEN inactive_days END), 0)         AS median_inactive_days_open,
    round(100.0 * avg(CASE WHEN comments = 0 THEN 1 ELSE 0 END), 1)          AS pct_zero_comments
FROM categorized
WHERE category IN ('Bug', 'Feature / Enhancement')
GROUP BY repo, category
HAVING count(*) >= 20
ORDER BY repo, category
