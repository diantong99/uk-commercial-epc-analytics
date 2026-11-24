-- UK Commercial EPC analytics | PostgreSQL
-- Requires the downloaded annual source tables raw.certificates_2021..2026
-- and raw.recommendations_2021..2026 to be loaded before running.
-- Execute in order on a dedicated project database. Several statements
-- recreate analytics tables; do NOT run against production data.
-- This is a processing script, not a database dump or raw dataset.

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS clean;
CREATE SCHEMA IF NOT EXISTS analytics;



CREATE OR REPLACE VIEW clean.certificates_all_records AS

SELECT '2021' AS year, COUNT(*) AS records
FROM raw.certificates_2021

UNION ALL

SELECT '2022', COUNT(*)
FROM raw.certificates_2022

UNION ALL

SELECT '2023', COUNT(*)
FROM raw.certificates_2023

UNION ALL

SELECT '2024', COUNT(*)
FROM raw.certificates_2024

UNION ALL

SELECT '2025', COUNT(*)
FROM raw.certificates_2025

UNION ALL

SELECT '2026', COUNT(*)
FROM raw.certificates_2026

ORDER BY year;


CREATE OR REPLACE VIEW clean.recommendations_all_records AS
SELECT '2021' AS year, COUNT(*) AS records
FROM raw.recommendations_2021

UNION ALL

SELECT '2022', COUNT(*)
FROM raw.recommendations_2022

UNION ALL

SELECT '2023', COUNT(*)
FROM raw.recommendations_2023

UNION ALL

SELECT '2024', COUNT(*)
FROM raw.recommendations_2024

UNION ALL

SELECT '2025', COUNT(*)
FROM raw.recommendations_2025

UNION ALL

SELECT '2026', COUNT(*)
FROM raw.recommendations_2026

ORDER BY year;



CREATE OR REPLACE VIEW clean.records_table AS
SELECT
    c.year,
    c.records AS certificates,
    r.records AS recommendations,
    ROUND(r.records * 1.0 / c.records, 2)
AS recommendations_per_certificate
FROM clean.certificates_all_records AS c
         JOIN clean.recommendations_all_records AS r
              ON c.year = r.year;









CREATE OR REPLACE VIEW clean.recommendations_all_full AS

SELECT
    certificate_number::TEXT AS certificate_number,
    related_certificate_number::TEXT AS related_certificate_number,
    recommendation_item::TEXT AS recommendation_item,
    payback_type::TEXT AS payback_type,
    recommendation_code::TEXT AS recommendation_code,
    recommendation::TEXT AS recommendation,
    2021 AS source_year
FROM raw.recommendations_2021

UNION ALL

SELECT
    certificate_number::TEXT,
    related_certificate_number::TEXT,
    recommendation_item::TEXT,
    payback_type::TEXT,
    recommendation_code::TEXT,
    recommendation::TEXT,
    2022
FROM raw.recommendations_2022

UNION ALL

SELECT
    certificate_number::TEXT,
    related_certificate_number::TEXT,
    recommendation_item::TEXT,
    payback_type::TEXT,
    recommendation_code::TEXT,
    recommendation::TEXT,
    2023
FROM raw.recommendations_2023

UNION ALL

SELECT
    certificate_number::TEXT,
    related_certificate_number::TEXT,
    recommendation_item::TEXT,
    payback_type::TEXT,
    recommendation_code::TEXT,
    recommendation::TEXT,
    2024
FROM raw.recommendations_2024

UNION ALL

SELECT
    certificate_number::TEXT,
    related_certificate_number::TEXT,
    recommendation_item::TEXT,
    payback_type::TEXT,
    recommendation_code::TEXT,
    recommendation::TEXT,
    2025
FROM raw.recommendations_2025

UNION ALL

SELECT
    certificate_number::TEXT,
    related_certificate_number::TEXT,
    recommendation_item::TEXT,
    payback_type::TEXT,
    recommendation_code::TEXT,
    recommendation::TEXT,
    2026
