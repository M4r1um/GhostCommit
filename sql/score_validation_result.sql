-- % of issues i marked yes, by tier
SELECT
    s.repo,
    s.tier,
    count(*)                                                              AS checked,
    sum(CASE WHEN lower(trim(v.deserves_attention)) = 'yes' THEN 1 ELSE 0 END) AS said_yes,
    round(100.0 * avg(CASE WHEN lower(trim(v.deserves_attention)) = 'yes' THEN 1 ELSE 0 END), 0) AS yes_pct
FROM read_csv_auto('data/score_validation_labeled.csv', all_varchar = true) v
JOIN read_csv_auto('data/attention_score_v2.csv') s
  ON s.repo = v.repo AND CAST(s.number AS VARCHAR) = v.number
WHERE trim(coalesce(v.deserves_attention, '')) <> ''
GROUP BY s.repo, s.tier
ORDER BY s.repo, s.tier
