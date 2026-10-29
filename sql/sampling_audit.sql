-- check each repo/month was fully collected
SELECT
    c.repo,
    c.sample_month,
    CAST(c.population_reported AS INT)            AS population_reported,
    CAST(c.population_fetched  AS INT)            AS population_fetched,
    CAST(c.collected AS INT)                      AS collected,
    CAST(c.population_open AS INT)                AS population_open,
    round(100.0 * CAST(c.population_open AS INT) / nullif(CAST(c.population_fetched AS INT), 0), 1) AS open_pct,
    c.method,
    CASE
        WHEN CAST(c.population_reported AS INT) <> CAST(c.population_fetched AS INT) THEN 'CHECK: fetched count differs from GitHub total'
        WHEN CAST(c.population_fetched AS INT) < 30 THEN 'Too few issues to compare'
        ELSE 'OK'
    END AS status
FROM coverage c
ORDER BY c.repo, c.sample_month