FROM raw.recommendations_2026;


-- Compatibility view used by analytics.recommendations below.
-- The canonical year-unioned recommendation records are defined above.
CREATE OR REPLACE VIEW clean.recommendations_all_text AS
SELECT * FROM clean.recommendations_all_full;



SELECT
    source_year,
    COUNT(*) AS total_records
FROM clean.recommendations_all_full
GROUP BY source_year
ORDER BY source_year;

SELECT *
FROM clean.recommendations_all_full
LIMIT 20;


SELECT
    COUNT(*) AS total_records,

    COUNT(*) FILTER (
        WHERE payback_type NOT IN
              ('SHORT', 'MEDIUM', 'LONG', 'OTHER')
            OR payback_type IS NULL
        ) AS invalid_payback,

    COUNT(*) FILTER (
        WHERE recommendation_code = 'USER'
        ) AS user_defined_records,

    COUNT(*) FILTER (
        WHERE (
                  recommendation_code NOT LIKE 'EPC-%'
                      AND recommendation_code <> 'USER'
                  )
            OR recommendation_code IS NULL
        ) AS unknown_codes

FROM clean.recommendations_all_full;






DO $$
    DECLARE
        cols TEXT;
        combined_sql TEXT := '';
        y INTEGER;
    BEGIN
        -- 找出不同年份数据类型不一致的字段
        WITH inconsistent_columns AS (
            SELECT column_name
            FROM information_schema.columns
            WHERE table_schema = 'raw'
              AND table_name IN (
                                 'certificates_2021',
                                 'certificates_2022',
                                 'certificates_2023',
                                 'certificates_2024',
                                 'certificates_2025',
                                 'certificates_2026'
                )
            GROUP BY column_name
            HAVING COUNT(DISTINCT udt_name) > 1
        )
        SELECT STRING_AGG(
                       CASE
                           WHEN i.column_name IS NOT NULL
                               THEN FORMAT('t.%I::TEXT AS %I',
                                           c.column_name, c.column_name)
                           ELSE FORMAT('t.%I', c.column_name)
                           END,
                       ', ' ORDER BY c.ordinal_position
               )
        INTO cols
        FROM information_schema.columns c
                 LEFT JOIN inconsistent_columns i
                           ON c.column_name = i.column_name
        WHERE c.table_schema = 'raw'
          AND c.table_name = 'certificates_2021';

        -- 将六年的数据合并
        FOR y IN 2021..2026 LOOP
                IF y > 2021 THEN
                    combined_sql := combined_sql || ' UNION ALL ';
                END IF;

                combined_sql := combined_sql || FORMAT(
                        'SELECT %s, %s AS source_year FROM raw.%I t',
                        cols,
                        y,
                        'certificates_' || y
                                                );
            END LOOP;

        EXECUTE
            'CREATE OR REPLACE VIEW clean.certificates_all_text AS '
                || combined_sql;
    END $$;


SELECT
    source_year,
    COUNT(*) AS total_records
FROM clean.certificates_all_text
GROUP BY source_year
ORDER BY source_year;


SELECT
    current_database(),
    to_regclass('clean.certificates_all_text'),
    to_regclass('clean.recommendations_all_text');


SELECT
    c.certificate_number,
    c.asset_rating_band,
    r.recommendation_item,
    r.recommendation_code,
    r.payback_type,
    r.recommendation
FROM clean.certificates_all_text c
         JOIN clean.recommendations_all_full r
              ON c.certificate_number = r.certificate_number
LIMIT 20;

SELECT
    certificate_number,
    COUNT(*) AS occurrences
FROM clean.certificates_all_text
GROUP BY certificate_number
HAVING COUNT(*) > 1
ORDER BY occurrences DESC
LIMIT 20;


-- Initial setup only
-- 1. 建立证书明细表
CREATE TABLE analytics.certificates AS
SELECT *
FROM clean.certificates_all_text;

