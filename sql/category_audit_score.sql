-- how often each rule matched my manual category
SELECT
    m.category_source,
    count(*)                                                              AS audited,
    sum(CASE WHEN lower(trim(m.manual_category)) = lower(trim(m.predicted_category)) THEN 1 ELSE 0 END) AS correct,
    round(100.0 * sum(CASE WHEN lower(trim(m.manual_category)) = lower(trim(m.predicted_category)) THEN 1 ELSE 0 END)
          / count(*), 1)                                                  AS precision_pct,
    string_agg(CASE WHEN lower(trim(m.manual_category)) <> lower(trim(m.predicted_category))
                    THEN m.repo || '#' || m.number || ' ' || m.predicted_category || '->' || m.manual_category END, ' | ') AS mismatches
FROM manual_audit m
WHERE trim(coalesce(m.manual_category, '')) <> ''
GROUP BY m.category_source
ORDER BY audited DESC
