Problem

Vayu Air’s analysts query the live booking database directly. Reports are slow, the joins are complicated, and each team gets different numbers for the same question (revenue by route, month or frequent-flyer tier). Historical reports also change when a passenger’s tier changes.

Process (what you built)

Grain: one row per ticket sold. Columns were split into dimension keys and additive measures (fare, tax, miles).
Star schema: FactTicketSales in the centre, with DimPassenger, DimFlight, DimAirport (origin and destination), DimAircraft and DimDate (booking and travel). Each dimension has a surrogate key and keeps its business key.
Load: dimensions first, then the fact, joined on business keys. Row counts were checked against bronze.
Snowflake: airport → city → country, which trades extra joins for less repeated data.
SCD Type 2: DimPassenger keeps a new row each time tier or home airport changes (is_current, effective_from, effective_to), using expire-then-insert.
Partitioning: the fact was partitioned by date. The execution plan shows partition elimination when you filter on the date key, and a full scan when you filter on another column.
Medallion and contract: tables were mapped to bronze/silver/gold, and bronze_bookings got a data contract (schema, allowed values, SLA, owner, change rules).

End result

Faster queries: the fact joins to small dimensions by integer keys, and date filters read only the partitions they need.
One set of numbers: every team uses the same fact and dimensions, so “revenue by route, month or tier” gives one answer.
Honest history: each booking stays linked to the passenger version that was current at that time, so tier-based revenue doesn’t change retroactively.
Easier reports: simple fact-to-dimension joins replace the tangled joins on the live system.
Clear layers and rules: raw data stays in bronze, the reporting model sits in gold, and the data contract defines what the source feed must deliver.