-- 2. 建立改善建议明细表
CREATE TABLE analytics.recommendations AS
SELECT *
FROM clean.recommendations_all_text;


CREATE INDEX idx_certificates_number
    ON analytics.certificates (certificate_number);

CREATE INDEX idx_recommendations_number
    ON analytics.recommendations (certificate_number);

ANALYZE analytics.certificates;
ANALYZE analytics.recommendations;



SELECT
    COUNT(*) AS total_records,
    COUNT(DISTINCT certificate_number) AS unique_certificates,
    COUNT(*) FILTER (
        WHERE certificate_number IS NULL
        ) AS missing_certificate_numbers
FROM analytics.certificates;


SELECT
    COUNT(*) AS total_recommendations,
    COUNT(*) FILTER (
        WHERE c.certificate_number IS NOT NULL
        ) AS matched_recommendations,
    COUNT(*) FILTER (
        WHERE c.certificate_number IS NULL
        ) AS unmatched_recommendations
FROM analytics.recommendations r
         LEFT JOIN (
    SELECT DISTINCT certificate_number
    FROM analytics.certificates
    WHERE certificate_number IS NOT NULL
) c
                   ON r.certificate_number = c.certificate_number;





WITH classified AS (
    SELECT
        certificate_number,
        property_type,
        asset_rating_band,

        CASE
            WHEN property_type IN (
                                   'B1 Offices and Workshop businesses',
                                   'Offices and Workshop Businesses'
                )
                THEN 'Office & Workshop'

            WHEN property_type IN (
                                   'General Industrial and Special Industrial Groups',
                                   'B2 to B7 General Industrial and Special Industrial Groups'
                )
                THEN 'Industrial'

            WHEN property_type IN (
                                   'Storage or Distribution',
                                   'B8 Storage or Distribution'
                )
                THEN 'Warehouse'

            WHEN property_type IN (
                                   'A1/A2 Retail and Financial/Professional services',
                                   'Retail/Financial and Professional Services'
                )
                THEN 'Retail & Professional Services'

            WHEN property_type IN (
                                   'A3/A4/A5 Restaurant and Cafes/Drinking Establishments and Hot Food takeaways',
                                   'Restaurants and Cafes/Drinking Establishments/Takeaways'
                )
                THEN 'Hospitality'

            WHEN property_type IN ('C1 Hotels', 'Hotels')
                THEN 'Hotel'

            ELSE 'Other / Unmapped'
            END AS property_category

    FROM analytics.certificates
)

SELECT
    property_category,
    COUNT(*) AS total_certificates,

    COUNT(*) FILTER (
        WHERE asset_rating_band IN ('A','B','C','D','E','F','G')
        ) AS valid_rating_certificates,

    COUNT(*) FILTER (
        WHERE asset_rating_band IN ('F','G')
        ) AS low_rating_certificates,

    ROUND(
                    COUNT(*) FILTER (
                WHERE asset_rating_band IN ('F','G')
                ) * 100.0
                / NULLIF(
                                    COUNT(*) FILTER (
                                WHERE asset_rating_band IN
                                      ('A','B','C','D','E','F','G')
                                ), 0
                  ),
                    2
    ) AS low_rating_percentage

FROM classified
GROUP BY property_category
ORDER BY low_rating_percentage DESC NULLS LAST;










SELECT
    r.recommendation_code,
    r.recommendation,

    COUNT(*) AS recommendation_count,

    COUNT(DISTINCT c.certificate_number)
             AS affected_certificates

FROM analytics.certificates c

         JOIN analytics.recommendations r
              ON c.certificate_number = r.certificate_number

WHERE c.asset_rating_band IN ('F', 'G')
  AND c.property_type IN (
                          'B1 Offices and Workshop businesses',
                          'Offices and Workshop Businesses'
    )

GROUP BY
    r.recommendation_code,
    r.recommendation

