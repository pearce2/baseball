/* this query computes fielding Win Shares according to the Bill James 1987-forward formulas */

/* Step 0: Drop any existing temp tables */
DROP TABLE IF EXISTS temp_yr_lg_tm_bat_totals; 
DROP TABLE IF EXISTS temp_yr_lg_tm_pit_totals; 
DROP TABLE IF EXISTS temp_yr_lg_tm_fld_totals;
DROP TABLE IF EXISTS temp_yr_lg_tm_misc_totals;
DROP TABLE IF EXISTS temp_yr_lg_tm_park_stats;
DROP TABLE IF EXISTS temp_yr_lg_tm_park_factors;
DROP TABLE IF EXISTS temp_yr_lg_totals;
DROP TABLE IF EXISTS temp_yr_lg_position_fielding;
DROP TABLE IF EXISTS temp_yr_lg_factors;
DROP TABLE IF EXISTS temp_yr_lg_tm_position_fielding;
DROP TABLE IF EXISTS temp_win_shares_factors_stage_1;
DROP TABLE IF EXISTS temp_win_shares_factors_stage_2;
DROP TABLE IF EXISTS temp_win_shares_factors_stage_3;
DROP TABLE IF EXISTS temp_yr_lg_tm_pos_claim_points;

/* Step 1: Compute Year/League/Team Batting, Pitching, Fielding, and Miscellaneous Totals */

CREATE TABLE temp_yr_lg_tm_bat_totals AS
SELECT
	Year
	, Lg
	, Tm
	, SUM(AB) AS AB
	, SUM(R) AS R
	, SUM(H) AS H
	, SUM(`2B`) AS `2B`
	, SUM(`3B`) AS `3B`
	, SUM(HR) AS HR
	, SUM(BB) AS BB
	, SUM(SO) AS SO
	, SUM(HBP) AS HBP
	, SUM(SH) AS SH
	, SUM(SF) AS SF
	, SUM(SB) AS SB
	, SUM(CS) AS CS
FROM bbref_batting_standard
WHERE Tm <> 'TOT'
GROUP BY Year, Lg, Tm
;

CREATE TABLE temp_yr_lg_tm_pit_totals AS
SELECT 
	pit.Year
	, pit.Lg
	, pit.Tm
	, SUM(pit.W) AS W
	, SUM(pit.L) AS L
	, SUM(pit.W)/(SUM(CAST(pit.W AS FLOAT)) + SUM(pit.L)) AS WPCT
	, SUM(pit.BF) AS BF
	, SUM(CASE WHEN RIGHT(pit.IP,2) = '.1' THEN IP + 0.23 WHEN RIGHT(pit.IP,2) = '.2' THEN IP + 0.47 ELSE IP END) AS IP
	, SUM(pit.H) AS H
	, SUM(pit.R) AS R
	, SUM(pit.ER) AS ER
	, SUM(pit.HR) AS HR
	, sac.SH AS SH
	, sac.SF AS SF
	, SUM(COALESCE(pit.HBP, 0)) AS HBP
	, SUM(pit.BB) AS BB
	, SUM(pit.SO) AS SO
	, SUM(pit.WP) AS WP
	, SUM(pit.BK) AS BK
	, SUM(CASE 
			WHEN RIGHT(pit.Name, 1) = '*' THEN
				CASE WHEN RIGHT(pit.IP,2) = '.1' THEN IP + 0.23 
				WHEN RIGHT(pit.IP,2) = '.2' THEN IP + 0.47 
				ELSE IP END
			ELSE 0 END) AS IP_LHP
	, SUM(CASE WHEN RIGHT(pit.Name, 1) = '*' THEN pit.SO ELSE 0 END) AS SO_LHP
FROM bbref_pitching_standard pit
JOIN 
	(
	SELECT Year, Lg, Tm, SUM(SH) AS SH, SUM(SF) AS SF FROM
		(
		SELECT 
			LEFT(gl.YYYYMMDD, 4) AS Year
			, gl.HomLeague AS Lg
			, t.teamIDbr AS Tm
			, SUM(CASE WHEN gl.VisSH IS NULL THEN 0 WHEN gl.VisSH < 0 THEN 0 ELSE gl.VisSH END) AS SH
			, SUM(CASE WHEN gl.VisSF IS NULL THEN 0 WHEN gl.VisSF < 0 THEN 0 ELSE gl.VisSF END) AS SF
		FROM Retrosheet_GameLogs gl
		JOIN Chadwick_Teams t ON LEFT(gl.YYYYMMDD, 4) = t.yearID AND gl.HomLeague = t.lgID AND gl.HomTeam = t.teamIDretro
		GROUP BY LEFT(gl.YYYYMMDD, 4), gl.HomLeague, t.teamIDBR
		UNION ALL
		SELECT 
			LEFT(gl.YYYYMMDD, 4) AS YEAR 
			, gl.VisLeague AS Lg
			, t.teamIDbr AS Tm
			, SUM(CASE WHEN gl.HomSH IS NULL THEN 0 WHEN gl.HomSH < 0 THEN 0 ELSE gl.HomSH END) AS SH
			, SUM(CASE WHEN gl.HomSF IS NULL THEN 0 WHEN gl.HomSF < 0 THEN 0 ELSE gl.HomSF END) AS SF
		FROM Retrosheet_GameLogs gl
		JOIN Chadwick_Teams t ON LEFT(gl.YYYYMMDD, 4) = t.yearID AND gl.VisLeague = t.lgID AND gl.VisTeam = t.teamIDretro
		GROUP BY LEFT(gl.YYYYMMDD, 4), gl.VisLeague, t.teamIDBR 
		) a
	GROUP BY Year, Lg, Tm
	) sac ON pit.Year = sac.Year AND pit.Lg = sac.Lg AND pit.Tm = sac.Tm
GROUP BY pit.Year, pit.Lg, pit.Tm, sac.SH, sac.SF
;


CREATE TABLE temp_yr_lg_tm_fld_totals AS
WITH p AS (SELECT year, lg, tm, SUM(po) AS po, SUM(a) AS a, SUM(e) AS e, 0 AS PB, 0 AS DP FROM bbref_fielding_p GROUP BY year, lg, tm)
	, c AS (SELECT year, lg, tm, SUM(po) AS po, SUM(a) AS a, SUM(e) AS e, SUM(pb) AS PB, 0 AS DP FROM bbref_fielding_c GROUP BY year, lg, tm)
    , fb AS (SELECT year, lg, tm, SUM(po) AS po, SUM(a) AS a, SUM(e) AS e, 0 AS PB, 0 AS DP FROM bbref_fielding_1b GROUP BY year, lg, tm)
    , sb AS (SELECT year, lg, tm, SUM(po) AS po, SUM(a) AS a, SUM(e) AS e, 0 AS PB, 0 AS DP FROM bbref_fielding_2b GROUP BY year, lg, tm)
    , tb AS (SELECT year, lg, tm, SUM(po) AS po, SUM(a) AS a, SUM(e) AS e, 0 AS PB, 0 AS DP FROM bbref_fielding_3b GROUP BY year, lg, tm)
    , ss AS (SELECT year, lg, tm, SUM(po) AS po, SUM(a) AS a, SUM(e) AS e, 0 AS PB, 0 AS DP FROM bbref_fielding_ss GROUP BY year, lg, tm)
    , oof AS (SELECT year, lg, tm, SUM(po) AS po, SUM(a) AS a, SUM(e) AS e, 0 AS PB, 0 AS DP FROM bbref_fielding_of GROUP BY year, lg, tm)
    , home_dp as 
    	(
		SELECT 
			LEFT(gl.YYYYMMDD, 4) AS Year
			, gl.HomLeague AS Lg
			, t.teamIDbr AS Tm
			, SUM(CASE WHEN gl.HomDP IS NULL THEN 0 WHEN gl.HomDP < 0 THEN 0 ELSE gl.HomDP END) AS DP
		FROM Retrosheet_GameLogs gl
		JOIN Chadwick_Teams t ON LEFT(gl.YYYYMMDD, 4) = t.yearID AND gl.HomLeague = t.lgID AND gl.HomTeam = t.teamIDretro
		GROUP BY LEFT(gl.YYYYMMDD, 4), gl.HomLeague, t.teamIDBR
		), away_dp as 
        (
		SELECT 
			LEFT(gl.YYYYMMDD, 4) AS YEAR 
			, gl.VisLeague AS Lg
			, t.teamIDbr AS Tm
			, SUM(CASE WHEN gl.VisDP IS NULL THEN 0 WHEN gl.VisDP < 0 THEN 0 ELSE gl.VisDP END) AS DP
		FROM Retrosheet_GameLogs gl
		JOIN Chadwick_Teams t ON LEFT(gl.YYYYMMDD, 4) = t.yearID AND gl.VisLeague = t.lgID AND gl.VisTeam = t.teamIDretro
		GROUP BY LEFT(gl.YYYYMMDD, 4), gl.VisLeague, t.teamIDBR
        )
SELECT 
	p.Year
    , p.lg
    , p.tm
    , SUM(p.po) + SUM(c.po) + SUM(fb.po) + SUM(sb.po) + SUM(tb.po) + SUM(ss.po) + SUM(oof.po) AS po
    , SUM(p.a) + SUM(c.a) + SUM(fb.a) + SUM(sb.a) + SUM(tb.a) + SUM(ss.a) + SUM(oof.a) AS a
    , SUM(p.e) + SUM(c.e) + SUM(fb.e)  + SUM(sb.e)  + SUM(tb.e)  + SUM(ss.e)  + SUM(oof.e) AS e
    , SUM(c.pb) AS pb
    , SUM(home_dp.dp + away_dp.dp) AS dp 
