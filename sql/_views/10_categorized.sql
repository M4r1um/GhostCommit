-- main view: adds category, flags and day counts to each issue
-- category order: issue type > labels > title prefix > title keywords

CREATE OR REPLACE VIEW categorized AS
WITH base AS (
    SELECT
        *,
        '|' || lower(coalesce(labels, '')) || '|'   AS lbl,
        lower(trim(coalesce(title, '')))           AS t,
        lower(coalesce(issue_type, ''))            AS it,
        CAST(snapshot_at AS TIMESTAMP)             AS snap
    FROM issues
),
flags AS (
    SELECT
        *,
        -- from labels
        (lbl LIKE '%|bug|%' OR lbl LIKE '%|type: bug|%' OR lbl LIKE '%|regression|%'
         OR lbl LIKE '%|type: regression|%' OR lbl LIKE '%|confirmed bug|%')              AS l_bug,
        (lbl LIKE '%|feature-request|%' OR lbl LIKE '%|enhancement|%'
         OR lbl LIKE '%|type: enhancement|%' OR lbl LIKE '%|type: feature request|%'
         OR lbl LIKE '%|feature|%' OR lbl LIKE '%|new feature|%')                       AS l_feature,
        (lbl LIKE '%accessibility%' OR lbl LIKE '%|a11y|%')                              AS l_a11y,
        (lbl LIKE '%|docs|%' OR lbl LIKE '%|documentation|%' OR lbl LIKE '%|type: docs|%') AS l_docs,
        (lbl LIKE '%|performance|%' OR lbl LIKE '%|perf|%')                              AS l_perf,
        (lbl LIKE '%|*question|%' OR lbl LIKE '%|question|%' OR lbl LIKE '%|type: question|%'
         OR lbl LIKE '%|usage question|%' OR lbl LIKE '%|type: discussion|%')            AS l_question,
        -- from title prefixes
        (t LIKE 'bug:%' OR t LIKE 'bug %' OR t LIKE '[bug]%' OR t LIKE '%[devtools bug]%'
         OR t LIKE '%[compiler bug]%' OR t LIKE 'regression:%')  AS p_bug,
        (t LIKE 'enh:%' OR t LIKE 'enh %' OR t LIKE '[feature request]%' OR t LIKE 'feature request%'
         OR t LIKE 'feature:%' OR t LIKE '[feature]%' OR t LIKE '%[devtools feature request]%'
         OR t LIKE 'proposal:%' OR t LIKE 'rfc:%')                                       AS p_feature,
        (t LIKE 'doc:%' OR t LIKE 'docs:%' OR t LIKE '[docs]%')                          AS p_docs,
        (t LIKE 'perf:%')                                                                AS p_perf,
        (t LIKE 'qst:%' OR t LIKE 'question:%' OR t LIKE '[question]%')                  AS p_question,
        -- from title keywords
        regexp_matches(t, '\b(crash(es|ed|ing)?|error|exception|broken|fails?|failing|not working|doesn''t work|does not work|incorrect|wrong|unexpected|regression|hangs?|freez(e|es|ing)|memory leak)\b') AS k_bug,
        regexp_matches(t, '\b(add support|support for|allow|would be nice|feature|option to|ability to|request)\b') AS k_feature
    FROM base
)
SELECT
    repo, number, title, labels, issue_type, state, state_reason,
    CAST(created_at AS TIMESTAMP) AS created_at,
    CAST(updated_at AS TIMESTAMP) AS updated_at,
    TRY_CAST(closed_at AS TIMESTAMP) AS closed_at,
    comments, assignee_count, author_association, reactions_total,
    sample_month, sample_weight, html_url, snap AS snapshot_at,

    CASE
        WHEN it = 'bug'                                  THEN 'Bug'
        WHEN it IN ('feature', 'enhancement')            THEN 'Feature / Enhancement'
        WHEN it = 'task'                                 THEN 'Task'
        WHEN l_bug                                       THEN 'Bug'
        WHEN l_feature                                   THEN 'Feature / Enhancement'
        WHEN l_docs                                      THEN 'Documentation'
        WHEN l_perf                                      THEN 'Performance'
        WHEN l_a11y                                      THEN 'Accessibility'
        WHEN l_question                                  THEN 'Question / Support'
        WHEN p_bug                                       THEN 'Bug'
        WHEN p_feature                                   THEN 'Feature / Enhancement'
        WHEN p_docs                                      THEN 'Documentation'
        WHEN p_perf                                      THEN 'Performance'
        WHEN p_question                                  THEN 'Question / Support'
        WHEN k_bug AND NOT k_feature                     THEN 'Bug'
        WHEN k_feature AND NOT k_bug                     THEN 'Feature / Enhancement'
        ELSE 'Unclassified'
    END AS category,

    CASE
        WHEN it IN ('bug', 'feature', 'enhancement', 'task')                  THEN 'issue_type'
        WHEN l_bug OR l_feature OR l_docs OR l_perf OR l_a11y OR l_question   THEN 'label'
        WHEN p_bug OR p_feature OR p_docs OR p_perf OR p_question             THEN 'title_prefix'
        WHEN (k_bug AND NOT k_feature) OR (k_feature AND NOT k_bug)           THEN 'title_keyword'
        ELSE 'none'
    END AS category_source,

    -- flags (an issue can have more than one)
    (it = 'bug' OR l_bug OR p_bug)                         AS is_bug,
    (it IN ('feature','enhancement') OR l_feature OR p_feature) AS is_feature,
    l_a11y                                                 AS is_accessibility,
    (l_docs OR p_docs)                                     AS is_docs,
    (l_perf OR p_perf)                                     AS is_performance,
    -- closed without a fix
    (state = 'closed' AND state_reason IN ('not_planned', 'duplicate'))      AS closed_without_fix,
    (lbl LIKE '%|*duplicate|%' OR lbl LIKE '%|duplicate|%')                  AS labeled_duplicate,
    (lbl LIKE '%|*out-of-scope|%' OR lbl LIKE '%|*as-designed|%'
     OR lbl LIKE '%|wontfix|%' OR lbl LIKE '%|won''t fix|%' OR lbl LIKE '%|closing candidate|%') AS labeled_wont_fix,
    (lbl LIKE '%|needs triage|%' OR lbl LIKE '%|status: unconfirmed|%'
     OR lbl LIKE '%|triage-needed|%')                                         AS awaiting_triage,
    -- maintainer asked for more info
    (lbl LIKE '%|info-needed|%' OR lbl LIKE '%|needs info|%' OR lbl LIKE '%|status: needs more information|%'
     OR lbl LIKE '%|confirmation-pending|%' OR lbl LIKE '%|stale|%' OR lbl LIKE '%|resolution: stale|%') AS waiting_on_reporter,
    -- crashes, freezes, data loss
    (lbl LIKE '%freeze-slow-crash-leak%' OR lbl LIKE '%|crash|%' OR lbl LIKE '%data loss%'
     OR lbl LIKE '%|data-loss|%' OR lbl LIKE '%|important|%'
     OR regexp_matches(t, '\b(crash(es|ed|ing)?|freez(e|es|ing)|froze|hangs?|corrupt(s|ed|ion)?|data loss|lost (my|all)|delet(ed|es) (my|the|all)|memory leak)\b')) AS severe_symptom,
    -- small cosmetic stuff
    (lbl LIKE '%|polish|%' OR lbl LIKE '%|cosmetic|%' OR lbl LIKE '%|typo|%'
     OR regexp_matches(t, '\b(cosmetic|typo|minor|unimportant|visual(ly)?|misaligned|alignment|padding|spacing|wording)\b')) AS minor_issue,

    date_diff('day', CAST(created_at AS TIMESTAMP), snap)   AS age_days,
    date_diff('day', CAST(updated_at AS TIMESTAMP), snap)   AS inactive_days,
    CASE WHEN state = 'closed'
         THEN date_diff('hour', CAST(created_at AS TIMESTAMP), TRY_CAST(closed_at AS TIMESTAMP)) / 24.0
    END AS days_to_close
FROM flags