ORDER BY affected_certificates DESC
LIMIT 20;






WITH classified AS (
    SELECT
        c.certificate_number,
        r.recommendation_code,
        r.payback_type,

        CASE
            WHEN r.recommendation_code = 'USER'
                THEN 'User-defined Recommendation'
            WHEN r.recommendation_code LIKE 'EPC-E%'
                THEN 'Building Envelope'
            WHEN r.recommendation_code LIKE 'EPC-H%'
                THEN 'Heating'
            WHEN r.recommendation_code LIKE 'EPC-L%'
                THEN 'Lighting'
            WHEN r.recommendation_code LIKE 'EPC-R%'
                THEN 'Renewable Energy'
            WHEN r.recommendation_code LIKE 'EPC-V%'
                THEN 'Ventilation / Solar Control'
            ELSE 'Other'
            END AS improvement_category
    FROM analytics.certificates c
             JOIN analytics.recommendations r
                  ON c.certificate_number = r.certificate_number
    WHERE c.asset_rating_band IN ('F', 'G')
      AND property_type IN (
                            'B1 Offices and Workshop businesses',
                            'Offices and Workshop Businesses'
        )
)
SELECT
    improvement_category,
    COUNT(*) AS total_recommendations,
    COUNT(DISTINCT certificate_number) AS affected_certificates,
    ROUND(
            COUNT(DISTINCT certificate_number) * 100.0 /
            NULLIF(
                    (
                        SELECT COUNT(DISTINCT certificate_number)
                        FROM analytics.certificates
                        WHERE asset_rating_band IN ('F', 'G')
                          AND property_type IN (
                                                'B1 Offices and Workshop businesses',
                                                'Offices and Workshop Businesses'
                            )
                    ), 0
            ),
            2
    ) AS affected_percentage
FROM classified
GROUP BY improvement_category
ORDER BY affected_certificates DESC;





SELECT
    recommendation,
    COUNT(*) AS records
FROM clean.recommendations_all_full
WHERE recommendation_code = 'USER'
GROUP BY recommendation
ORDER BY records DESC
LIMIT 20;

SELECT
    COUNT(*) AS total_user_records,

    COUNT(*) FILTER (
        WHERE recommendation IS NULL
            OR TRIM(recommendation) = ''
        ) AS empty_recommendations,

    COUNT(*) FILTER (
        WHERE LOWER(TRIM(recommendation))
            = 'insert recommendation here'
        ) AS placeholder_recommendations

FROM clean.recommendations_all_full
WHERE recommendation_code = 'USER';



WITH classified AS (
    SELECT
        c.certificate_number,
        c.asset_rating_band AS epc_rating,

        CASE
            WHEN r.recommendation_code = 'USER'
                THEN 'User-defined Recommendation'
            WHEN r.recommendation_code LIKE 'EPC-E%'
                THEN 'Building Envelope'
            WHEN r.recommendation_code LIKE 'EPC-H%'
                THEN 'Heating'
            WHEN r.recommendation_code LIKE 'EPC-L%'
                THEN 'Lighting'
            WHEN r.recommendation_code LIKE 'EPC-R%'
                THEN 'Renewable Energy'
            WHEN r.recommendation_code LIKE 'EPC-V%'
                THEN 'Ventilation / Solar Control'
            ELSE 'Other'
            END AS improvement_category

    FROM analytics.certificates c
             JOIN analytics.recommendations r
                  ON c.certificate_number = r.certificate_number

    WHERE c.property_type IN (
                              'B1 Offices and Workshop businesses',
                              'Offices and Workshop Businesses'
        )
      AND c.asset_rating_band IN ('A','B','C','D','E','F','G')
),

     category_counts AS (
         SELECT
             epc_rating,
             improvement_category,
             COUNT(DISTINCT certificate_number) AS affected_certificates
         FROM classified
         GROUP BY epc_rating, improvement_category
     ),

     group_totals AS (
         SELECT
             asset_rating_band AS epc_rating,
             COUNT(DISTINCT certificate_number) AS total_certificates

         FROM analytics.certificates

         WHERE property_type IN (
                                 'B1 Offices and Workshop businesses',
                                 'Offices and Workshop Businesses'
             )
           AND asset_rating_band IN ('A','B','C','D','E','F','G')

         GROUP BY asset_rating_band
     )

