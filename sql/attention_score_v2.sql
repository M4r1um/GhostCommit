-- attention score for open issues (0-100)
-- neglect (max 40) + importance (max 50), minus penalties
-- tiers are ranked within each repo
WITH parts AS (
    SELECT
        *,
        -- neglect
        -- max points at 180 days quiet
        round(least(inactive_days / 180.0, 1) * 20, 1)                    AS pts_inactive,
        CASE WHEN assignee_count = 0 THEN 10 ELSE 0 END                    AS pts_unassigned,
        CASE WHEN awaiting_triage AND NOT waiting_on_reporter THEN 10 ELSE 0 END AS pts_untriaged,
        -- importance
        CASE category
            WHEN 'Bug' THEN 20 WHEN 'Performance' THEN 15 WHEN 'Accessibility' THEN 15
            WHEN 'Feature / Enhancement' THEN 6 WHEN 'Documentation' THEN 3 ELSE 5 END
        + CASE WHEN is_accessibility AND category <> 'Accessibility' THEN 5 ELSE 0 END AS pts_type,
        CASE WHEN '|' || lower(coalesce(labels,'')) || '|' LIKE '%regression%' THEN 10 ELSE 0 END AS pts_regression,
        CASE WHEN severe_symptom THEN 10 ELSE 0 END                         AS pts_severe,
        round(least(ln(1 + reactions_total) / ln(51), 1) * 15
            + least(comments / 20.0, 1) * 5, 1)                           AS pts_demand,
        -- penalties
        CASE WHEN labeled_duplicate OR labeled_wont_fix THEN -30 ELSE 0 END AS pts_close_candidate,
        -- waiting on reporter
        CASE WHEN waiting_on_reporter THEN -15 ELSE 0 END                   AS pts_waiting,
        CASE WHEN minor_issue THEN -10 ELSE 0 END                           AS pts_minor
    FROM categorized
    WHERE state = 'open'
),
scored AS (
    SELECT *,
        greatest(0, least(100,
            pts_inactive + pts_unassigned + pts_untriaged
          + pts_type + pts_regression + pts_severe + pts_demand
          + pts_close_candidate + pts_waiting + pts_minor))  AS attention_score
    FROM parts
)
SELECT
    repo, number, title, category, category_source,
    round(attention_score, 1)                                             AS attention_score,
    CASE
        WHEN pts_close_candidate < 0 THEN 'Close candidate'
        WHEN waiting_on_reporter     THEN 'Waiting on reporter'
        WHEN percent_rank() OVER (PARTITION BY repo ORDER BY attention_score) >= 0.90 THEN 'Review first'
        WHEN percent_rank() OVER (PARTITION BY repo ORDER BY attention_score) >= 0.60 THEN 'Review soon'
        ELSE 'Monitor'
    END                                                                   AS tier,
    rank() OVER (PARTITION BY repo ORDER BY attention_score DESC)         AS rank_in_repo,
    concat_ws('; ',
        CASE WHEN inactive_days >= 180 THEN 'quiet ' || inactive_days || ' days' END,
        CASE WHEN pts_unassigned > 0 THEN 'unassigned' END,
        CASE WHEN pts_untriaged > 0 THEN 'never triaged' END,
        CASE WHEN category IN ('Bug','Performance','Accessibility') THEN lower(category) END,
        CASE WHEN pts_regression > 0 THEN 'regression' END,
        CASE WHEN pts_severe > 0 THEN 'crash/freeze/data loss' END,
        CASE WHEN waiting_on_reporter THEN 'waiting on reporter' END,
        CASE WHEN minor_issue THEN 'minor/cosmetic' END,
        CASE WHEN reactions_total >= 5 THEN reactions_total || ' reactions' END,
        CASE WHEN pts_close_candidate < 0 THEN 'labelled duplicate / won''t fix' END
    )                                                                     AS reasons,
    pts_inactive, pts_unassigned, pts_untriaged, pts_type, pts_regression, pts_severe, pts_demand, pts_close_candidate, pts_waiting, pts_minor,
    inactive_days, age_days, comments, reactions_total, labels, html_url
FROM scored
ORDER BY repo, attention_score DESC