FROM p
JOIN c ON p.year = c.year AND p.lg = c.lg AND p.tm = c.tm
JOIN fb ON c.year = fb.year AND c.lg = fb.lg AND c.tm = fb.tm
JOIN sb ON fb.year = sb.year AND fb.lg = sb.lg AND fb.tm = sb.tm
JOIN tb ON sb.year = tb.year AND sb.lg = tb.lg AND sb.tm = tb.tm
JOIN ss ON tb.year = ss.year AND tb.lg = ss.lg AND tb.tm = ss.tm
JOIN oof ON ss.year = oof.year AND ss.lg = oof.lg AND ss.tm = oof.tm
JOIN home_dp ON oof.Year = home_dp.Year AND oof.Lg = home_dp.lg AND oof.tm = home_dp.tm
JOIN away_dp ON away_dp.Year = home_dp.Year AND away_dp.Lg = home_dp.lg AND away_dp.tm = home_dp.tm
WHERE p.tm <> 'TOT'
GROUP BY p.Year, p.lg, p.tm
ORDER BY p.Year, p.lg, p.tm
;




/* Compute home wins and road losses */

CREATE TABLE temp_yr_lg_tm_misc_totals AS
WITH w_home AS 
	(
    SELECT LEFT(gl.YYYYMMDD, 4) AS Year, gl.HomLeague AS lg, t.teamIDbr AS tm, SUM(CASE WHEN gl.HomScore > gl.VisScore THEN 1 ELSE 0 END) AS w_home
    FROM Retrosheet_GameLogs gl
	LEFT JOIN chadwick_teams t ON LEFT(gl.YYYYMMDD, 4) = t.yearID AND gl.HomLeague = t.lgID AND gl.HomTeam = t.teamIDretro
    GROUP BY LEFT(gl.YYYYMMDD, 4), gl.HomLeague, t.teamIDbr 
    ), 
    l_road AS
    (
    SELECT LEFT(gl.YYYYMMDD, 4) AS Year, gl.HomLeague AS lg, t.teamIDbr AS tm, SUM(CASE WHEN gl.HomScore > gl.VisScore THEN 1 ELSE 0 END) AS l_road
    FROM Retrosheet_GameLogs gl
	LEFT JOIN chadwick_teams t ON LEFT(gl.YYYYMMDD, 4) = t.yearID AND gl.VisLeague = t.lgID AND gl.VisTeam = t.teamIDretro
    GROUP BY LEFT(gl.YYYYMMDD, 4), gl.HomLeague, t.teamIDbr 
    )    
SELECT 
	w.year
	, w.lg
	, w.tm
	, w.w_home AS W_HOME
	, l.l_road AS L_ROAD
FROM w_home w
JOIN l_road l ON w.year = l.year AND w.lg = l.lg AND w.tm = l.tm
order by year, lg, tm
;

/* Compute Park Factors */

CREATE TABLE temp_yr_lg_tm_park_stats AS
WITH home AS
	(
    SELECT
		LEFT(gl.YYYYMMDD, 4) as yearID
        , gl.HomLeague AS Lg
        , gl.HomTeam as Tm
        , COUNT(*) AS games
        , SUM(gl.HomScore) + SUM(gl.VisScore) AS runs
        , SUM(gl.HomHR) + SUM(gl.VisHR) AS hr
	FROM retrosheet_gamelogs gl
    GROUP BY LEFT(gl.YYYYMMDD, 4), gl.HomLeague, gl.HomTeam, gl.ParkID
    ), road AS
    (
    SELECT
		LEFT(gl.YYYYMMDD, 4) as yearID
        , gl.VisLeague AS Lg
        , gl.VisTeam AS Tm
        , COUNT(*) AS games
        , SUM(gl.HomScore) + SUM(gl.VisScore) AS runs
        , SUM(gl.HomHR) + SUM(gl.VisHR) AS hr
	FROM retrosheet_gamelogs gl
    GROUP BY LEFT(gl.YYYYMMDD, 4), gl.VisLeague, gl.VisTeam
	)
SELECT
	IFNULL(home.yearID, road.YearID) AS yearID
	, IFNULL(home.Lg, road.Lg) AS Lg
	, IFNULL(home.Tm, road.Tm) AS Tm
	, SUM(IFNULL(home.games, 0)) AS games_home
	, SUM(IFNULL(home.runs, 0)) AS runs_home
	, SUM(IFNULL(home.hr, 0)) AS hr_home
	, IFNULL(road.games, 0) AS games_road
	, IFNULL(road.runs, 0) AS runs_road
	, IFNULL(road.hr, 0) AS hr_road
FROM home
LEFT JOIN road ON home.yearID = road.yearID AND home.lg = road.lg AND home.tm = road.tm
GROUP BY home.yearID, road.YearID, home.Lg, road.Lg, home.Tm, road.Tm, road.games, road.runs, road.hr
ORDER BY Tm, Lg, YearID
;


-- Now compute the park factors    
CREATE TABLE temp_yr_lg_tm_park_factors AS
WITH years_ext AS 
	(
    SELECT
		base.year AS year_base
		, base.parkID 
        , base.retrotm
        , base.lg
        , ext.year AS years_ext
	FROM seamheads_parkconfig base
    LEFT JOIN seamheads_parkconfig ext ON base.Year <> ext.year AND base.parkID = ext.parkID AND base.year BETWEEN ext.year - 2 AND ext.year + 2
		AND base.LF_Dim = ext.LF_Dim AND base.CF_Dim = ext.CF_Dim AND base.RF_Dim = ext.RF_Dim AND base.LF_W = ext.LF_W AND base.CF_W = ext.CF_W AND base.RF_W = ext.RF_W
    ), home AS
	(
    SELECT
		LEFT(gl.YYYYMMDD, 4) as yearID
        , gl.HomLeague AS Lg
        , gl.HomTeam as Tm
        , COUNT(*) AS games
        , SUM(gl.HomScore) + SUM(gl.VisScore) AS runs
        , SUM(gl.HomHR) + SUM(gl.VisHR) AS hr
	FROM retrosheet_gamelogs gl
    GROUP BY LEFT(gl.YYYYMMDD, 4), gl.HomLeague, gl.HomTeam
    ), road AS
    (
    SELECT
		LEFT(gl.YYYYMMDD, 4) as yearID
        , gl.VisLeague AS Lg
        , gl.VisTeam AS Tm
        , COUNT(*) AS games
        , SUM(gl.HomScore) + SUM(gl.VisScore) AS runs
        , SUM(gl.HomHR) + SUM(gl.VisHR) AS hr
	FROM retrosheet_gamelogs gl
    GROUP BY LEFT(gl.YYYYMMDD, 4), gl.VisLeague, gl.VisTeam
	), stats_ext AS 
    ( 
	SELECT
		IFNULL(home.yearID, road.YearID) AS yearID
		, IFNULL(home.Lg, road.Lg) AS Lg
		, IFNULL(home.Tm, road.Tm) AS Tm
		, IFNULL(home.games, 0) AS games_home
		, IFNULL(home.runs, 0) AS runs_home
		, IFNULL(home.hr, 0) AS hr_home
		, IFNULL(road.games, 0) AS games_road
		, IFNULL(road.runs, 0) AS runs_road
		, IFNULL(road.hr, 0) AS hr_road
	FROM home
	LEFT JOIN road ON home.yearID = road.yearID AND home.lg = road.lg AND home.tm = road.tm
	)