SELECT
    c.epc_rating,
    c.improvement_category,
    c.affected_certificates,
    t.total_certificates,

    ROUND(
            c.affected_certificates * 100.0
                / NULLIF(t.total_certificates, 0),
            2
    ) AS coverage_percentage

FROM category_counts c
         JOIN group_totals t
              ON c.epc_rating = t.epc_rating

ORDER BY
    c.improvement_category,
    c.epc_rating;





SELECT
    CASE
        WHEN r.recommendation_code = 'USER'
            THEN 'User-defined Recommendation'
        WHEN r.recommendation_code LIKE 'EPC-E%'
            THEN 'Building Envelope'
        WHEN r.recommendation_code LIKE 'EPC-H%'
            THEN 'Heating'
        WHEN r.recommendation_code LIKE 'EPC-L%'
            THEN 'Lighting'
        WHEN r.recommendation_code LIKE 'EPC-R%'
            THEN 'Renewable Energy'
        WHEN r.recommendation_code LIKE 'EPC-V%'
            THEN 'Ventilation / Solar Control'
        ELSE 'Other'
        END AS improvement_category,

    r.payback_type,
    COUNT(*) AS recommendation_count

FROM analytics.certificates c
         JOIN analytics.recommendations r
              ON c.certificate_number = r.certificate_number

WHERE c.asset_rating_band IN ('F', 'G')
  AND c.property_type IN (
                          'B1 Offices and Workshop businesses',
                          'Offices and Workshop Businesses'
    )

GROUP BY improvement_category, r.payback_type
ORDER BY improvement_category, recommendation_count DESC;





-- =====================================================
-- EPC Commercial Property Analytics
-- Save Exploratory Analysis Results
-- =====================================================

BEGIN;

-- 1. 年度数据量统计
DROP TABLE IF EXISTS analytics.stats_annual_records;

CREATE TABLE analytics.stats_annual_records AS
WITH c AS (
    SELECT
        source_year,
        COUNT(*) AS certificate_records
    FROM analytics.certificates
    GROUP BY source_year
),
     r AS (
         SELECT
             source_year,
             COUNT(*) AS recommendation_records
         FROM analytics.recommendations
         GROUP BY source_year
     )
SELECT
    c.source_year,
    c.certificate_records,
    r.recommendation_records,
    ROUND(
            r.recommendation_records * 1.0
                / NULLIF(c.certificate_records, 0),
            2
    ) AS recommendations_to_certificates_ratio
FROM c
         JOIN r USING (source_year);


-- 2. 原始物业类型统计
DROP TABLE IF EXISTS analytics.stats_property_types;

CREATE TABLE analytics.stats_property_types AS
SELECT
    property_type,
    COUNT(*) AS total_certificates,
    COUNT(*) FILTER (
        WHERE asset_rating_band IN
              ('A','B','C','D','E','F','G')
        ) AS valid_rating_certificates,
    COUNT(*) FILTER (
        WHERE asset_rating_band IN ('F','G')
        ) AS low_rating_certificates,
    ROUND(
                    COUNT(*) FILTER (
                WHERE asset_rating_band IN ('F','G')
                ) * 100.0
                / NULLIF(
                                    COUNT(*) FILTER (
                                WHERE asset_rating_band IN
                                      ('A','B','C','D','E','F','G')
                                ), 0
                  ),
                    2
    ) AS low_rating_percentage
FROM analytics.certificates
GROUP BY property_type;


-- 3. 标准化物业类别统计
DROP TABLE IF EXISTS analytics.stats_property_categories;

