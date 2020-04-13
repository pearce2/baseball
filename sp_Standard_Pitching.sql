USE [Baseball]
GO

/****** Object:  StoredProcedure [dbo].[sp_StandardPitching]    Script Date: 4/13/2020 12:46:59 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



-- =============================================
-- Author:		<Author,,Name>
-- Create date: <Create Date,,>
-- Description:	<Description,,>
-- =============================================
ALTER PROCEDURE [dbo].[sp_StandardPitching]

	-- Add the parameters for the stored procedure here

@StartYear VARCHAR(4),
@EndYear VARCHAR(4)

AS

BEGIN

	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    -- Insert statements for procedure here

/**/


--------------------------------------------------------------------------------------------------------------------
-- Get Event File data for seasons of interest and store in temp table
--------------------------------------------------------------------------------------------------------------------

Select *
Into #EventsTemp
from Retrosheet.Events where Substring(Game_ID, 4, 4) between @StartYear and @EndYear






--------------------------------------------------------------------------------------------------------------------
-- Get Games Pitched from Event File data
--------------------------------------------------------------------------------------------------------------------

Select Year, Team, RetroID, count(*) as G
INTO #GamesPitched
FROM
	(

	-- Get unique game ID's (hence UNION instead of UNION ALL) for each Year/player ID/Team combination for player ID's
	-- appearing in the Pitcher or Responsible Pitcher fields

	Select
		Substring(Game_ID, 4, 4) as Year,
		pit_id as RetroID,
		CASE WHEN Bat_home_id = 1 THEN away_team_id ELSE left(Game_ID,3) END as Team,
		Game_ID
	from #EventsTemp where pit_id is not null

	UNION

	Select
		Substring(Game_ID, 4, 4) as Year,
		Resp_Pit_id as RetroID,
		CASE WHEN Bat_home_id = 1 THEN away_team_id ELSE left(Game_ID,3) END as Team,
		Game_ID
	from #EventsTemp where Resp_pit_id is not null
	) gp
where ltrim(rtrim(RetroID)) != ''
group by Year, Team, RetroID


--------------------------------------------------------------------------------------------------------------------
-- Get Games Started, Wins, Losses, and Saves from Game Log data
--------------------------------------------------------------------------------------------------------------------



Select Year, Team, RetroID, sum(GS) as GS, sum(W) as W, Sum(L) as L, sum(Sv) as Sv
INTO #GameLogStats
from
	(
	-- Home Games Started
	select
		left(yyyymmdd,4) as Year,
		HomTeam as Team,
		HomSPID as RetroID,
		1 as GS,
		0 as W,
		0 as L,
		0 as Sv
	from Retrosheet.GameLogs where left(yyyymmdd,4) between @StartYear and @EndYear

	UNION ALL

	-- Visiting Games Started
	select
		left(yyyymmdd,4) as Year,
		VisTeam as Team,
		VisSPID as RetroID,
		1 as GS,
		0 as W,
		0 as L,
		0 as Sv
	from Retrosheet.GameLogs where left(yyyymmdd,4) between @StartYear and @EndYear

	UNION ALL

	-- Home Wins
	select
		left(yyyymmdd,4) as Year,
		HomTeam as Team,
		WinPitID as RetroID,
		0 as GS,
		1 as W,
		0 as L,
		0 as Sv
	from Retrosheet.GameLogs where left(yyyymmdd,4) between @StartYear and @EndYear and HomScore > VisScore

	UNION ALL

	-- Visitor Wins
	select
		left(yyyymmdd,4) as Year,
		VisTeam as Team,
		WinPitID as RetroID,
		0 as GS,
		1 as W,
		0 as L,
		0 as Sv
	from Retrosheet.GameLogs where left(yyyymmdd,4) between @StartYear and @EndYear and VisScore > HomScore

	UNION ALL

	-- Home Losses
	select
		left(yyyymmdd,4) as Year,
		HomTeam as Team,
		LosPitID as RetroID,
		0 as GS,
		0 as W,
		1 as L,
		0 as Sv
	from Retrosheet.GameLogs where left(yyyymmdd,4) between @StartYear and @EndYear and HomScore < VisScore

	UNION ALL

	-- Visiting Losses
	select
		left(yyyymmdd,4) as Year,
		VisTeam as Team,
		LosPitID as RetroID,
		0 as GS,
		0 as W,
		1 as L,
		0 as Sv
	from Retrosheet.GameLogs where left(yyyymmdd,4) between @StartYear and @EndYear and VisScore < HomScore

	UNION ALL

	-- Home Saves
	select
		left(yyyymmdd,4) as Year,
		HomTeam as Team,
		SvPitID as RetroID,
		0 as GS,
		0 as W,
		0 as L,
		1 as Sv
	from Retrosheet.GameLogs where left(yyyymmdd,4) between @StartYear and @EndYear and HomScore > VisScore

	UNION ALL

	-- Visiting Saves
	select
		left(yyyymmdd,4) as Year,
		VisTeam as Team,
		SvPitID as RetroID,
		0 as GS,
		0 as W,
		0 as L,
		1 as Sv
	from Retrosheet.GameLogs where left(yyyymmdd,4) between @StartYear and @EndYear and VisScore > HomScore
	) as wl