SELECT  
	stats.YearID
    , stats.Lg
    , stats.Tm
    , home.games AS games_home
    , CASE 
		WHEN stats.YearID < 1909 THEN ((stats.runs_home + 100) / (stats.games_home + 10)) / ((stats.runs_road + 100) / (stats.games_road + 10))
        WHEN (SELECT COUNT(*) FROM years_ext y WHERE y.years_ext = stats.yearID AND y.retrotm = stats.tm /*AND y.parkid = stats.parkid*/) = 0 THEN (stats.runs_home / stats.games_home) / 
																														(stats.runs_road / stats.games_road)
        ELSE ((((SELECT COUNT(*) FROM years_ext y WHERE y.years_ext = stats.yearID AND y.retrotm = stats.tm  /*AND y.parkid = stats.parkid*/) * stats.runs_home) +
				(SELECT SUM(s2.runs_home) FROM stats_ext s2 WHERE stats.yearID <> s2.yearid /*AND s2.parkid = stats.parkid*/ AND stats.tm = s2.tm AND s2.yearID BETWEEN stats.yearID - 2 AND stats.yearID + 2))
				/ 
			 (((SELECT COUNT(*) FROM years_ext y WHERE y.years_ext = stats.yearID AND y.retrotm = stats.tm  /*AND y.parkid = stats.parkid*/) * stats.games_home) + 
				(SELECT SUM(s2.games_home) FROM stats_ext s2 WHERE stats.yearID <> s2.yearid /*AND s2.parkid = stats.parkid*/ AND stats.tm = s2.tm  AND s2.yearID BETWEEN stats.yearID - 2 AND stats.yearID + 2)))
			/
			((((SELECT COUNT(*) FROM years_ext y WHERE y.years_ext = stats.yearID AND y.retrotm = stats.tm  /*AND y.parkid = stats.parkid*/) * stats.runs_road) +
				(SELECT SUM(s2.runs_road) FROM stats_ext s2 WHERE stats.yearID <> s2.yearid /*AND s2.parkid = stats.parkid*/ AND stats.tm = s2.tm  AND s2.yearID BETWEEN stats.yearID - 2 AND stats.yearID + 2))
				/ 
			 (((SELECT COUNT(*) FROM years_ext y WHERE y.years_ext = stats.yearID AND y.retrotm = stats.tm  /*AND y.parkid = stats.parkid*/) * stats.games_road) + 
				(SELECT SUM(s2.games_road) FROM stats_ext s2 WHERE stats.yearID <> s2.yearid /*AND s2.parkid = stats.parkid*/ AND stats.tm = s2.tm  AND s2.yearID BETWEEN stats.yearID - 2 AND stats.yearID + 2)))
	END AS park_run_factor   
    , CASE 
		WHEN stats.YearID < 1909 THEN ((stats.hr_home + 100) / (stats.games_home + 10)) / ((stats.hr_road + 100) / (stats.games_road + 10))
        WHEN (SELECT COUNT(*) FROM years_ext y WHERE y.years_ext = stats.yearID AND y.retrotm = stats.tm  /*AND y.parkid = stats.parkid*/) = 0 THEN (stats.hr_home / stats.games_home) / 
																														(stats.hr_road / stats.games_road)
        ELSE ((((SELECT COUNT(*) FROM years_ext y WHERE y.years_ext = stats.yearID AND y.retrotm = stats.tm /*AND y.parkid = stats.parkid*/) * stats.hr_home) +
				(SELECT SUM(s2.hr_home) FROM stats_ext s2 WHERE stats.yearID <> s2.yearid /*AND s2.parkid = stats.parkid*/ AND stats.tm = s2.tm AND s2.yearID BETWEEN stats.yearID - 2 AND stats.yearID + 2))
				/ 
			 (((SELECT COUNT(*) FROM years_ext y WHERE y.years_ext = stats.yearID AND y.retrotm = stats.tm  /*AND y.parkid = stats.parkid*/) * stats.games_home) + 
				(SELECT SUM(s2.games_home) FROM stats_ext s2 WHERE stats.yearID <> s2.yearid /*AND s2.parkid = stats.parkid*/ AND stats.tm = s2.tm  AND s2.yearID BETWEEN stats.yearID - 2 AND stats.yearID + 2)))
			/
			((((SELECT COUNT(*) FROM years_ext y WHERE y.years_ext = stats.yearID AND y.retrotm = stats.tm  /*AND y.parkid = stats.parkid*/) * stats.hr_road) +
				(SELECT SUM(s2.hr_road) FROM stats_ext s2 WHERE stats.yearID <> s2.yearid /*AND s2.parkid = stats.parkid*/ AND stats.tm = s2.tm  AND s2.yearID BETWEEN stats.yearID - 2 AND stats.yearID + 2))
				/ 
			 (((SELECT COUNT(*) FROM years_ext y WHERE y.years_ext = stats.yearID AND y.retrotm = stats.tm  /*AND y.parkid = stats.parkid*/) * stats.games_road) + 
				(SELECT SUM(s2.games_road) FROM stats_ext s2 WHERE stats.yearID <> s2.yearid /*AND s2.parkid = stats.parkid*/ AND stats.tm = s2.tm  AND s2.yearID BETWEEN stats.yearID - 2 AND stats.yearID + 2)))
	END AS park_hr_factor   
FROM stats_ext stats
JOIN home ON stats.yearid = home.yearid AND stats.lg = home.lg AND stats.tm = home.tm
GROUP BY stats.YearID, stats.Lg, stats.Tm, /* stats.ParkID, */ stats.runs_home, stats.games_home, stats.runs_road, stats.games_road, stats.hr_home, stats.hr_road, home.games
ORDER BY stats.tm, stats.yearID
;


/* Compute Year/League totals */
CREATE TABLE temp_yr_lg_totals AS
SELECT
	bat.Year
	, bat.Lg
	, SUM(bat.AB) AS AB_b
	, SUM(bat.R) AS R_b
	, SUM(bat.H) AS H_b
	, SUM(bat.`2B`) AS `2B_b`
	, SUM(bat.`3B`) AS `3B_b`
	, SUM(bat.HR) AS HR_b
	, SUM(bat.BB) AS BB_b
	, SUM(bat.SO) AS SO_b
	, SUM(bat.HBP) AS HBP_b
	, SUM(bat.SH) AS SH_b
	, SUM(bat.SF) AS SF_b
	, SUM(bat.SB) AS SB_b
	, SUM(bat.CS) AS CS_b
	, SUM(pit.W) AS W_p
	, SUM(pit.L) AS L_p
	, SUM(pit.BF) AS BF_p
	, SUM(pit.IP) AS IP_p
	, SUM(pit.H) AS H_p
	, SUM(pit.R) AS R_p
	, SUM(pit.ER) AS ER_p
	, SUM(pit.HR) AS HR_p
	, SUM(pit.SH) AS SH_p
	, SUM(pit.SF) AS SF_p
	, SUM(COALESCE(pit.HBP, 0)) AS HBP_p
	, SUM(pit.BB) AS BB_p
	, SUM(pit.SO) AS SO_p
	, SUM(pit.WP) AS WP_p
	, SUM(pit.BK) AS BK_p
	, SUM(pit.IP_LHP) AS IP_LHP_p
	, SUM(pit.SO_LHP) AS SO_LHP_p
	, SUM(misc.W_HOME) AS W_HOME
	, SUM(misc.L_ROAD) AS L_ROAD
	, SUM(fld.PO) AS PO
	, SUM(fld.A) AS A
	, SUM(fld.E) AS E
	, SUM(fld.DP) AS DP
	, SUM(fld.PB) AS PB
	, SUM(CAST(bat.R AS FLOAT)) / SUM(bat.AB - bat.H + bat.CS) AS RUNS_PER_OUT_LG
	, 1 - (1 - (SUM(pit.BF - pit.H - CAST(pit.BB AS FLOAT) - pit.SO - pit.HBP)/SUM(pit.BF - pit.HR - pit.BB - pit.SO - pit.HBP))) AS DER_LG
FROM temp_yr_lg_tm_bat_totals bat
JOIN temp_yr_lg_tm_pit_totals pit ON bat.Year = pit.Year AND bat.Lg = pit.Lg AND bat.Tm = pit.Tm
JOIN temp_yr_lg_tm_misc_totals misc ON pit.Year = misc.Year AND pit.Lg = misc.Lg AND pit.Tm = misc.Tm
JOIN temp_yr_lg_tm_fld_totals fld ON misc.Year = fld.Year AND misc.Lg = fld.Lg AND misc.Tm = fld.Tm
GROUP BY bat.Year, bat.Lg
;


CREATE TABLE temp_yr_lg_position_fielding AS
WITH SO_p_lg AS 
	(SELECT Year, Lg, SUM(SO) AS SO_p FROM bbref_pitching_standard GROUP BY Year, Lg)
SELECT
	p.Year
	, p.Lg
	, SUM(p.Inn) AS INN_P_LG
	, SUM(p.PO) AS PO_P_LG
	, SUM(p.A) AS A_P_LG
	, SUM(p.E) AS E_P_LG
	, SUM(p.DP) AS DP_P_LG
    , c.INN_C_LG
    , c.PO_C_LG
    , c.A_C_LG
    , c.E_C_LG
    , c.DP_C_LG
    , c.PB_C_LG
    , c.SB_C_LG
    , c.CS_C_LG
    , p2.SO_p
	, 1 - (c.PO_C_LG + c.A_C_LG - p2.SO_p ) / (CAST(c.PO_C_LG AS FLOAT) + c.A_C_LG - p2.SO_p + c.E_C_LG) AS EPct_C_LG
	, f.INN_1B_LG
	, f.PO_1B_LG
	, f.A_1B_LG
	, f.E_1B_LG
	, f.DP_1B_LG
	, f.E_1B_LG / (CAST(f.PO_1B_LG AS FLOAT) + f.A_1B_LG + f.E_1B_LG) AS EPct_1B_LG
	, s.INN_2B_LG
	, s.PO_2B_LG
	, s.A_2B_LG
	, s.E_2B_LG
	, s.DP_2B_LG
	, s.E_2B_LG / (CAST(s.PO_2B_LG AS FLOAT) + s.A_2B_LG + s.E_2B_LG) AS EPct_2B_LG
	, t.INN_3B_LG
	, t.PO_3B_LG
	, t.A_3B_LG
	, t.E_3B_LG
	, t.DP_3B_LG
	, t.E_3B_LG / (CAST(t.PO_3B_LG AS FLOAT) + t.A_3B_LG + t.E_3B_LG) AS EPct_3B_LG
	, ss.INN_SS_LG
	, ss.PO_SS_LG
	, ss.A_SS_LG
	, ss.E_SS_LG
	, ss.DP_SS_LG
	, ss.E_SS_LG / (CAST(ss.PO_SS_LG AS FLOAT) + ss.A_SS_LG + ss.E_SS_LG) AS EPct_SS_LG
	, fof.INN_OF_LG
	, fof.PO_OF_LG
	, fof.A_OF_LG
	, fof.E_OF_LG
	, fof.DP_OF_LG
	, fof.E_OF_LG / (CAST(fof.PO_OF_LG AS FLOAT) + fof.A_OF_LG + fof.E_OF_LG) AS EPct_OF_LG
FROM bbref_fielding_p p
JOIN SO_p_lg AS p2 ON p.Year = p2.Year AND p.Lg = p2.Lg
JOIN 
	(
	SELECT 
		Year AS `Year`
		, Lg
		, SUM(Inn) AS INN_C_LG
		, SUM(PO) AS PO_C_LG
		, SUM(A) AS A_C_LG
		, SUM(E) AS E_C_LG
		, SUM(DP) AS DP_C_LG
		, SUM(PB) AS PB_C_LG
		, SUM(SB) AS SB_C_LG
		, SUM(CS) AS CS_C_LG
	FROM bbref_fielding_c
	WHERE Lg <> 'MLB' AND Tm <> 'TOT'
    GROUP BY Year, Lg
	) c ON p.`Year` = c.`Year` and p.Lg = c.Lg