CREATE TABLE analytics.stats_property_categories AS
WITH classified AS (
    SELECT
        certificate_number,
        asset_rating_band,
        CASE
            WHEN property_type IN (
                                   'B1 Offices and Workshop businesses',
                                   'Offices and Workshop Businesses'
                )
                THEN 'Office & Workshop'

            WHEN property_type IN (
                                   'General Industrial and Special Industrial Groups',
                                   'B2 to B7 General Industrial and Special Industrial Groups'
                )
                THEN 'Industrial'

            WHEN property_type IN (
                                   'Storage or Distribution',
                                   'B8 Storage or Distribution'
                )
                THEN 'Warehouse'

            WHEN property_type IN (
                                   'A1/A2 Retail and Financial/Professional services',
                                   'Retail/Financial and Professional Services'
                )
                THEN 'Retail & Professional Services'

            WHEN property_type IN (
                                   'A3/A4/A5 Restaurant and Cafes/Drinking Establishments and Hot Food takeaways',
                                   'Restaurants and Cafes/Drinking Establishments/Takeaways'
                )
                THEN 'Hospitality'

            WHEN property_type IN ('C1 Hotels', 'Hotels')
                THEN 'Hotel'

            ELSE 'Other / Unmapped'
            END AS property_category
    FROM analytics.certificates
)
SELECT
    property_category,
    COUNT(*) AS total_certificates,
    COUNT(*) FILTER (
        WHERE asset_rating_band IN
              ('A','B','C','D','E','F','G')
        ) AS valid_rating_certificates,
    COUNT(*) FILTER (
        WHERE asset_rating_band IN ('F','G')
        ) AS low_rating_certificates,
    ROUND(
                    COUNT(*) FILTER (
                WHERE asset_rating_band IN ('F','G')
                ) * 100.0
                / NULLIF(
                                    COUNT(*) FILTER (
                                WHERE asset_rating_band IN
                                      ('A','B','C','D','E','F','G')
                                ), 0
                  ),
                    2
    ) AS low_rating_percentage
FROM classified
GROUP BY property_category;


-- 4. 创建共用的 Office & Workshop 建议分类视图
CREATE OR REPLACE VIEW analytics.v_office_recommendations AS
SELECT
    c.certificate_number,
    c.asset_rating_band AS epc_rating,
    r.recommendation_code,
    r.recommendation,
    r.payback_type,

    CASE
        WHEN r.recommendation_code = 'USER'
            THEN 'User-defined Recommendation'
        WHEN r.recommendation_code LIKE 'EPC-E%'
            THEN 'Building Envelope'
        WHEN r.recommendation_code LIKE 'EPC-H%'
            THEN 'Heating'
        WHEN r.recommendation_code LIKE 'EPC-L%'
            THEN 'Lighting'
        WHEN r.recommendation_code LIKE 'EPC-R%'
            THEN 'Renewable Energy'
        WHEN r.recommendation_code LIKE 'EPC-V%'
            THEN 'Ventilation / Solar Control'
        ELSE 'Other'
        END AS improvement_category

FROM analytics.certificates c
         JOIN analytics.recommendations r
              ON c.certificate_number = r.certificate_number
WHERE c.property_type IN (
                          'B1 Offices and Workshop businesses',
                          'Offices and Workshop Businesses'
    );


-- 5. F/G Office & Workshop Top 20 改善建议
DROP TABLE IF EXISTS analytics.stats_office_top20;

CREATE TABLE analytics.stats_office_top20 AS
SELECT
    recommendation_code,
    recommendation,
    COUNT(*) AS recommendation_count,
    COUNT(DISTINCT certificate_number)
             AS affected_certificates

FROM analytics.v_office_recommendations
WHERE epc_rating IN ('F','G')
GROUP BY recommendation_code, recommendation
ORDER BY affected_certificates DESC
LIMIT 20;


