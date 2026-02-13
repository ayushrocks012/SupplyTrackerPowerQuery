let
    // --- Dependencies ---
    Source = stg_MergedData,
    
    // Logic from CurrMonthADS.m
    CurrentMonth = Date.Month(DateTime.LocalNow()),
    CurrentYear = Date.Year(DateTime.LocalNow()),
    
    Filtered = Table.SelectRows(Source, each Date.Month([RowDate]) = CurrentMonth and Date.Year([RowDate]) = CurrentYear),
    
    // Original Logic: Group by ECC CODE, Site, and RowDate (day grain), then Sum [Data].
    Grouped = Table.Group(Filtered, {"ECC CODE", "Location/Plant/Site", "RowDate"}, {{"CurrMonthADS", each List.Sum([Data]), type nullable number}})
in
    Grouped
