# Baseball

This directory contains 2 SQL files and the two result sets for them.

## sp_StandardPitching

This script is a standard procedure I wrote for my Baseball database for ease of calling 
from Python or elsewhere and not having to embed all the SQL code in another scripting application.

The procedure is called with parameters for the start year and stop year.  This example uses 1987 only.

The proc itself first grabs all play-by-play records for the years of interest and puts them in 
temp tables for more efficient querying.  It runs several queries to compile different related 
information that is not necessarily play-by-play data, storing them all in temp tables with a
final query that assembles what I really want to see from each temp table.  If it were a smaller
number of temp tables or shorter queries, I might have used CTE's instead of multiple queries, but 
this design allowed me to develop and test each subsection easier.

Data for Games Started, Wins, Losses, and Saves comes from a table of Game Logs where each game has a single
record with many columns for the related data for each game.

Results are in the exec sp_standardpitching 1987,1987.csv file -- so named because that's the command to run it.

## Strat Range By Age.sql

As a long-time player of the card and dice replay game Strat-O-Matic Baseball, this is a query I wrote using
an example of the SQL keyword PIVOT to analyze player defensive range ratings by age.  Like in the above procedure,
I parameterized the Position variable so I only had to change it in one place when I wanted to evaluate a different
position.  This example uses data for catchers.

The query compiles range ratings from all eight possible positions in a batter's record via the UNION ALL keyword
then PIVOTS the results based on the age of the player that season.  The standard for age-based analysis is to use
the player's age as of July 1 of the season, roughly the midpoint of the season in Major League Baseball.

Results are in the accompanying Strat Range By Age - Catchers.csv file.
