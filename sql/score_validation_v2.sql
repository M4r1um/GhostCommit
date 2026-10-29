-- blind check: 5 'review first' + 5 'monitor' per repo, tier hidden
WITH picked AS (
    SELECT repo, number, title, html_url, tier,
           row_number() OVER (PARTITION BY repo, tier
                              ORDER BY hash('gc' || repo || CAST(number AS VARCHAR))) AS rn
    FROM read_csv_auto('data/attention_score_v2.csv')
    WHERE tier IN ('Review first', 'Monitor')
)
SELECT repo, number, title, html_url, '' AS deserves_attention, '' AS notes
FROM picked
WHERE rn <= 5
ORDER BY repo, hash('shuffle' || CAST(number AS VARCHAR))