where RetroID != ''
group by Year, Team, RetroID
order by Year, Team, RetroID



--------------------------------------------------------------------------------------------------------------------
-- Get Pitching Events
--------------------------------------------------------------------------------------------------------------------


Select

	-- Top level stats
	Substring(Game_ID, 4, 4) as Year,
	Resp_pit_id,
	CASE WHEN Bat_home_id = 1 THEN away_team_id ELSE LEFT(Game_ID,3) END as Team,
	SUM(CASE WHEN Bat_Event_Fl = 'T' THEN 1 ELSE 0 END) as PA,
	SUM(CASE WHEN AB_Fl = 'T' THEN 1 ELSE 0 END) as AB,
	SUM(CASE WHEN H_cd > 0 THEN 1 ELSE 0 END) as H,
	SUM(CASE WHEN H_cd = 2 THEN 1 ELSE 0 END) as DB,
	SUM(CASE WHEN H_cd = 3 THEN 1 ELSE 0 END) as TP,
	SUM(CASE WHEN H_cd = 4 THEN 1 ELSE 0 END) as HR, 
	SUM(RBI_ct) as RBI,
	SUM(event_outs_ct) as Outs,
	SUM(CASE WHEN Event_cd in (14,15) THEN 1 ELSE 0 END) as BB,
	SUM(CASE WHEN Event_cd = 3 THEN 1 ELSE 0 END) as SO,
	SUM(CASE WHEN DP_Fl = 'T' and BattedBall_cd = 'G' THEN 1 ELSE 0 END) as GDP,
	SUM(CASE WHEN Event_cd = 16 THEN 1 ELSE 0 END) as HBP,
	SUM(CASE WHEN SH_Fl = 'T' THEN 1 ELSE 0 END) as SH,
	SUM(CASE WHEN SF_Fl = 'T' THEN 1 ELSE 0 END) as SF,
	SUM(CASE WHEN Event_cd = 15 THEN 1 ELSE 0 END) as IBB,

	-- Stats vs Left Handed Batters
	SUM(CASE WHEN Bat_Event_Fl = 'T' and resp_bat_hand_cd = 'L' THEN 1 ELSE 0 END) as PA_L,
	SUM(CASE WHEN AB_Fl = 'T' and resp_bat_hand_cd = 'L'  THEN 1 ELSE 0 END) as AB_L,
	SUM(CASE WHEN H_cd > 0 and resp_bat_hand_cd = 'L'  THEN 1 ELSE 0 END) as H_L,
	SUM(CASE WHEN H_cd = 2 and resp_bat_hand_cd = 'L'  THEN 1 ELSE 0 END) as DB_L,
	SUM(CASE WHEN H_cd = 3 and resp_bat_hand_cd = 'L'  THEN 1 ELSE 0 END) as TP_L,
	SUM(CASE WHEN H_cd = 4 and resp_bat_hand_cd = 'L'  THEN 1 ELSE 0 END) as HR_L,
	SUM(CASE WHEN resp_bat_hand_cd = 'L' THEN RBI_ct ELSE 0 END) as RBI_L,
	SUM(CASE WHEN Event_cd in (14,15) and resp_bat_hand_cd = 'L' THEN 1 ELSE 0 END) as BB_L,
	SUM(CASE WHEN Event_cd = 3 and resp_bat_hand_cd = 'L' THEN 1 ELSE 0 END) as SO_L,
	SUM(CASE WHEN DP_Fl = 'T' and BattedBall_cd = 'G' and resp_bat_hand_cd = 'L' THEN 1 ELSE 0 END) as GDP_L,
	SUM(CASE WHEN Event_cd = 16 and resp_bat_hand_cd = 'L' THEN 1 ELSE 0 END) as HBP_L,
	SUM(CASE WHEN SH_Fl = 'T' and resp_bat_hand_cd = 'L' THEN 1 ELSE 0 END) as SH_L,
	SUM(CASE WHEN SF_Fl = 'T' and resp_bat_hand_cd = 'L' THEN 1 ELSE 0 END) as SF_L,
	SUM(CASE WHEN Event_cd = 15 and resp_bat_hand_cd = 'L' THEN 1 ELSE 0 END) as IBB_L,

	-- Stats vs Right Handed Batters
	SUM(CASE WHEN Bat_Event_Fl = 'T' and resp_bat_hand_cd = 'R' THEN 1 ELSE 0 END) as PA_R,
	SUM(CASE WHEN AB_Fl = 'T' and resp_bat_hand_cd = 'R'  THEN 1 ELSE 0 END) as AB_R,
	SUM(CASE WHEN H_cd > 0 and resp_bat_hand_cd = 'R'  THEN 1 ELSE 0 END) as H_R,
	SUM(CASE WHEN H_cd = 2 and resp_bat_hand_cd = 'R'  THEN 1 ELSE 0 END) as DB_R,
	SUM(CASE WHEN H_cd = 3 and resp_bat_hand_cd = 'R'  THEN 1 ELSE 0 END) as TP_R,
	SUM(CASE WHEN H_cd = 4 and resp_bat_hand_cd = 'R'  THEN 1 ELSE 0 END) as HR_R,
	SUM(CASE WHEN resp_bat_hand_cd = 'R' THEN RBI_ct ELSE 0 END) as RBI_R,
	SUM(CASE WHEN Event_cd in (14,15) and resp_bat_hand_cd = 'R' THEN 1 ELSE 0 END) as BB_R,
	SUM(CASE WHEN Event_cd = 3 and resp_bat_hand_cd = 'R' THEN 1 ELSE 0 END) as SO_R,
	SUM(CASE WHEN DP_Fl = 'T' and BattedBall_cd = 'G' and resp_bat_hand_cd = 'R' THEN 1 ELSE 0 END) as GDP_R,
	SUM(CASE WHEN Event_cd = 16 and resp_bat_hand_cd = 'R' THEN 1 ELSE 0 END) as HBP_R,
	SUM(CASE WHEN SH_Fl = 'T' and resp_bat_hand_cd = 'R' THEN 1 ELSE 0 END) as SH_R,
	SUM(CASE WHEN SF_Fl = 'T' and resp_bat_hand_cd = 'R' THEN 1 ELSE 0 END) as SF_R,
	SUM(CASE WHEN Event_cd = 15 and resp_bat_hand_cd = 'R' THEN 1 ELSE 0 END) as IBB_R
