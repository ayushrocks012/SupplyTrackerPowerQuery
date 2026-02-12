let
    // --- Dependencies ---
    Source = stg_MergedData,
    
    // Logic from CurrMonthADS.m
    CurrentMonth = Date.Month(DateTime.LocalNow()),
    CurrentYear = Date.Year(DateTime.LocalNow()),
    
    Filtered = Table.SelectRows(Source, each Date.Month([RowDate]) = CurrentMonth and Date.Year([RowDate]) = CurrentYear),
    
    Grouped = Table.Group(Filtered, {"ECC CODE", "Location/Plant/Site"}, {{"Sum", each List.Sum([Data]), type nullable number}, {"Count", each Table.RowCount(_), Int64.Type}}),
    
    ADS = Table.AddColumn(Grouped, "ADS", each [Sum] / [Count]),
    
    Final = Table.SelectColumns(ADS, {"ECC CODE", "Location/Plant/Site", "ADS"})
in
    Final