JOIN 
	(
	SELECT 
		Year AS `Year`
		, Lg
		, SUM(Inn) AS INN_1B_LG
		, SUM(PO) AS PO_1B_LG
		, SUM(A) AS A_1B_LG
		, SUM(E) AS E_1B_LG
		, SUM(DP) AS DP_1B_LG
	FROM bbref_fielding_1b
	WHERE Lg <> 'MLB' AND Tm <> 'TOT'
    GROUP BY Year, Lg
	) f ON p.`Year` = f.`Year` and p.Lg = f.Lg
JOIN 
	(
	SELECT 
		Year AS `Year`
		, Lg
		, SUM(Inn) AS INN_2B_LG
		, SUM(PO) AS PO_2B_LG
		, SUM(A) AS A_2B_LG
		, SUM(E) AS E_2B_LG
		, SUM(DP) AS DP_2B_LG
	FROM bbref_fielding_2b
	WHERE Lg <> 'MLB' AND Tm <> 'TOT'
    GROUP BY Year, Lg
	) s ON p.`Year` = s.`Year` and p.Lg = s.Lg
JOIN 
	(
	SELECT 
		Year AS `Year`
		, Lg
		, SUM(Inn) AS INN_3B_LG
		, SUM(PO) AS PO_3B_LG
		, SUM(A) AS A_3B_LG
		, SUM(E) AS E_3B_LG
		, SUM(DP) AS DP_3B_LG
	FROM bbref_fielding_3b
	WHERE Lg <> 'MLB' AND Tm <> 'TOT'
    GROUP BY Year, Lg
	) t ON p.`Year` = t.`Year` and p.Lg = t.Lg
JOIN 
	(
	SELECT 
		Year AS `Year`
		, Lg
		, SUM(Inn) AS INN_SS_LG
		, SUM(PO) AS PO_SS_LG
		, SUM(A) AS A_SS_LG
		, SUM(E) AS E_SS_LG
		, SUM(DP) AS DP_SS_LG
	FROM bbref_fielding_ss
	WHERE Lg <> 'MLB' AND Tm <> 'TOT'
    GROUP BY Year, Lg
	) ss ON p.`Year` = ss.`Year` and p.Lg = ss.Lg
JOIN 
	(
	SELECT 
		Year AS `Year`
		, Lg
		, SUM(Inn) AS INN_OF_LG
		, SUM(PO) AS PO_OF_LG
		, SUM(A) AS A_OF_LG
		, SUM(E) AS E_OF_LG
		, SUM(DP) AS DP_OF_LG
	FROM bbref_fielding_of
	WHERE Lg <> 'MLB' AND Tm <> 'TOT'
    GROUP BY Year, Lg
	) fof ON p.`Year` = fof.`Year` and p.Lg = fof.Lg
WHERE p.lg <> 'MLB' AND p.Tm <> 'TOT'
GROUP BY p.`Year`, p.Lg
ORDER BY p.`Year`, p.Lg
;



/* Compute Yr/Lg Factors */
CREATE TABLE temp_yr_lg_factors AS
SELECT
	a.Year
	, a.Lg
	, a.X_Lg
	, a.ROB_Lg
	, a.EstA_Lg
	, a.EstB_Lg
	, (2*EstA_Lg + EstB_Lg) / 3 AS EstC_Lg
	, a.FA_Lg
	, a.SHR_Lg
FROM
	(
	SELECT
		f.Year
		, f.Lg
		, (f.A_1B_LG + 0.5*f.DP_SS_LG - f.PO_P_LG + 0.5*f.DP_2B_LG) / (SELECT COUNT(DISTINCT p.Tm) FROM bbref_pitching_standard p WHERE f.Year = p.Year AND f.Lg = p.Lg AND p.Tm <> 'TOT') AS X_Lg
		, t.H_b - t.`2B_b` - t.`3B_b` - t.HR_b + t.BB_p + t.HBP_p - f.PB_C_LG - t.WP_p - t.BK_p AS ROB_Lg
		, f.PO_1B_LG - 0.7*f.A_P_LG - 0.86*f.A_2B_LG - 0.78*(f.A_3B_LG + f.A_SS_LG) + 0.115*(t.H_b - t.`2B_b` - t.`3B_b` - t.HR_b + t.BB_p + t.HBP_p - f.PB_C_LG - t.WP_p - t.BK_p)
			- 0.0575*(3*t.IP_p - t.SO_p) AS EstA_Lg
		, (3*t.IP_p - t.SO_p)*0.1 - f.A_1B_LG AS EstB_Lg
		, 1 - f.EPct_3B_LG AS FA_Lg
		, CAST(t.SH_p AS FLOAT) / (t.W_p + 2*t.L_p) AS SHR_Lg
		, t.SH_p, t.W_p, t.L_p
	FROM temp_yr_lg_position_fielding f
	JOIN temp_yr_lg_totals t ON f.Year = t.Year AND f.Lg = T.Lg
	) a
ORDER BY a.Year, a.Lg
;


CREATE TABLE temp_yr_lg_tm_position_fielding AS
WITH SO_p_lg_tm AS 
	(SELECT Year, Lg, Tm, SUM(SO) AS SO_p_tm FROM bbref_pitching_standard GROUP BY Year, Lg, Tm)
SELECT
	p.Year
	, p.Lg
    , p.Tm
	, SUM(p.Inn) AS INN_P_TM
	, SUM(p.PO) AS PO_P_TM
	, SUM(p.A) AS A_P_TM
	, SUM(p.E) AS E_P_TM
	, SUM(p.DP) AS DP_P_TM
    , c.INN_C_TM
    , c.PO_C_TM
    , c.A_C_TM
    , c.E_C_TM
    , c.DP_C_TM
    , c.PB_C_TM
    , c.SB_C_TM
    , c.CS_C_TM
    , p2.SO_P_TM
	, 1 - (c.PO_C_TM + c.A_C_TM - p2.SO_P_TM ) / (CAST(c.PO_C_TM AS FLOAT) + c.A_C_TM - p2.SO_P_TM + c.E_C_TM) AS EPct_C_TM
	, f.INN_1B_TM
	, f.PO_1B_TM
	, f.A_1B_TM
	, f.E_1B_TM
	, f.DP_1B_TM
	, f.E_1B_TM / (CAST(f.PO_1B_TM AS FLOAT) + f.A_1B_TM + f.E_1B_TM) AS EPct_1B_TM
	, s.INN_2B_TM
	, s.PO_2B_TM
	, s.A_2B_TM
	, s.E_2B_TM
	, s.DP_2B_TM
	, s.E_2B_TM / (CAST(s.PO_2B_TM AS FLOAT) + s.A_2B_TM + s.E_2B_TM) AS EPct_2B_TM
	, t.INN_3B_TM
	, t.PO_3B_TM
	, t.A_3B_TM
	, t.E_3B_TM
	, t.DP_3B_TM
	, t.E_3B_TM / (CAST(t.PO_3B_TM AS FLOAT) + t.A_3B_TM + t.E_3B_TM) AS EPct_3B_TM
	, ss.INN_SS_TM
	, ss.PO_SS_TM
	, ss.A_SS_TM
	, ss.E_SS_TM
	, ss.DP_SS_TM
	, ss.E_SS_TM / (CAST(ss.PO_SS_TM AS FLOAT) + ss.A_SS_TM + ss.E_SS_TM) AS EPct_SS_TM
	, fof.INN_OF_TM
	, fof.PO_OF_TM
	, fof.A_OF_TM
	, fof.E_OF_TM
	, fof.DP_OF_TM
	, fof.E_OF_TM / (CAST(fof.PO_OF_TM AS FLOAT) + fof.A_OF_TM + fof.E_OF_TM) AS EPct_OF_TM
FROM bbref_fielding_p p
JOIN SO_p_lg_tm AS p2 ON p.Year = p2.Year AND p.Lg = p2.Lg AND p.Tm = p2.Tm
JOIN 
	(
	SELECT 
		Year AS `Year`
		, Lg
        , Tm
		, SUM(Inn) AS INN_C_TM
		, SUM(PO) AS PO_C_TM
		, SUM(A) AS A_C_TM
		, SUM(E) AS E_C_TM
		, SUM(DP) AS DP_C_TM
		, SUM(PB) AS PB_C_TM
		, SUM(SB) AS SB_C_TM
		, SUM(CS) AS CS_C_TM
	FROM bbref_fielding_c
	WHERE Lg <> 'MLB' AND Tm <> 'TOT'
    GROUP BY Year, Lg, Tm
	) c ON p.`Year` = c.`Year` and p.Lg = c.Lg AND p.Tm = c.Tm
JOIN 
	(
	SELECT 
		Year AS `Year`
		, Lg
        , Tm
		, SUM(Inn) AS INN_1B_TM
		, SUM(PO) AS PO_1B_TM
		, SUM(A) AS A_1B_TM
		, SUM(E) AS E_1B_TM
		, SUM(DP) AS DP_1B_TM
	FROM bbref_fielding_1b
	WHERE Lg <> 'MLB' AND Tm <> 'TOT'
    GROUP BY Year, Lg, Tm
	) f ON p.`Year` = f.`Year` and p.Lg = f.Lg AND p.Tm = f.Tm
