-- ##01

DROP MATERIALIZED VIEW IF EXISTS mv_driver_season_summary;

CREATE MATERIALIZED VIEW mv_driver_season_summary AS
SELECT
    race.year,
    driver.id AS driver_id,
    driver.full_name AS driver_name,
    COUNT(*) AS total_races,
    COUNT(CASE WHEN race_data.position_number = 1 THEN 1 END) AS wins,
    COUNT(CASE WHEN race_data.position_number <= 3 THEN 1 END) AS podiums,
    COUNT(CASE WHEN race_data.race_reason_retired IS NOT NULL THEN 1 END) AS dnfs,
    SUM(COALESCE(race_data.race_points, 0)) AS total_points

FROM race_data
JOIN race ON race.id = race_data.race_id
JOIN driver ON driver.id = race_data.driver_id
WHERE race_data.type = 'RACE_RESULT'
GROUP BY race.year, driver.id, driver.full_name;


CREATE UNIQUE INDEX mv_driver_season_summary_year_driver_idx
    ON mv_driver_season_summary (year, driver_id);


REFRESH MATERIALIZED VIEW CONCURRENTLY mv_driver_season_summary;


-- Teste: 10 temporadas mais recentes de Ayrton Senna.
SELECT year, driver_name, total_races, wins, podiums, dnfs, total_points
FROM mv_driver_season_summary
WHERE driver_id = 'ayrton-senna'
ORDER BY year DESC
LIMIT 10;

--##02



--##03