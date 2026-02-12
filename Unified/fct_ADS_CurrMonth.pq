let
    // --- Dependencies ---
    Source = stg_MergedData,
    
    // Logic from CurrMonthADS.m
    CurrentMonth = Date.Month(DateTime.LocalNow()),
    CurrentYear = Date.Year(DateTime.LocalNow()),
    
    Filtered = Table.SelectRows(Source, each Date.Month([RowDate]) = CurrentMonth and Date.Year([RowDate]) = CurrentYear),
    
    // Original Logic: Group by ECC CODE and Site, then Sum [Data].
    // No count or division. "Data" column likely already represents ADS or Daily Sales for that row.
    Grouped = Table.Group(Filtered, {"ECC CODE", "Location/Plant/Site"}, {{"Data", each List.Sum([Data]), type nullable number}}),
    
    // Rename "Data" to "CurrMonthADS" or just keep it and rename in final selection?
    // Original CurrMonthADS.m just output the grouped table.
    // But fct_Inventory_Batch expects a column "CurrMonthADS" (or "ADS"?).
    // Let's check fct_Inventory_Batch:
    // MergedADS = Table.NestedJoin(..., ADS, ...)
    // ExpandedADS = Table.ExpandTableColumn(..., {"ADS"}, {"ADS"})
    // So fct_Inventory_Batch expects a column named "ADS".
    
    Renamed = Table.RenameColumns(Grouped, {{"Data", "ADS"}})
in
    Renamed