JOIN 
	(
	SELECT 
		Year AS `Year`
		, Lg
        , Tm
		, SUM(Inn) AS INN_2B_TM
		, SUM(PO) AS PO_2B_TM
		, SUM(A) AS A_2B_TM
		, SUM(E) AS E_2B_TM
		, SUM(DP) AS DP_2B_TM
	FROM bbref_fielding_2b
	WHERE Lg <> 'MLB' AND Tm <> 'TOT'
    GROUP BY Year, Lg, Tm
	) s ON p.`Year` = s.`Year` and p.Lg = s.Lg AND p.Tm = s.Tm
JOIN 
	(
	SELECT 
		Year AS `Year`
		, Lg
        , Tm
		, SUM(Inn) AS INN_3B_TM
		, SUM(PO) AS PO_3B_TM
		, SUM(A) AS A_3B_TM
		, SUM(E) AS E_3B_TM
		, SUM(DP) AS DP_3B_TM
	FROM bbref_fielding_3b
	WHERE Lg <> 'MLB' AND Tm <> 'TOT'
    GROUP BY Year, Lg, Tm
	) t ON p.`Year` = t.`Year` and p.Lg = t.Lg AND p.Tm = t.Tm
JOIN 
	(
	SELECT 
		Year AS `Year`
		, Lg
        , Tm
		, SUM(Inn) AS INN_SS_TM
		, SUM(PO) AS PO_SS_TM
		, SUM(A) AS A_SS_TM
		, SUM(E) AS E_SS_TM
		, SUM(DP) AS DP_SS_TM
	FROM bbref_fielding_ss
	WHERE Lg <> 'MLB' AND Tm <> 'TOT'
    GROUP BY Year, Lg, Tm
	) ss ON p.`Year` = ss.`Year` and p.Lg = ss.Lg AND p.Tm = ss.Tm
JOIN 
	(
	SELECT 
		Year AS `Year`
		, Lg
        , Tm
		, SUM(Inn) AS INN_OF_TM
		, SUM(PO) AS PO_OF_TM
		, SUM(A) AS A_OF_TM
		, SUM(E) AS E_OF_TM
		, SUM(DP) AS DP_OF_TM
	FROM bbref_fielding_of
	WHERE Lg <> 'MLB' AND Tm <> 'TOT'
    GROUP BY Year, Lg, Tm
	) fof ON p.`Year` = fof.`Year` and p.Lg = fof.Lg AND p.Tm = fof.Tm
WHERE p.lg <> 'MLB' AND p.Tm <> 'TOT'
GROUP BY p.`Year`, p.Lg, p.Tm
ORDER BY p.`Year`, p.Lg, p.Tm
;


/* Compute Stage 1 Win Shares team factors */
CREATE TABLE temp_win_shares_factors_stage_1 AS
SELECT
	a.YearID
	, a.Lg
	, a.Tm
	, 1 - (1 - a.DER_quotient)/a.`P-S` AS DER
	, a.`P-S`
	, a.MR
	, a.MRA
	, CASE
		WHEN ((100 + 2500 * (1 - (1 - a.DER_quotient)/a.`P-S` - (SELECT DER_LG FROM temp_yr_lg_totals t WHERE a.YearID = t.Year AND a.Lg = t.Lg))) 
			+ a.`CL-2` + a.`CL-3` + a.`CL-4` + 405 * p.WPCT + 650) / (2 * (100 + 2500 * (1 - (1 - a.DER_quotient)/a.`P-S` - (SELECT DER_LG FROM temp_yr_lg_totals t WHERE a.YearID = t.Year AND a.Lg = t.Lg)))
			+ a.`CL-2` + a.`CL-3` + a.`CL-4` + (100 + (t.E + 0.5 * t.PB) / t.IP_p * p.IP - 0.5 * f.PB - f.E) + (100 + (f.DP - a.EDP2) * 4/3) + 1097.5 + 405 * p.WPCT) < 0.16375 THEN 0.16375 
		WHEN ((100 + 2500 * (1 - (1 - a.DER_quotient)/a.`P-S` - (SELECT DER_LG FROM temp_yr_lg_totals t WHERE a.YearID = t.Year AND a.Lg = t.Lg))) 
			+ a.`CL-2` + a.`CL-3` + a.`CL-4` + 405 * p.WPCT + 650) / (2 * (100 + 2500 * (1 - (1 - a.DER_quotient)/a.`P-S` - (SELECT DER_LG FROM temp_yr_lg_totals t WHERE a.YearID = t.Year AND a.Lg = t.Lg)))
			+ a.`CL-2` + a.`CL-3` + a.`CL-4` + (100 + (t.E + 0.5 * t.PB) / t.IP_p * p.IP - 0.5 * f.PB - f.E) + (100 + (f.DP - a.EDP2) * 4/3) + 1097.5 + 405 * p.WPCT) > 0.32375 THEN 0.32375 
		ELSE ((100 + 2500 * (1 - (1 - a.DER_quotient)/a.`P-S` - (SELECT DER_LG FROM temp_yr_lg_totals t WHERE a.YearID = t.Year AND a.Lg = t.Lg))) 
			+ a.`CL-2` + a.`CL-3` + a.`CL-4` + 405 * p.WPCT + 650) / (2 * (100 + 2500 * (1 - (1 - a.DER_quotient)/a.`P-S` - (SELECT DER_LG FROM temp_yr_lg_totals t WHERE a.YearID = t.Year AND a.Lg = t.Lg)))
			+ a.`CL-2` + a.`CL-3` + a.`CL-4` + (100 + (t.E + 0.5 * t.PB) / t.IP_p * p.IP - 0.5 * f.PB - f.E) + (100 + (f.DP - a.EDP2) * 4/3) + 1097.5 + 405 * p.WPCT)
		END AS P_Pct
	, a.MR / (a.MR + a.MRA) * 3 * p.W AS OW
	, 3 * p.W - (a.MR / (a.MR + a.MRA) * 3 * p.W) AS DW
	, (3 * p.W - (a.MR / (a.MR + a.MRA) * 3 * p.W)) * 
		((100 + 2500 * (1 - (1 - a.DER_quotient)/a.`P-S` - (SELECT DER_LG FROM temp_yr_lg_totals t WHERE a.YearID = t.Year AND a.Lg = t.Lg))) 
			+ a.`CL-2` + a.`CL-3` + a.`CL-4` + 405 * p.WPCT + 650) / (2 * (100 + 2500 * (1 - (1 - a.DER_quotient)/a.`P-S` - (SELECT DER_LG FROM temp_yr_lg_totals t WHERE a.YearID = t.Year AND a.Lg = t.Lg)))
			+ a.`CL-2` + a.`CL-3` + a.`CL-4` + (100 + (t.E + 0.5 * t.PB) / t.IP_p * p.IP - 0.5 * f.PB - f.E) + (100 + (f.DP - a.EDP2) * 4/3) + 1097.5 + 405 * p.WPCT) AS PW
	, (3 * p.W - (a.MR / (a.MR + a.MRA) * 3 * p.W)) -
		(3 * p.W - (a.MR / (a.MR + a.MRA) * 3 * p.W)) * 
			((100 + 2500 * (1 - (1 - a.DER_quotient)/a.`P-S` - (SELECT DER_LG FROM temp_yr_lg_totals t WHERE a.YearID = t.Year AND a.Lg = t.Lg))) 
			+ a.`CL-2` + a.`CL-3` + a.`CL-4` + 405 * p.WPCT + 650) / (2 * (100 + 2500 * (1 - (1 - a.DER_quotient)/a.`P-S` - (SELECT DER_LG FROM temp_yr_lg_totals t WHERE a.YearID = t.Year AND a.Lg = t.Lg)))
			+ a.`CL-2` + a.`CL-3` + a.`CL-4` + (100 + (t.E + 0.5 * t.PB) / t.IP_p * p.IP - 0.5 * f.PB - f.E) + (100 + (f.DP - a.EDP2) * 4/3) + 1097.5 + 405 * p.WPCT) AS FW
	, 100 + 2500 * (1 - (1 - a.DER_quotient)/a.`P-S` - (SELECT DER_LG FROM temp_yr_lg_totals t WHERE a.YearID = t.Year AND a.Lg = t.Lg)) AS `CL-1`
	, a.`CL-2`
	, a.`CL-3`
	, a.`CL-4`
	, 100 + (t.E + 0.5 * t.PB) / t.IP_p * p.IP - 0.5 * f.PB - f.E AS `CL-5`
	, 100 + (f.DP - a.EDP2) * 4/3 AS `CL-6`
	, a.EDP2
	, a.`O-0`
	, (t.R_p * 9 / t.IP_p) * pf.Park_run_Factor * 1.52 - (((t.R_p * 9 / t.IP_p) * pf.Park_run_Factor * 1.52 - p.ER * 9 / p.IP) * 
		(1 - (((100 + 2500 * (1 - (1 - a.DER_quotient)/a.`P-S` - (SELECT DER_LG FROM temp_yr_lg_totals t WHERE a.YearID = t.Year AND a.Lg = t.Lg))) 
			+ a.`CL-2` + a.`CL-3` + a.`CL-4` + 405 * p.WPCT + 650) / (2 * (100 + 2500 * (1 - (1 - a.DER_quotient)/a.`P-S` - (SELECT DER_LG FROM temp_yr_lg_totals t WHERE a.YearID = t.Year AND a.Lg = t.Lg)))
			+ a.`CL-2` + a.`CL-3` + a.`CL-4` + (100 + (t.E + 0.5 * t.PB) / t.IP_p * p.IP - 0.5 * f.PB - f.E) + (100 + (f.DP - a.EDP2) * 4/3) + 1097.5 + 405 * p.WPCT)))) AS `P-0`
	, a.TLPOP
	, a.LH
