/*
COVID-19 Data Exploration — SQL Server (T-SQL)

Expected tables in the PortfolioProject database:
  dbo.CovidDeaths
  dbo.CovidVaccinations

This script explores reported cases, deaths, and vaccination doses.
It fixes integer division, protects against division by zero, and labels
vaccination totals as doses (not unique people).
*/

USE PortfolioProject;
GO

-- 1. Inspect the source data
SELECT TOP (100) *
FROM dbo.CovidDeaths
WHERE continent IS NOT NULL
ORDER BY location, date;
GO

-- 2. Select the columns used in this analysis
SELECT location, date, total_cases, new_cases, total_deaths, population
FROM dbo.CovidDeaths
WHERE continent IS NOT NULL
ORDER BY location, date;
GO

-- 3. Reported deaths as a percentage of reported cases for the United States
-- This is a ratio of reported cumulative counts, not an individual's risk.
SELECT
    location,
    date,
    total_cases,
    total_deaths,
    100.0 * TRY_CONVERT(decimal(20, 2), total_deaths)
        / NULLIF(TRY_CONVERT(decimal(20, 2), total_cases), 0) AS deaths_to_cases_percent
FROM dbo.CovidDeaths
WHERE location = 'United States'
  AND continent IS NOT NULL
ORDER BY date;
GO

-- 4. Reported cumulative cases as a percentage of population over time
SELECT
    location,
    date,
    population,
    total_cases,
    100.0 * TRY_CONVERT(decimal(20, 2), total_cases)
        / NULLIF(TRY_CONVERT(decimal(20, 2), population), 0) AS reported_cases_per_100_people
FROM dbo.CovidDeaths
WHERE continent IS NOT NULL
ORDER BY location, date;
GO

-- 5. Highest reported infection count and cases per 100 people by country
SELECT
    location,
    MAX(TRY_CONVERT(bigint, population)) AS population,
    MAX(TRY_CONVERT(bigint, total_cases)) AS highest_reported_cases,
    100.0 * MAX(TRY_CONVERT(decimal(20, 2), total_cases))
        / NULLIF(MAX(TRY_CONVERT(decimal(20, 2), population)), 0)
        AS highest_reported_cases_per_100_people
FROM dbo.CovidDeaths
WHERE continent IS NOT NULL
GROUP BY location
ORDER BY highest_reported_cases_per_100_people DESC;
GO

-- 6. Highest reported death count by country
SELECT
    location,
    MAX(TRY_CONVERT(bigint, total_deaths)) AS highest_reported_deaths
FROM dbo.CovidDeaths
WHERE continent IS NOT NULL
GROUP BY location
ORDER BY highest_reported_deaths DESC;
GO

-- 7. Approximate reported death count by continent.
-- First take each country's highest cumulative count, then sum countries.
WITH CountryDeaths AS (
    SELECT
        continent,
        location,
        MAX(TRY_CONVERT(bigint, total_deaths)) AS highest_reported_deaths
    FROM dbo.CovidDeaths
    WHERE continent IS NOT NULL
    GROUP BY continent, location
)
SELECT continent, SUM(highest_reported_deaths) AS summed_country_reported_deaths
FROM CountryDeaths
GROUP BY continent
ORDER BY summed_country_reported_deaths DESC;
GO

-- 8. Global reported cases, deaths, and deaths-to-cases ratio
SELECT
    SUM(TRY_CONVERT(decimal(20, 2), new_cases)) AS total_reported_new_cases,
    SUM(TRY_CONVERT(decimal(20, 2), new_deaths)) AS total_reported_new_deaths,
    100.0 * SUM(TRY_CONVERT(decimal(20, 2), new_deaths))
        / NULLIF(SUM(TRY_CONVERT(decimal(20, 2), new_cases)), 0)
        AS reported_deaths_to_cases_percent
FROM dbo.CovidDeaths
WHERE continent IS NOT NULL;
GO

