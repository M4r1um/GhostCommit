-- pick 25 issues per repo to check categories by hand
-- fill in manual_category, save as data/category_audit_labeled.csv
WITH ranked AS (
    SELECT *,
        row_number() OVER (PARTITION BY repo, category_source
                           ORDER BY hash(repo || '#' || CAST(number AS VARCHAR))) AS rn,
        count(*) OVER (PARTITION BY repo, category_source) AS n_source
    FROM categorized
)
SELECT repo, number, title, labels, category AS predicted_category, category_source,
       '' AS manual_category, '' AS notes, html_url
FROM ranked
WHERE rn <= CASE category_source
                WHEN 'issue_type'    THEN 5
                WHEN 'label'         THEN 7
                WHEN 'title_prefix'  THEN 6
                WHEN 'title_keyword' THEN 4
                ELSE 3 END
ORDER BY repo, category_source, number