FROM
	(
	SELECT
		pf.YearID
		, pf.Lg
		, ct.Teamidbr as tm
		, (p.BF - p.H - p.BB - p.SO - p.HBP) / (CAST(p.BF AS FLOAT) - p.HR - p.BB - p.SO - p.HBP) AS DER_quotient
		, SQRT((pf.Park_run_Factor - pf.Park_hr_Factor * (t.HR_b * 1.5 / t.R_b)) / (1 - t.HR_b * 1.5 / t.R_b)) AS `P-S`
		, b.R - (CAST(t.R_p AS FLOAT) / t.IP_p) * pf.Park_run_Factor * 0.52 * (p.IP - misc.W_HOME + misc.L_ROAD) AS MR
		, (t.R_p / t.IP_p) * pf.Park_run_Factor * 1.52 * p.IP - p.R AS MRA
		, 28.571 * (p.SO * 9  / p.IP + 2.5) AS `CL-2`
		, (t.HBP_p + t.BB_p) / t.IP_p * p.IP - p.BB - p.HBP + 200 AS `CL-3`
		, 5 * (t.HR_p / IF(t.IP_p = 0, 1, t.IP_p) * p.IP - p.HR / IFNULL(IF(pf.Park_hr_Factor = 0, 1, pf.Park_hr_Factor), 1)) + 200 AS `CL-4`
		, ((t.H_b - t.`2B_b` - t.`3B_b` - t.HR_b) / ((t.H_b/1.0) - t.HR_b) * (p.H - p.HR) + p.BB + p.HBP - p.SH - p.WP - p.BK) * ((t.DP/1.0) / (t.H_b - t.`2B_b` - t.`3B_b` - t.HR_b + t.BB_p + t.HR_p - t.SH_p - t.WP_p - t.BK_p - t.PB)) * (((f.A/1.0) / p.IP) / ((t.A/1.0) / t.IP_p)) AS EDP2
		, t.R_b / (CAST(t.AB_b AS FLOAT) - t.H_b + t.CS_b) * 0.52 * pf.Park_run_Factor AS `O-0`
		, (f.PO - p.SO) / (CAST(t.PO AS FLOAT) - t.SO_p) AS TLPOP
		, 3 * p.IP_LHP - p.SO_LHP - ((3 * t.IP_LHP_p - t.SO_LHP_p) / (3 * t.IP_p - t.SO_p)) * (3 * p.IP - p.SO) AS LH
	FROM temp_Yr_Lg_Tm_Park_Factors pf
    JOIN chadwick_teams ct ON pf.tm = ct.teamIDretro AND pf.yearid = ct.yearID AND pf.lg = ct.lgID
	JOIN temp_Yr_Lg_Tm_Pit_Totals p ON pf.YearID = p.Year AND pf.Lg = p.Lg AND ct.teamIDBR = p.Tm
	JOIN temp_Yr_Lg_Tm_Bat_Totals b ON p.Year = b.Year AND p.Lg = b.Lg AND p.Tm = b.Tm 
	JOIN temp_Yr_Lg_Tm_Fld_Totals f ON b.Year = f.Year AND b.Lg = f.Lg AND b.Tm = f.Tm
	JOIN temp_Yr_Lg_Tm_Misc_Totals misc on f.Year = misc.Year AND f.Lg = misc.Lg AND f.Tm = misc.Tm
	JOIN temp_Yr_Lg_Totals t ON misc.Year = t.Year AND misc.Lg = t.Lg
	) a
JOIN temp_Yr_Lg_Tm_Pit_Totals p ON a.YearID = p.Year AND a.Lg = p.Lg AND a.Tm = p.Tm
JOIN temp_Yr_Lg_Tm_Fld_Totals f ON p.Year = f.Year AND p.Lg = f.Lg AND p.Tm = f.Tm
JOIN chadwick_teams teams ON f.tm = teams.teamidbr AND f.year = teams.yearid AND f.lg = teams.lgID
JOIN temp_Yr_Lg_Tm_Park_Factors pf ON f.Year = pf.YearID AND f.Lg = pf.Lg AND teams.teamidretro = pf.Tm
JOIN temp_Yr_Lg_Totals t ON f.Year = t.Year AND f.Lg = t.Lg 
ORDER BY a.YearID, a.Lg, a.Tm
;


/* Compute Stage 2 Win Shares team factors */
CREATE TABLE temp_win_shares_factors_stage_2 AS
SELECT
	a.Year
	, a.Lg
	, a.Tm
	, a.ROB
	, a.EstA
	, a.EstB
	, (2 * a.EstA + a.EstB) / 3 AS EstC
	, a.X
	, a.EPO_2B
	, a.EPO_SS
	, a.EE
	, a.SHR
	, a.EA
FROM
	(
	SELECT
		b.Year
		, b.Lg
		, b.Tm
		, (CAST(p.H AS FLOAT) - p.HR) * (t.H_b - t.`2B_b` - t.`3B_b` - t.HR_b) / (t.H_b - t.HR_b) + p.BB + p.HBP - p.WP - f.PB - p.BK AS ROB
		, pf.PO_1B_TM - 0.7 * pf.A_P_TM - 0.86 * pf.A_2B_TM - 0.78 * (pf.A_3B_TM + pf.A_SS_TM) + 0.115 * 
			((CAST(p.H AS FLOAT) - p.HR) * (t.H_b - t.`2B_b` - t.`3B_b` - t.HR_b) / (t.H_b - t.HR_b) + p.BB + p.HBP - p.WP - f.PB - p.BK)
				- 0.0575 * (p.IP * 3 - p.SO) AS EstA
		, (3 * p.IP - p.SO) * 0.1 - pf.A_1B_TM AS EstB
		, pf.A_1B_TM + 0.5 * pf.DP_SS_TM - pf.PO_P_TM + 0.5 * pf.DP_2B_TM + 0.015 * ws1.LH AS X
		, (f.PO - p.SO) * lpf.PO_2B_LG / (t.PO - t.SO_p) + (p.BB - (t.BB_p / t.IP_p) * p.IP) / 13 + ws1.LH / 32 AS EPO_2B
		, (f.PO - p.SO) * lpf.PO_SS_LG / (t.PO - t.SO_p) + (p.BB - (t.BB_p / t.IP_p) * p.IP) / 14 + ws1.LH / 64 AS EPO_SS
		, (pf.PO_3B_TM + pf.PO_SS_TM) / ylf.FA_Lg - pf.PO_3B_TM - pf.PO_SS_TM AS EE
		, p.SH / (CAST(p.W AS FLOAT) + 2 * p.L) AS SHR
		, f.A * lpf.A_3B_LG / (t.A/1.0) + ws1.LH / 31.0 AS EA
	FROM temp_Yr_Lg_Tm_Bat_Totals b
	JOIN temp_Yr_Lg_Tm_Pit_Totals p ON b.Year = p.Year AND b.Lg = p.Lg AND b.Tm = p.Tm
	JOIN temp_Yr_Lg_Tm_Position_Fielding pf ON p.Year = pf.Year AND p.Lg = pf.Lg AND p.Tm = pf.Tm
	JOIN temp_Yr_Lg_Tm_Fld_Totals f ON pf.Year = f.Year AND pf.Lg = f.Lg AND pf.Tm = f.Tm
	JOIN temp_Yr_Lg_Totals t ON p.Year = t.Year AND p.Lg = t.Lg
	JOIN temp_Yr_Lg_Position_Fielding lpf ON t.Year = lpf.Year AND t.Lg = lpf.Lg
	JOIN temp_Yr_Lg_Factors ylf ON lpf.Year = ylf.Year AND lpf.Lg = ylf.Lg
	JOIN temp_Win_Shares_Factors_Stage_1 ws1 ON f.Year = ws1.YearID AND f.Lg = ws1.Lg AND f.Tm = ws1.Tm
	) a
ORDER BY a.Year, a.Lg, a.Tm
;


/* Compute Stage 3 Win Shares -- Positional P and C% factors */
CREATE TABLE temp_win_shares_factors_stage_3 AS
SELECT
	a.Year
	, a.Lg
	, a.Tm
	, (a.C_P1 + a.C_P2 + a.C_P3 + a.C_P4) / 100.0 AS cC_Pct
	, (a.`1B_P1` + a.`1B_P2` + a.`1B_P3` + a.`1B_P4`) / 100.0 AS c1B_Pct
	, (a.`2B_P1` + a.`2B_P2` + a.`2B_P3` + a.`2B_P4`) / 100.0 AS c2B_Pct
	, (a.`3B_P1` + a.`3B_P2` + a.`3B_P3` + a.`3B_P4`) / 100.0 AS c3B_Pct
	, (a.SS_P1 + a.SS_P2 + a.SS_P3 + a.SS_P4) / 100.0 AS cSS_Pct
	, (a.OF_P1 + a.OF_P2 + a.OF_P3 + a.OF_P4) / 100.0 AS cOF_Pct