-- 6. F/G Office & Workshop 改善类别覆盖率
DROP TABLE IF EXISTS analytics.stats_office_fg_categories;

CREATE TABLE analytics.stats_office_fg_categories AS
SELECT
    improvement_category,
    COUNT(*) AS total_recommendations,
    COUNT(DISTINCT certificate_number)
             AS affected_certificates,

    ROUND(
            COUNT(DISTINCT certificate_number) * 100.0
                / NULLIF(
                    (
                        SELECT COUNT(DISTINCT certificate_number)
                        FROM analytics.certificates
                        WHERE asset_rating_band IN ('F','G')
                          AND property_type IN (
                                                'B1 Offices and Workshop businesses',
                                                'Offices and Workshop Businesses'
                            )
                    ), 0
                  ),
            2
    ) AS affected_percentage

FROM analytics.v_office_recommendations
WHERE epc_rating IN ('F','G')
GROUP BY improvement_category;


-- 7. Office & Workshop A-G 改善类别覆盖率
DROP TABLE IF EXISTS analytics.stats_office_rating_coverage;

CREATE TABLE analytics.stats_office_rating_coverage AS
WITH category_counts AS (
    SELECT
        epc_rating,
        improvement_category,
        COUNT(DISTINCT certificate_number)
            AS affected_certificates
    FROM analytics.v_office_recommendations
    WHERE epc_rating IN ('A','B','C','D','E','F','G')
    GROUP BY epc_rating, improvement_category
),
     group_totals AS (
         SELECT
             asset_rating_band AS epc_rating,
             COUNT(DISTINCT certificate_number)
                               AS total_certificates
         FROM analytics.certificates
         WHERE property_type IN (
                                 'B1 Offices and Workshop businesses',
                                 'Offices and Workshop Businesses'
             )
           AND asset_rating_band IN ('A','B','C','D','E','F','G')
         GROUP BY asset_rating_band
     )
SELECT
    c.epc_rating,
    c.improvement_category,
    c.affected_certificates,
    t.total_certificates,
    ROUND(
            c.affected_certificates * 100.0
                / NULLIF(t.total_certificates, 0),
            2
    ) AS coverage_percentage
FROM category_counts c
         JOIN group_totals t
              ON c.epc_rating = t.epc_rating;


-- 8. F/G Office & Workshop 回收期分布
DROP TABLE IF EXISTS analytics.stats_office_payback;

CREATE TABLE analytics.stats_office_payback AS
SELECT
    improvement_category,
    payback_type,
    COUNT(*) AS recommendation_count
FROM analytics.v_office_recommendations
WHERE epc_rating IN ('F','G')
GROUP BY improvement_category, payback_type;


-- 9. USER 自定义建议文本质量统计
DROP TABLE IF EXISTS analytics.stats_user_quality;

CREATE TABLE analytics.stats_user_quality AS
SELECT
    COUNT(*) AS total_user_records,

    COUNT(*) FILTER (
        WHERE recommendation IS NULL
            OR TRIM(recommendation) = ''
        ) AS empty_recommendations,

    COUNT(*) FILTER (
        WHERE LOWER(TRIM(recommendation))
            = 'insert recommendation here'
        ) AS placeholder_recommendations

FROM clean.recommendations_all_full
WHERE recommendation_code = 'USER';

COMMIT;



SELECT
    'Annual Records' AS analysis,
    COUNT(*) AS records
FROM analytics.stats_annual_records

UNION ALL
SELECT 'Property Types', COUNT(*)
FROM analytics.stats_property_types

UNION ALL
SELECT 'Property Categories', COUNT(*)
FROM analytics.stats_property_categories

UNION ALL
SELECT 'Office Top 20', COUNT(*)
FROM analytics.stats_office_top20

UNION ALL
SELECT 'Office F/G Categories', COUNT(*)
FROM analytics.stats_office_fg_categories