-- 9. Vaccination data: running sum of reported new doses by country
-- New vaccinations count doses; they do not necessarily count unique people.
SELECT
    dea.continent,
    dea.location,
    dea.date,
    dea.population,
    vac.new_vaccinations,
    SUM(COALESCE(TRY_CONVERT(bigint, vac.new_vaccinations), 0)) OVER (
        PARTITION BY dea.location
        ORDER BY dea.date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS rolling_reported_vaccination_doses,
    100.0 * SUM(COALESCE(TRY_CONVERT(decimal(20, 2), vac.new_vaccinations), 0)) OVER (
        PARTITION BY dea.location
        ORDER BY dea.date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) / NULLIF(TRY_CONVERT(decimal(20, 2), dea.population), 0)
        AS rolling_doses_per_100_people
FROM dbo.CovidDeaths AS dea
INNER JOIN dbo.CovidVaccinations AS vac
    ON dea.location = vac.location
   AND dea.date = vac.date
WHERE dea.continent IS NOT NULL
ORDER BY dea.location, dea.date;
GO

-- 10. CTE version of the vaccination calculation
WITH PopulationVsVaccinationDoses AS (
    SELECT
        dea.continent,
        dea.location,
        dea.date,
        dea.population,
        vac.new_vaccinations,
        SUM(COALESCE(TRY_CONVERT(bigint, vac.new_vaccinations), 0)) OVER (
            PARTITION BY dea.location
            ORDER BY dea.date
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS rolling_reported_vaccination_doses
    FROM dbo.CovidDeaths AS dea
    INNER JOIN dbo.CovidVaccinations AS vac
        ON dea.location = vac.location
       AND dea.date = vac.date
    WHERE dea.continent IS NOT NULL
)
SELECT
    *,
    100.0 * rolling_reported_vaccination_doses
        / NULLIF(TRY_CONVERT(decimal(20, 2), population), 0)
        AS rolling_doses_per_100_people
FROM PopulationVsVaccinationDoses
ORDER BY location, date;
GO

-- 11. Temporary table version
DROP TABLE IF EXISTS #PercentPopulationVaccinated;

CREATE TABLE #PercentPopulationVaccinated (
    continent nvarchar(255),
    location nvarchar(255),
    date date,
    population bigint,
    new_vaccinations bigint,
    rolling_reported_vaccination_doses bigint
);

INSERT INTO #PercentPopulationVaccinated (
    continent, location, date, population, new_vaccinations,
    rolling_reported_vaccination_doses
)
SELECT
    dea.continent,
    dea.location,
    dea.date,
    TRY_CONVERT(bigint, dea.population),
    TRY_CONVERT(bigint, vac.new_vaccinations),
    SUM(COALESCE(TRY_CONVERT(bigint, vac.new_vaccinations), 0)) OVER (
        PARTITION BY dea.location
        ORDER BY dea.date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )
FROM dbo.CovidDeaths AS dea
INNER JOIN dbo.CovidVaccinations AS vac
    ON dea.location = vac.location
   AND dea.date = vac.date
WHERE dea.continent IS NOT NULL;

SELECT
    *,
    100.0 * rolling_reported_vaccination_doses
        / NULLIF(TRY_CONVERT(decimal(20, 2), population), 0)
        AS rolling_doses_per_100_people
FROM #PercentPopulationVaccinated
ORDER BY location, date;
GO

-- 12. View for reuse in later analysis or visualization
CREATE OR ALTER VIEW dbo.PercentPopulationVaccinated AS
SELECT
    dea.continent,
    dea.location,
    dea.date,
    dea.population,
    vac.new_vaccinations,
    SUM(COALESCE(TRY_CONVERT(bigint, vac.new_vaccinations), 0)) OVER (
        PARTITION BY dea.location
        ORDER BY dea.date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS rolling_reported_vaccination_doses
FROM dbo.CovidDeaths AS dea
INNER JOIN dbo.CovidVaccinations AS vac
    ON dea.location = vac.location
   AND dea.date = vac.date
WHERE dea.continent IS NOT NULL;
GO

SELECT
    *,
    100.0 * rolling_reported_vaccination_doses
        / NULLIF(TRY_CONVERT(decimal(20, 2), population), 0)
        AS rolling_doses_per_100_people
FROM dbo.PercentPopulationVaccinated
ORDER BY location, date;
GO

