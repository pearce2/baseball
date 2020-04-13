/* Range by Age */

-- Added year >= 1997 to get contiguous block of seasons with range ratings of 1-5 instead of 1-4

DECLARE @Pos varchar(2) = 'C'

select lastname, firstname, retroid, [16],[17],[18],[19],[20],[21],[22],[23],[24],[25],[26],[27],[28],[29],[30], 
	[31],[32],[33],[34],[35],[36],[37],[38],[39],[40],[41],[42],[43],[44],[45],[46],[47],[48],[49],[50] 
from 
	(
	-- Position 1
	select
		lastname,
		firstname,
		retroid,
		age,
		cast(rg1 as float) as rg
	from strat.AllBatters
	where pos1 = @Pos
		and year >= 1997

	UNION ALL

	-- Position 2
	select
		lastname,
		firstname,
		retroid,
		age,
		cast(rg2 as float)
	from strat.AllBatters
	where pos2 = @Pos
		and year >= 1997

	UNION ALL

	-- Position 3
	select
		lastname,
		firstname,
		retroid,
		age,
		cast(rg3 as float)
	from strat.AllBatters
	where pos3 = @Pos
		and year >= 1997

	UNION ALL

	-- Position 4
	select
		lastname,
		firstname,
		retroid,
		age,
		cast(rg4 as float)
	from strat.AllBatters
	where pos4 = @Pos
		and year >= 1997

	UNION ALL

	-- Position 5
	select
		lastname,
		firstname,
		retroid,
		age,
		cast(rg5 as float)
	from strat.AllBatters
	where pos5 = @Pos
		and year >= 1997

	UNION ALL

	-- Position 6
	select
		lastname,
		firstname,
		retroid,
		age,
		cast(rg6 as float)
	from strat.AllBatters
	where pos6 = @Pos
		and year >= 1997

	UNION ALL

	-- Position 7
	select
		lastname,
		firstname,
		retroid,
		age,
		cast(rg7 as float)
	from strat.AllBatters
	where pos7 = @Pos
		and year >= 1997

	UNION ALL

	-- Position 8
	select
		lastname,
		firstname,
		retroid,
		age,
		cast(rg8 as float)
	from strat.AllBatters
	where pos8 = @Pos
		and year >= 1997
	) z

pivot (min(rg) for age in ([16],[17],[18],[19],[20],[21],[22],[23],[24],[25],[26],[27],[28],[29],[30], 
	[31],[32],[33],[34],[35],[36],[37],[38],[39],[40],[41],[42],[43],[44],[45],[46],[47],[48],[49],[50])) as pivottable

order by retroid