UNION ALL
SELECT 'Office Rating Coverage', COUNT(*)
FROM analytics.stats_office_rating_coverage

UNION ALL
SELECT 'Office Payback', COUNT(*)
FROM analytics.stats_office_payback

UNION ALL
SELECT 'USER Quality', COUNT(*)
FROM analytics.stats_user_quality;





-- Step 1: Create certificate-level ML dataset

DROP TABLE IF EXISTS analytics.ml_certificate_features;

CREATE TABLE analytics.ml_certificate_features AS

WITH recommendation_summary AS (
    SELECT
        certificate_number,

        COUNT(*) AS total_recommendations,

        COUNT(*) FILTER (
            WHERE payback_type = 'SHORT'
            ) AS short_count,

        COUNT(*) FILTER (
            WHERE payback_type = 'MEDIUM'
            ) AS medium_count,

        COUNT(*) FILTER (
            WHERE payback_type = 'LONG'
            ) AS long_count,

        COUNT(*) FILTER (
            WHERE payback_type = 'OTHER'
            ) AS other_count

    FROM analytics.recommendations
    GROUP BY certificate_number
)

SELECT
    c.certificate_number,
    c.property_type,
    c.asset_rating_band AS epc_rating,

    CASE c.asset_rating_band
        WHEN 'A' THEN 1
        WHEN 'B' THEN 2
        WHEN 'C' THEN 3
        WHEN 'D' THEN 4
        WHEN 'E' THEN 5
        WHEN 'F' THEN 6
        WHEN 'G' THEN 7
        END AS epc_rating_score,

    COALESCE(r.total_recommendations, 0)
                        AS total_recommendations,

    COALESCE(r.short_count, 0) AS short_count,
    COALESCE(r.medium_count, 0) AS medium_count,
    COALESCE(r.long_count, 0) AS long_count,
    COALESCE(r.other_count, 0) AS other_count,

    ROUND(
            COALESCE(r.short_count, 0) * 1.0
                / NULLIF(r.total_recommendations, 0),
            4
    ) AS short_ratio,

    ROUND(
            COALESCE(r.medium_count, 0) * 1.0
                / NULLIF(r.total_recommendations, 0),
            4
    ) AS medium_ratio,

    ROUND(
            COALESCE(r.long_count, 0) * 1.0
                / NULLIF(r.total_recommendations, 0),
            4
    ) AS long_ratio

FROM analytics.certificates c

         LEFT JOIN recommendation_summary r
                   ON c.certificate_number = r.certificate_number

WHERE c.asset_rating_band IN
      ('A','B','C','D','E','F','G');

CREATE INDEX idx_ml_certificate_number
    ON analytics.ml_certificate_features (certificate_number);

ANALYZE analytics.ml_certificate_features;



SELECT
    COUNT(*) AS total_records,

    COUNT(DISTINCT certificate_number)
             AS unique_certificates,

    COUNT(*) FILTER (
        WHERE total_recommendations = 0
        ) AS certificates_without_recommendations,

    ROUND(
            AVG(total_recommendations), 2
    ) AS avg_recommendations,

    MAX(total_recommendations)
             AS max_recommendations

FROM analytics.ml_certificate_features;



CREATE OR REPLACE VIEW analytics.ml_features_with_date AS
SELECT
    m.*,
    c.lodgement_date::DATE AS lodgement_date,
    c.source_year,
    c.uprn
FROM analytics.ml_certificate_features m
         JOIN analytics.certificates c
              ON m.certificate_number = c.certificate_number;



SELECT
    EXTRACT(YEAR FROM lodgement_date)::INT AS assessment_year,
    COUNT(*) AS certificates
FROM analytics.ml_features_with_date
GROUP BY assessment_year
ORDER BY assessment_year;


SELECT
    COUNT(*) AS total_records,
    COUNT(DISTINCT certificate_number) AS unique_certificates
FROM analytics.ml_features_with_date;

SELECT *
FROM analytics.ml_features_with_date;


