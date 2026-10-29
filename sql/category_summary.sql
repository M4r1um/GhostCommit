-- issue counts by repo, category and where the category came from
SELECT
    repo,
    category,
    category_source,
    count(*)                                                  AS issues,
    CAST(sum(CASE WHEN state = 'open' THEN 1 ELSE 0 END) AS INT) AS open,
    round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY repo), 1) AS pct_of_repo,
    round(sum(sample_weight), 0)                              AS est_population
FROM categorized
GROUP BY repo, category, category_source
ORDER BY repo, issues DESC
