-- round 2: new issues not used in round 1
WITH seen AS (
    SELECT repo, CAST(number AS VARCHAR) AS number
    FROM read_csv_auto('data/score_validation_labeled.csv', all_varchar = true)
),
picked AS (
    SELECT s.repo, s.number, s.title, s.html_url, s.tier,
           row_number() OVER (PARTITION BY s.repo, s.tier
                              ORDER BY hash('round2' || s.repo || CAST(s.number AS VARCHAR))) AS rn
    FROM read_csv_auto('data/attention_score_v2.csv') s
    LEFT JOIN seen ON seen.repo = s.repo AND seen.number = CAST(s.number AS VARCHAR)
    WHERE s.tier IN ('Review first', 'Monitor') AND seen.number IS NULL
)
SELECT repo, number, title, html_url, '' AS deserves_attention, '' AS notes
FROM picked
WHERE rn <= 5
ORDER BY repo, hash('shuffle2' || CAST(number AS VARCHAR))