INTO #PitchingEvents
from #EventsTemp e
Group By Substring(Game_ID, 4, 4), Resp_Pit_id, CASE WHEN bat_home_id = 1 THEN away_team_id ELSE LEFT(Game_ID,3) END





--------------------------------------------------------------------------------------------------------------------
-- Get Stolen Bases, Caught Stealing, Pickoffs, and PickOff-Caught Stealing
--------------------------------------------------------------------------------------------------------------------

Select Year, RetroID, Team, sum(SB) as SB, sum(CS) as CS, sum(SB2) as SB2, sum(SB3) as SB3, sum(SBH) as SBH, sum(CS2) as CS2, sum(CS3) as CS3, sum(CSH) as CSH,
	sum(PkO) as PkO, sum(POCS) as POCS
INTO #SB
From
	(
	-- Steals of 2B
	Select
		Substring(Game_ID, 4, 4) as Year,
		resp_pit_id as RetroID,
		CASE WHEN bat_home_id = 1 THEN away_team_id ELSE left(Game_ID,3) END as Team,
		1 as SB,
		0 as CS,
		1 as SB2,
		0 as SB3,
		0 as SBH,
		0 as CS2,
		0 as CS3,
		0 as CSH,
		0 as PkO, 
		0 as POCS
	from #EventsTemp where run1_sb_fl = 'T'

	UNION ALL

	--- Steals of 3B
	Select
		Substring(Game_ID, 4, 4) as Year,
		resp_pit_id as RetroID,
		CASE WHEN bat_home_id = 1 THEN away_team_id ELSE left(Game_ID,3) END as Team,
		1 as SB,
		0 as CS,
		0 as SB2,
		1 as SB3,
		0 as SBH,
		0 as CS2,
		0 as CS3,
		0 as CSH,
		0 as PkO,
		0 as POCS
	from #EventsTemp where run2_sb_fl = 'T'

	UNION ALL

	-- Steals of Home
	Select
		Substring(Game_ID, 4, 4) as Year,
		resp_pit_id as RetroID,
		CASE WHEN bat_home_id = 1 THEN away_team_id ELSE left(Game_ID,3) END as Team,
		1 as SB,
		0 as CS,
		0 as SB2,
		0 as SB3,
		1 as SBH,
		0 as CS2,
		0 as CS3,
		0 as CSH,
		0 as PkO,
		0 as POCS
	from #EventsTemp where run3_sb_fl = 'T'

	UNION ALL

	-- Caught Stealing 2B
	Select
		Substring(Game_ID, 4, 4) as Year,
		resp_pit_id as RetroID,
		CASE WHEN bat_home_id = 1 THEN away_team_id ELSE left(Game_ID,3) END as Team,
		0 as SB,
		1 as CS,
		0 as SB2,
		0 as SB3,
		0 as SBH,
		1 as CS2,
		0 as CS3,
		0 as CSH,
		0 as PkO, 
		0 as POCS
	from #EventsTemp where run1_cs_fl = 'T' and run1_pk_fl = 'F'

	UNION ALL

	-- Caught Stealing 3B
	Select
		Substring(Game_ID, 4, 4) as Year,
		resp_pit_id as RetroID,
		CASE WHEN bat_home_id = 1 THEN away_team_id ELSE left(Game_ID,3) END as Team,
		0 as SB,
		1 as CS,
		0 as SB2,
		0 as SB3,
		0 as SBH,
		0 as CS2,
		1 as CS3,
		0 as CSH,
		0 as PkO,
		0 as POCS
	from #EventsTemp where run2_cs_fl = 'T' and run2_pk_fl = 'F'

	UNION ALL

	-- Caught Stealing Home
	Select
		Substring(Game_ID, 4, 4) as Year,
		resp_pit_id as RetroID,
		CASE WHEN bat_home_id = 1 THEN away_team_id ELSE left(Game_ID,3) END as Team,
		0 as SB,
		1 as CS,
		0 as SB2,
		0 as SB3,
		0 as SBH,
		0 as CS2,
		0 as CS3,
		1 as CSH,
		0 as PkO,
		0 as POCS
	from #EventsTemp where run3_cs_fl = 'T' and run3_pk_fl = 'F'

	UNION ALL

	-- Picked Off 1B
	Select
		Substring(Game_ID, 4, 4) as Year,
		resp_pit_id as RetroID,
		CASE WHEN bat_home_id = 1 THEN away_team_id ELSE left(Game_ID,3) END as Team,
		0 as SB,
		0 as CS,
		0 as SB2,
		0 as SB3,
		0 as SBH,
		0 as CS2,
		0 as CS3,
		0 as CSH,
		1 as PkO, 
		0 as POCS
	from #EventsTemp where run1_cs_fl = 'T' and run1_pk_fl = 'F'

	UNION ALL

	-- Picked Off 2B
	Select
		Substring(Game_ID, 4, 4) as Year,
		resp_pit_id as RetroID,
		CASE WHEN bat_home_id = 1 THEN away_team_id ELSE left(Game_ID,3) END as Team,
		0 as SB,
		0 as CS,
		0 as SB2,
		0 as SB3,
		0 as SBH,
		0 as CS2,
		0 as CS3,
		0 as CSH,
		1 as PkO,
		0 as POCS
	from #EventsTemp where run2_cs_fl = 'T' and run2_pk_fl = 'F'

	UNION ALL

	-- Picked Off 3B
	Select
		Substring(Game_ID, 4, 4) as Year,
		resp_pit_id as RetroID,
		CASE WHEN bat_home_id = 1 THEN away_team_id ELSE left(Game_ID,3) END as Team,
		0 as SB,
		0 as CS,
		0 as SB2,
		0 as SB3,
		0 as SBH,
		0 as CS2,
		0 as CS3,
		0 as CSH,
		1 as PkO,
		0 as POCS
	from #EventsTemp where run3_cs_fl = 'T' and run3_pk_fl = 'F'

	UNION ALL

	-- Picked Off/Caught Stealing 2B
	Select
		Substring(Game_ID, 4, 4) as Year,
		resp_pit_id as RetroID,
		CASE WHEN bat_home_id = 1 THEN away_team_id ELSE left(Game_ID,3) END as Team,
		0 as SB,
		1 as CS,
		0 as SB2,
		0 as SB3,
		0 as SBH,
		1 as CS2,
		0 as CS3,
		0 as CSH,
		1 as PkO,
		1 as POCS
	from #EventsTemp where run1_cs_fl = 'T' and run1_pk_fl = 'T'

	UNION ALL

	-- Picked Off/Caught Stealing 3B
	Select
		Substring(Game_ID, 4, 4) as Year,
		resp_pit_id as RetroID,
		CASE WHEN bat_home_id = 1 THEN away_team_id ELSE left(Game_ID,3) END as Team,
		0 as SB,
		1 as CS,
		0 as SB2,
		0 as SB3,
		0 as SBH,
		0 as CS2,
		1 as CS3,
		0 as CSH,
		1 as PkO,
		1 as POCS
	from #EventsTemp where run2_cs_fl = 'T' and run2_pk_fl = 'T'

	UNION ALL

	-- Picked Off/Caught Stealing Home
	Select
		Substring(Game_ID, 4, 4) as Year,
		resp_pit_id as RetroID,
		CASE WHEN bat_home_id = 1 THEN away_team_id ELSE left(Game_ID,3) END as Team,
		0 as SB,
		1 as CS,
		0 as SB2,
		0 as SB3,
		0 as SBH,
		0 as CS2,
		0 as CS3,
		1 as CSH,
		1 as PkO,
		1 as POCS
	from #EventsTemp where run3_cs_fl = 'T' and run3_pk_fl = 'T'
	) sb