FROM
	(
	SELECT
		pf.Year
		, pf.Lg
		, pf.Tm
		, pf.CS_C_TM,pf.SB_C_TM,lpf.CS_C_LG,lpf.SB_C_LG
		, 25 + (pf.CS_C_TM / (IF(pf.SB_C_TM = 0, 1.0, pf.SB_C_TM/1.0) + pf.CS_C_TM) - lpf.CS_C_LG / (IF(lpf.SB_C_LG = 0, 1.0, lpf.SB_C_LG/1.0) + lpf.CS_C_LG)) * 150 AS C_P1
		, 30 - 15 * pf.EPct_C_TM / lpf.EPct_C_LG AS C_P2
		, 5 + (pf.PB_C_TM - lpf.PB_C_LG * ws1.TLPOP) / 5 AS C_P3
		, 10 - (p.SF / (IF(tot.SF_p = 0, 1.0, tot.SF_p/1.0) * tot.HR_p)) * 5 AS C_P4
		, 20 + (ws2.EstC + pf.A_1B_TM + 0.0285 * ws1.LH - (f.EstC_Lg + lpf.A_1B_LG) * ws1.TLPOP) / 5.0 AS `1B_P1`
		, 30 - 15 * pf.EPct_1B_TM / (lpf.EPct_1B_LG) AS `1B_P2`
		, 10 + (ws2.X - f.X_lg) / 5 AS `1B_P3`
		, 10 - 5 * ((pf.E_3B_TM + pf.E_SS_TM) / ((lpf.E_3B_LG + lpf.E_SS_LG) * ws1.TLPOP)) AS `1B_P4`
		, 20 + (f2.DP - ws1.EDP2) / 3.0 AS `2B_P1`
		, (pf.A_2B_TM - pf.DP_2B_TM - ((lpf.A_2B_LG - lpf.DP_2B_LG) * ws1.TLPOP - ws1.LH / 35.0)) / 6 + 15 AS `2B_P2`
		, 24 - 14 * pf.EPct_2B_TM / lpf.EPct_2B_LG AS `2B_P3`
		, (pf.PO_2B_TM - ws2.EPO_2B) / 12.0 + 5 AS `2B_P4`
		, (pf.A_3B_TM - ws2.EA) / 4.0 + 25 AS `3B_P1`
		, (ws2.EE - pf.E_3B_TM) / 2.0 + 15 AS `3B_P2`
		, 10 - ws2.SHR / (IF(f.SHR_Lg = 0, 1, f.SHR_Lg)/1.0) * 5 AS `3B_P3`
		, (pf.DP_3B_TM - ws1.EDP2 * lpf.DP_3B_LG / (IF(tot.DP = 0, 1, tot.DP)/1.0)) / 2 + 5 AS `3B_P4`
		, (pf.A_SS_TM - (f2.A * (lpf.A_SS_LG / (tot.A/1.0)) + ws1.LH / 100.0)) / 4 + 20 AS `SS_P1`
		, (f2.DP - ws1.EDP2) / 4.0 + 15 AS `SS_P2`
		, 20 - 10 * pf.EPct_SS_TM / (lpf.EPct_SS_LG/1.0) AS `SS_P3`
		, (pf.PO_SS_TM - ws2.EPO_SS) / 5.0 + 5 AS `SS_P4`
		, (pf.PO_OF_TM / ((f2.PO/1.0) - f2.A - p.SO) - lpf.PO_OF_LG / ((tot.PO/1.0) - tot.A - tot.SO_p)) * 100 + 20 AS `OF_P1`
		, ws1.`CL-1` * 0.24 - 9 AS `OF_P2`
		, ((pf.A_OF_TM + pf.DP_OF_TM - p.SF) - (lpf.A_OF_LG + lpf.DP_OF_LG - tot.SF_p) * ws1.TLPOP) / 5.0 + 10 AS `OF_P3`
		, 10 - 5 * pf.EPct_OF_TM / lpf.EPct_OF_LG AS `OF_P4`
	FROM temp_Win_Shares_Factors_Stage_2 ws2
	JOIN temp_Win_Shares_Factors_Stage_1 ws1 ON ws2.Year = ws1.YearID AND ws2.Lg = ws1.Lg AND ws2.Tm = ws1.Tm
	JOIN temp_Yr_Lg_Tm_Position_Fielding pf ON ws1.YearID = pf.Year AND ws1.Lg = pf.Lg AND ws1.Tm = pf.Tm
	JOIN temp_Yr_Lg_Tm_Pit_Totals p ON pf.Year = p.Year AND pf.Lg = p.Lg AND pf.Tm = p.Tm
	JOIN temp_Yr_Lg_Tm_Fld_Totals f2 ON p.Year = f2.Year AND p.Lg = f2.Lg AND p.Tm = f2.Tm
	JOIN temp_Yr_Lg_Position_Fielding t ON pf.Year = t.Year AND pf.Lg = t.Lg
	JOIN temp_Yr_Lg_Position_Fielding lpf ON t.Year = lpf.Year AND t.Lg = lpf.Lg
	JOIN temp_Yr_Lg_Totals tot ON lpf.Year = tot.Year AND lpf.Lg = tot.Lg
	JOIN temp_Yr_Lg_Factors f ON tot.Year = f.Year AND tot.Lg = f.Lg
	) a
;

	

/* Get Positional Fielding Win Shares by team */
CREATE TABLE temp_yr_lg_tm_pos_fwin_shares AS
SELECT
	a.Year
	, a.Lg
	, a.Tm
	, a.FCR * a.cT AS cFW
	, a.FCR * a.`1bT` AS `1bFW`
	, a.FCR * a.`2bT` AS `2bFW`
	, a.FCR * a.`3bT` AS `3bFW`
	, a.FCR * a.ssT AS ssFW
	, a.FCR * a.ofT AS ofFW
FROM
	(
	SELECT
		ws3.Year
		, ws3.Lg
		, ws3.Tm
		, (ws1.FW/1.0) / ((ws3.cC_Pct - 0.2) * 38 + (ws3.c1B_Pct - 0.2) * 12 + (ws3.c2B_Pct - 0.2) * 32 + (ws3.c3B_Pct - 0.2) * 24 + (ws3.cSS_Pct - 0.2) * 36 + (ws3.cOF_Pct - 0.2) * 58) AS FCR
		, (ws3.cC_Pct - 0.2) * 38 AS cT
		, (ws3.c1B_Pct - 0.2) * 12 AS `1bT`
		, (ws3.c2B_Pct - 0.2) * 32 AS `2bT`
		, (ws3.c3B_Pct - 0.2) * 24 AS `3bT`
		, (ws3.cSS_Pct - 0.2) * 36 AS ssT
		, (ws3.cOF_Pct - 0.2) * 58 AS ofT
	FROM temp_Win_Shares_Factors_Stage_3 ws3
	JOIN temp_Win_Shares_Factors_Stage_1 ws1 ON ws3.Year = ws1.YearID AND ws3.Lg = ws1.Lg AND ws3.Tm = ws1.Tm
	) a
ORDER BY Year, Lg, Tm
;


/* Calculate player Claim Points by position */
/* Win Share totals in the Adj column have been adjusted 
   for team schedule length scaled to 162 games */

CREATE TABLE temp_yr_lg_tm_pos_claim_points AS
SELECT
	a.Year
	, a.Lg
	, a.Tm
	, 'c' AS Pos
	, a.Name
	, a.BBRefID
	, a.Inn
	, a.PO
	, a.A
	, a.E
	, a.DP
	, a.PB
	, a.SB
	, a.CS
	-- This line fudges earned runs allowed by each catcher by omitting the catcher earned runs factor
	, IF(a.Inn > 0,IF(a.PO + 2*(a.A - a.CS) - 8*a.E + 6*a.DP - 4*a.PB - 2*a.SB + 4*a.CS /*+ 2*(p.ER / (p.IP/1.0) - p.ER / a.Inn) * a.PO*/ > 0, 
				        a.PO + 2*(a.A - a.CS) - 8*a.E + 6*a.DP - 4*a.PB - 2*a.SB + 4*a.CS /*+ 2*(p.ER / (p.IP/1.0) - a.ER / a.Inn) * a.PO*/, 0), 0) AS ClaimPoints
FROM
	(
	SELECT
		c.Year
		, c.Lg
		, c.Tm
		, c.name as Name
		, c.`Name-additional` AS BBRefID
		, c.Inn
		, c.PO
		, c.A
		, c.E
		, c.DP
		, c.PB
		, c.SB
		, c.CS
	FROM bbref_fielding_c c
	WHERE c.Lg IN ('AA','AL','FL','NA','NL','PL','UA') AND c.Year >= 1901
	) a
JOIN temp_Yr_Lg_Tm_Pit_Totals p ON a.Year = p.Year AND a.Lg = p.Lg AND a.Tm = p.Tm

UNION ALL

SELECT
	a.Year
	, a.Lg
	, a.Tm
	, '1b' AS Pos
	, a.Name
	, a.BBRefID
	, a.Inn
	, a.PO
	, a.A
	, a.E
	, a.DP
	, '' AS PB
	, '' AS SB
	, '' AS CS
	, IF(a.Inn > 0,IF(a.PO + 2*a.A - 5*a.E > 0, a.PO + 2*a.A - 5*a.E ,0), 0) AS ClaimPoints
FROM
	(
	SELECT
		fb.Year
		, fb.Lg
		, fb.Tm
		, fb.name as Name
		, fb.`Name-additional` AS BBRefID
		, fb.Inn
		, fb.PO
		, fb.A
		, fb.E
		, fb.DP
	FROM bbref_fielding_1b fb
	WHERE fb.Lg IN ('AA','AL','FL','NA','NL','PL','UA') AND fb.Year >= 1901
	) a

UNION ALL

SELECT
	a.Year
	, a.Lg
	, a.Tm
	, '2b' AS Pos
	, a.Name
	, a.BBRefID
	, a.Inn
	, a.PO
	, a.A
	, a.E
	, a.DP
	, '' AS PB
	, '' AS SB
	, '' AS CS
	, IF(a.Inn > 0,IF(a.PO + 2*a.A - 5*a.E + 2*a.`2bRBP` + a.DP > 0, a.PO + 2*a.A - 5*a.E + 2*a.`2bRBP` + a.DP ,0), 0) AS ClaimPoints