group by Year, RetroID, Team



--------------------------------------------------------------------------------------------------------------------
-- Get Baserunning Stats
--------------------------------------------------------------------------------------------------------------------

-- Get Count of batters who reach base on an error
Select Year, RetroID, Team, sum(ROE) as ROE
INTO #ROE
From
	(
	Select
		Substring(Game_ID, 4, 4) as Year,
		resp_pit_id as RetroID,
		CASE WHEN bat_home_id = 1 THEN away_team_id ELSE left(Game_ID,3) END as Team,
		1 as ROE
	from #EventsTemp where Bat_Event_Fl = 'T' and event_cd = 18
	) roe
Group by Year, RetroID, Team

-- Get Stolen Base Opportunities
Select Year, RetroID, Team, sum(SBO) as SBO
INTO #SBO
From
	(
	-- Batter event where runner on 1st base and 2nd base is open
	Select
		Substring(Game_ID, 4, 4) as Year,
		resp_pit_id as RetroID,
		CASE WHEN bat_home_id = 1 THEN away_team_id ELSE left(Game_ID,3) END as Team,
		1 as SBO
	from #EventsTemp where Bat_Event_Fl = 'T' and base1_run_id != '' and base2_run_id = ''

	UNION ALL

	-- Batter event where runner on 2nd base and 3rd base is open
	Select
		Substring(Game_ID, 4, 4) as Year,
		resp_pit_id as RetroID,
		CASE WHEN bat_home_id = 1 THEN away_team_id ELSE left(Game_ID,3) END as Team,
		1 as SBO
	from #EventsTemp where Bat_Event_Fl = 'T' and base2_run_id != '' and base3_run_id = ''
	) sbo