FROM
	(
	SELECT
		sb.Year
		, sb.Lg
		, sb.Tm
		, sb.name as Name
		, sb.`Name-additional` AS BBRefID
		, sb.Inn
		, sb.PO
		, sb.A
		, sb.E
		, sb.DP
		, IF(sb.Inn > 0, IF(((sb.PO + sb.A) / sb.Inn - (pf.PO_2B_TM + pf.A_2B_TM) / p.IP) * sb.Inn > 0,
							  ((sb.PO + sb.A) / sb.Inn - (pf.PO_2B_TM + pf.A_2B_TM) / p.IP) * sb.Inn, 0), 0) AS `2bRBP`
	FROM bbref_fielding_2b sb
	JOIN temp_Yr_Lg_Tm_Position_Fielding pf ON sb.Year = pf.Year AND sb.Lg = pf.Lg AND sb.Tm = pf.Tm
	JOIN temp_Yr_Lg_Tm_Pit_totals p ON pf.Year = p.Year AND pf.Lg = p.Lg AND pf.Tm = p.Tm
	WHERE sb.Lg IN ('AA','AL','FL','NA','NL','PL','UA') AND sb.Year >= 1901
	) a


UNION ALL

SELECT
	a.Year
	, a.Lg
	, a.Tm
	, '3b' AS Pos
	, a.Name
	, a.BBRefID
	, a.Inn
	, a.PO
	, a.A
	, a.E
	, a.DP
	, '' AS PB
	, '' AS SB
	, '' AS CS
	, IF(a.Inn > 0,IF(a.PO + 2*a.A - 5*a.E + 2*a.`3bRBP` + a.DP > 0, a.PO + 2*a.A - 5*a.E + 2*a.`3bRBP` + a.DP ,0), 0) AS ClaimPoints
FROM
	(
	SELECT
		tb.Year
		, tb.Lg
		, tb.Tm
		, tb.name as Name
		, tb.`Name-additional` AS BBRefID
		, tb.Inn
		, tb.PO
		, tb.A
		, tb.E
		, tb.DP
		, IF(tb.Inn > 0, IF(((tb.PO + tb.A) / tb.Inn - (pf.PO_3B_TM + pf.A_3B_TM) / p.IP) * tb.Inn > 0,
							  ((tb.PO + tb.A) / tb.Inn - (pf.PO_3B_TM + pf.A_3B_TM) / p.IP) * tb.Inn, 0), 0) AS `3bRBP`
	FROM bbref_fielding_3b tb
	JOIN temp_Yr_Lg_Tm_Position_Fielding pf ON tb.Year = pf.Year AND tb.Lg = pf.Lg AND tb.Tm = pf.Tm
	JOIN temp_Yr_Lg_Tm_Pit_totals p ON pf.Year = p.Year AND pf.Lg = p.Lg AND pf.Tm = p.Tm
	WHERE tb.Lg IN ('AA','AL','FL','NA','NL','PL','UA') AND tb.Year >= 1901
	) a



UNION ALL

SELECT
	a.Year
	, a.Lg
	, a.Tm
	, 'ss' AS Pos
	, a.Name
	, a.BBRefID
	, a.Inn
	, a.PO
	, a.A
	, a.E
	, a.DP
	, '' AS PB
	, '' AS SB
	, '' AS CS
	, IF(a.Inn > 0,IF(a.PO + 2*a.A - 5*a.E + 2*a.`ssRBP` + a.DP > 0, a.PO + 2*a.A - 5*a.E + 2*a.`ssRBP` + a.DP ,0), 0) AS ClaimPoints
FROM
	(
	SELECT
		ss.Year
		, ss.Lg
		, ss.Tm
		, ss.name as Name
		, ss.`Name-additional` AS BBRefID
		, ss.Inn
		, ss.PO
		, ss.A
		, ss.E
		, ss.DP
		, IF(ss.Inn > 0, IF(((ss.PO + ss.A) / ss.Inn - (pf.PO_SS_TM + pf.A_SS_TM) / p.IP) * ss.Inn > 0,
							  ((ss.PO + ss.A) / ss.Inn - (pf.PO_SS_TM + pf.A_SS_TM) / p.IP) * ss.Inn, 0), 0) AS `ssRBP`
	FROM bbref_fielding_ss ss
	JOIN temp_Yr_Lg_Tm_Position_Fielding pf ON ss.Year = pf.Year AND ss.Lg = pf.Lg AND ss.Tm = pf.Tm
	JOIN temp_Yr_Lg_Tm_Pit_totals p ON pf.Year = p.Year AND pf.Lg = p.Lg AND pf.Tm = p.Tm
	WHERE ss.Lg IN ('AA','AL','FL','NA','NL','PL','UA') AND ss.Year >= 1901
	) a





UNION ALL

SELECT
	a.Year
	, a.Lg
	, a.Tm
	, 'of' AS Pos
	, a.Name
	, a.BBRefID
	, a.Inn
	, a.PO
	, a.A
	, a.E
	, a.DP
	, '' AS PB
	, '' AS SB
	, '' AS CS
	, IF(a.Inn > 0,IF(a.PO + 4*a.A - 5*a.E + 2*a.`ofRBP` > 0, a.PO + 4*a.A - 5*a.E + 2*a.`ofRBP`, 0), 0) AS ClaimPoints
FROM
	(
	SELECT
		fof.Year
		, fof.Lg
		, fof.Tm
		, fof.name as Name
		, fof.`Name-additional` AS BBRefID
		, fof.Inn
		, fof.PO
		, fof.A
		, fof.E
		, fof.DP
		, pf.PO_OF_TM, pf.A_OF_TM, p.IP
		, IF(fof.Inn > 0, IF(((fof.PO + fof.A) / (fof.Inn/1.0) - (pf.PO_OF_TM + pf.A_OF_TM) / (3*p.IP/1.0)) * fof.Inn > 0,
							   ((fof.PO + fof.A) / (fof.Inn/1.0) - (pf.PO_OF_TM + pf.A_OF_TM) / (3*p.IP/1.0)) * fof.Inn, 0), 0) AS `ofRBP`
	FROM bbref_fielding_of fof
	JOIN temp_Yr_Lg_Tm_Position_Fielding pf ON fof.Year = pf.Year AND fof.Lg = pf.Lg AND fof.Tm = pf.Tm
	JOIN temp_Yr_Lg_Tm_Pit_totals p ON pf.Year = p.Year AND pf.Lg = p.Lg AND pf.Tm = p.Tm
	WHERE fof.Lg IN ('AA','AL','FL','NA','NL','PL','UA') AND fof.Year >= 1901
	) a
;





/* Calculate Fielding Win Shares by Position */
/* Win Share totals in the Adj column have been adjusted 
   for team schedule length scaled to 162 games */
CREATE TABLE temp_fielding_win_shares_final AS
WITH yr_lg_tm_pos_claim_points_cte AS
	(
    SELECT year, lg, tm, pos, sum(claimpoints) as pos_claimpoints from temp_Yr_Lg_Tm_Pos_Claim_Points group by year, lg, tm, pos
    ), team_games AS
    (
    SELECT year, lg, tm, SUM(GS) AS gs FROM bbref_pitching_standard WHERE tm <> 'TOT' GROUP BY year, lg, tm
    )
SELECT
	cp.Year
	, cp.Lg
	, cp.Tm
	, cp.Name
	, cp.Pos
	, cp.BBRefID
	, cp.Inn
    , cp.Inn * 162 / tg.gs AS Inn_adj
	, cp.ClaimPoints / cp_pos.pos_ClaimPoints *
		CASE WHEN cp.pos = 'c' THEN fws.cFW WHEN cp.pos = '1b' THEN fws.`1bFW` WHEN cp.pos = '2b' THEN fws.`2bFW` 
			WHEN cp.pos = '3b' THEN fws.`3bFW` WHEN cp.pos = 'ss' THEN fws.ssFW WHEN cp.pos = 'of' THEN fws.ofFW END AS FWS
	, cp.ClaimPoints / cp_pos.pos_ClaimPoints * 
		CASE WHEN cp.pos = 'c' THEN fws.cFW WHEN cp.pos = '1b' THEN fws.`1bFW` WHEN cp.pos = '2b' THEN fws.`2bFW` 
			WHEN cp.pos = '3b' THEN fws.`3bFW` WHEN cp.pos = 'ss' THEN fws.ssFW WHEN cp.pos = 'of' THEN fws.ofFW END * 162 / tg.gs AS FWSadj
	, cp.ClaimPoints / cp_pos.pos_ClaimPoints * 
		CASE WHEN cp.pos = 'c' THEN fws.cFW WHEN cp.pos = '1b' THEN fws.`1bFW` WHEN cp.pos = '2b' THEN fws.`2bFW` 
			WHEN cp.pos = '3b' THEN fws.`3bFW` WHEN cp.pos = 'ss' THEN fws.ssFW WHEN cp.pos = 'of' THEN fws.ofFW END / (IF(cp.Inn > 0, cp.Inn, 1) / 1.0) * 1458 AS `FWS/1458`
FROM temp_Yr_Lg_Tm_Pos_Claim_Points cp
JOIN yr_lg_tm_pos_claim_points_cte as cp_pos ON cp.Year = cp_pos.Year AND cp.Lg = cp_pos.Lg AND cp.Tm = cp_pos.Tm AND cp.Pos = cp_pos.Pos
JOIN temp_Yr_Lg_Tm_Pos_FWin_Shares fws ON cp.Year = fws.Year AND cp.Lg = fws.Lg AND cp.Tm = fws.Tm 
JOIN team_games tg ON cp.year = tg.year AND cp.lg = tg.lg AND cp.tm = tg.tm
WHERE cp.Lg IN ('AA','AL','FL','NA','NL','PL','UA') AND cp.Year >= 1901

and cp.year = 1918 and cp.bbrefid = 'milleot01'

ORDER BY cp.Pos, cp.Year, cp.Lg, cp.Tm
;