Group by Year, RetroID, Team






--------------------------------------------------------------------------------------------------------------------
-- Get Runs Allowed and Earned Runs Allowed
--------------------------------------------------------------------------------------------------------------------

Select Year, RetroID, Team, sum(RunsScored) as R, sum(EarnedRuns) as ER
INTO #RunsScored
FROM
	(
	-- Runner on 1st scores
	Select
		Substring(Game_ID, 4, 4) as Year,
		run1_resp_pit_id as RetroID,
		CASE WHEN bat_home_id = 1 THEN away_team_id ELSE left(Game_ID,3) END as Team,
		1 as RunsScored,
		CASE WHEN  run1_dest_id in (4,6) THEN 1 ELSE 0 END as EarnedRuns
	from #EventsTemp where run1_dest_id >= 4

	UNION ALL

	-- Runner on 2nd scores
	Select
		Substring(Game_ID, 4, 4) as Year,
		run2_resp_pit_id as RetroID,
		CASE WHEN bat_home_id = 1 THEN away_team_id ELSE left(Game_ID,3) END as Team,
		1 as RunsScored,
		CASE WHEN run2_dest_id in (4,6) THEN 1 ELSE 0 END as EarnedRuns
	from #EventsTemp where run2_dest_id >= 4
	
	UNION ALL

	-- Runner on 3rd scores
	Select
		Substring(Game_ID, 4, 4) as Year,
		run3_resp_pit_id as RetroID,
		CASE WHEN bat_home_id = 1 THEN away_team_id ELSE left(Game_ID,3) END as Team,
		1 as RunsScored,
		CASE WHEN run3_dest_id in (4,6) THEN 1 ELSE 0 END as EarnedRuns
	from #EventsTemp where run3_dest_id >= 4

	UNION ALL

	-- Batter scores
	Select
		Substring(Game_ID, 4, 4) as Year,
		resp_pit_id as RetroID,
		CASE WHEN bat_home_id = 1 THEN away_team_id ELSE left(Game_ID,3) END as Team,
		1 as RunsScored,
		CASE WHEN bat_dest_id in (4,6) THEN 1 ELSE 0 END as EarnedRuns
	from #EventsTemp where bat_dest_id >= 4
	) r
Group by Year, RetroID, Team



	


--------------------------------------------------------------------------------------------------------------------
-- Final Output
--------------------------------------------------------------------------------------------------------------------


select
	g.Year,
	g.Team,
	p.name_last,
	p.name_first,
	g.RetroID,
	isnull(g.G,0) as G,
	isnull(gl.GS,0) as GS,
	isnull(e.Outs,0) as Outs,
	cast(cast(isnull(e.Outs/3,0) as varchar(3)) + '.' + cast(isnull(e.Outs % 3,0) as varchar(1)) as decimal(5,1)) as IP,
	isnull(R.R,0) as R,
	isnull(R.ER,0) as ER,
	CASE 
		WHEN e.outs = 0 and r.ER > 0 THEN 'inf'
		WHEN e.outs = 0 and r.ER = 0 THEN NULL
		WHEN e.outs > 0 and r.ER = 0 THEN cast(0 as decimal(4,2))
		ELSE cast(round(9 * (r.ER / (e.Outs/3.0)),2) as decimal(8,2))
	END as ERA,
	isnull(gl.W,0) as W,
	isnull(gl.L,0) as L,
	isnull(gl.SV,0) as SV,
	isnull(e.PA,0) as PA,
	isnull(e.AB,0) as AB,
	isnull(e.H,0) as H,
	isnull(e.DB,0) as DB,
	isnull(e.TP,0) as TP,
	isnull(e.HR,0) as HR,
	isnull(e.RBI,0) as RBI,
	isnull(s.SB,0) as SB,
	isnull(s.CS,0) as CS,
	isnull(e.BB,0) as BB,
	isnull(e.SO,0) as SO,
	CASE WHEN e.AB > 0 THEN cast(cast(e.H as float) / cast( e.AB as float) as decimal(5,3)) ELSE NULL END as AVG,
	CASE WHEN e.AB + e.BB + e.HBP + e.SF > 0 
		THEN cast((cast(e.H as float) + e.BB + e.HBP) / (cast(e.AB as float)+ e.BB + e.HBP + e.SF) as decimal(5,3)) ELSE NULL END as OBP,
	CASE WHEN e.AB > 0 THEN cast((cast(e.H as float) + e.DB + 2*e.TP + 3*e.HR) / cast(e.AB as float) as decimal(5,3)) ELSE NULL END as SLG,
	isnull(e.H,0) + isnull(e.DB,0) + 2*isnull(e.TP,0) + 3*isnull(e.HR,0) as TB,
	isnull(e.GDP,0) as GDP,
	isnull(e.HBP,0) as HBP,
	isnull(e.SH,0) as SH,
	isnull(e.SF,0) as SF,
	isnull(e.IBB,0) as IBB,
	'' as PlatoonStats,
	CASE WHEN e.PA > 0 THEN cast(cast(e.PA_L as float) / cast(e.PA as float) * 100 as decimal(3,0)) ELSE NULL END as PctVsLHP,
	CASE WHEN e.AB_L > 0 THEN cast(cast(e.H_L as float) / cast( e.AB_L as float) as decimal(5,3)) ELSE NULL END as AVG_L,
	CASE WHEN e.AB_L + e.BB_L + e.HBP_L + e.SF_L > 0 
		THEN cast((cast(e.H_L as float) + e.BB_L + e.HBP_L) / (cast(e.AB_L as float)+ e.BB_L + e.HBP_L + e.SF_L) as decimal(5,3)) ELSE NULL END as OBP_L,
	CASE WHEN e.AB_L > 0 THEN cast((cast(e.H_L as float) + e.DB_L + 2*e.TP_L + 3*e.HR_L) / cast(e.AB_L as float) as decimal(5,3)) ELSE NULL END as SLG_L,
	isnull(e.PA_L,0) as PA_L,
	isnull(e.AB_L,0) as AB_L,
	isnull(e.H_L,0) as H_L,
	isnull(e.DB_L,0) as DB_L,
	isnull(e.TP_L,0) as TP_L,
	isnull(e.HR_L,0) as HR_L,
	isnull(e.RBI_L,0) as RBI_L,
	isnull(e.BB_L,0) as BB_L,
	isnull(e.SO_L,0) as SO_L,
	isnull(e.H_L,0) + isnull(e.DB_L,0) + 2*isnull(e.TP_L,0) + 3*isnull(e.HR_L,0) as TB_L,
	isnull(e.GDP_L,0) as GDP_L,
	isnull(e.HBP_L,0) as HBP_L,
	isnull(e.SH_L,0) as SH_L,
	isnull(e.SF_L,0) as SF_L,
	isnull(e.IBB_L,0) as IBB_L,
	CASE WHEN e.AB_R > 0 THEN cast(cast(e.H_R as float) / cast( e.AB_R as float) as decimal(5,3)) ELSE NULL END as AVG_R,
	CASE WHEN e.AB_R + e.BB_R + e.HBP_R + e.SF_R > 0 
		THEN cast((cast(e.H_R as float) + e.BB_R + e.HBP_R) / (cast(e.AB_R as float)+ e.BB_R + e.HBP_R + e.SF_R) as decimal(5,3)) ELSE NULL END as OBP_R,
	CASE WHEN e.AB_R > 0 THEN cast((cast(e.H_R as float) + e.DB_R + 2*e.TP_R + 3*e.HR_R) / cast(e.AB_R as float) as decimal(5,3)) ELSE NULL END as SLG_R,
	isnull(e.PA_R,0) as PA_R,
	isnull(e.AB_R,0) as AB_R,
	isnull(e.H_R,0) as H_R,
	isnull(e.DB_R,0) as DB_R,
	isnull(e.TP_R,0) as TP_R,
	isnull(e.HR_R,0) as HR_R,
	isnull(e.RBI_R,0) as RBI_R,
	isnull(e.BB_R,0) as BB_R,
	isnull(e.SO_R,0) as SO_R,
	isnull(e.H_R,0) + isnull(e.DB_R,0) + 2*isnull(e.TP_R,0) + 3*isnull(e.HR_R,0) as TB_R,
	isnull(e.GDP_R,0) as GDP_R,
	isnull(e.HBP_R,0) as HBP_R,
	isnull(e.SH_R,0) as SH_R,
	isnull(e.SF_R,0) as SF_R,
	isnull(e.IBB_R,0) as IBB_R,
	'' as Baserunning,
	isnull(s.SB,0) as SB,
	isnull(s.CS,0) as CS,
	CASE WHEN (isnull(s.SB,0) + isnull(s.CS,0)) > 0 THEN cast(isnull(cast(s.SB as float),0) / (isnull(cast(s.SB as float),0) + isnull(s.CS,0)) * 100 as decimal(5,1)) ELSE NULL END as SBPct,
	isnull(sbo.sbo,0) as SBO,
	CASE WHEN isnull(sbo.sbo,0) > 0 THEN cast((isnull(cast(s.SB as float),0) + isnull(s.CS,0)) / isnull(cast(sbo.sbo as float),0) * 100 as decimal(6,2)) ELSE NULL END as JumpPct,
	isnull(s.sb2,0) as SB2,
	isnull(s.cs2,0) as CS2,
	isnull(s.sb3,0) as SB3,
	isnull(s.cs3,0) as CS3,
	isnull(s.sbh,0) as SBH,
	isnull(s.csh,0) as CSH,
	isnull(s.PkO,0) as PkO,
	isnull(s.POCS,0) as POCS
from #GamesPitched g 
left join #GameLogStats gl on g.Year = gl.Year and g.team = gl.team and g.retroid = gl.retroid
left join #RunsScored r on g.Year = r.Year and g.team = r.team and g.retroid = r.retroid
left join Chadwick.people p on g.Retroid = p.key_retro
left join #sb s on g.Year = s.Year and g.team = s.team and g.retroid = s.retroid
left join #PitchingEvents e on g.Year = e.Year and g.Team = e.Team and g.RetroID = e.resp_pit_id
left join #sbo sbo on g.Year = sbo.Year and g.Team = sbo.Team and g.RetroID = sbo.RetroID
where name_last is not null
order by g.Year, g.Team, p.Name_Last, p.Name_First, g.RetroID




--------------------------------------------------------------------------------------------------------------------
-- Drop Temp Tables
--------------------------------------------------------------------------------------------------------------------

DROP TABLE #EventsTemp
DROP TABLE #PitchingEvents
DROP TABLE #GameLogStats
DROP TABLE #GamesPitched
DROP TABLE #sb
DROP TABLE #ROE
DROP TABLE #RunsScored
DROP TABLE #SBO

END
GO


