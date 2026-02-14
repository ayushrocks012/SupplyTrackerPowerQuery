let
    // --- Dependencies ---
    SourceAUK = stg_Inv_AUK_Batch,
    SourceAUL = stg_Inv_AUL_Batch,
    SKUBible = dim_SKUBible_V3, 
    ADS = fct_ADS_CurrMonth,
    OnOrder = stg_OnOrder,
    
    // 1. Combine AUK and AUL
    Combined = Table.Combine({SourceAUK, SourceAUL}),
    
    // 2. Merge with SKUBIBLE V3 — composite key {Product Code, Warehouse} → {ECC CODE, PLANT CODE}
    MergedSKU = Table.NestedJoin(Combined, {"Product Code", "Warehouse"}, SKUBible, {"ECC CODE", "PLANT CODE"}, "SKUBIBLE", JoinKind.LeftOuter),
    
    // Expand all 11 legacy columns from SKUBIBLE V3
    ExpandedSKU = Table.ExpandTableColumn(MergedSKU, "SKUBIBLE", {"DESC", "D56 ITEM NMBR", "1-6-3-3", "SHORT 1633", "SHIP SHELF LIFE", "FORM DESCRIPTION", "PACK TYPE REPORTING", "ADULT/PAED", "REIMBURSED/OOP", "FORECAST SUB-TIER", "GROWTH DRIVER"}, {"DESC", "D56 ITEM NMBR", "1-6-3-3", "SHORT 1633", "SHIP SHELF LIFE", "FORM DESCRIPTION", "PACK TYPE REPORTING", "ADULT/PAED", "REIMBURSED/OOP", "FORECAST SUB-TIER", "GROWTH DRIVER"}),
    
    // 3. Filter to AVAILABLE only (legacy Total_Inv_Batch.m line 6)
    FilteredAvailable = Table.SelectRows(ExpandedSKU, each [Combined Storage Type] = "AVAILABLE"),
    
    // 4. Current Date Logic
    CurrentDate = Date.From(DateTime.LocalNow()),
    
    // 5. Type transforms deferred to end (single pass)
    // Note: Expiry/SHIP SHELF LIFE types needed for calculations below
    
    // Days to Expiry
    WithDaysToExpiry = Table.AddColumn(FilteredAvailable, "Days to Expiry", each try Duration.Days(Date.From([Expiry]) - CurrentDate) otherwise null, Int64.Type),
    
    // 6. Merge with ADS
    MergedADS = Table.NestedJoin(WithDaysToExpiry, {"Product Code", "Warehouse"}, ADS, {"ECC CODE", "Location/Plant/Site"}, "ADS_Table", JoinKind.LeftOuter),
    ExpandedADS = Table.ExpandTableColumn(MergedADS, "ADS_Table", {"CurrMonthADS"}, {"CurrMonthADS"}),
    
    // 6. Calculate Months to Sell
    // Logic: ([Days to Expiry] - [SHIP SHELF LIFE]) / 30 / [ADS] ??
    // Original: ([Days to Expiry]-[SHIP SHELF LIFE])/30  <-- This seems to be "Months of Shelf Life Remaining" not "Months to Sell stock".
    // Wait, original: "Months to Sell" = ([Days to Expiry]-[SHIP SHELF LIFE])/30. 
    // This is weird naming. Usually "Months of Stock" = Inv / ADS.
    // But I will FOLLOW ORIGINAL LOGIC exactly.
    
    // Correction: The user might want "Months of Coverage" vs "Shelf Life Remaining".
    // Original Code: #"Added Custom" = Table.AddColumn(..., "Months to Sell", each ([Days to Expiry]-[SHIP SHELF LIFE])/30)
    // This calculates how many months of sellable life are left.
    
    WithMTS = Table.AddColumn(ExpandedADS, "Months to Sell", each 
        let 
            dte = try [Days to Expiry] otherwise null,
            ssl = try Number.From([SHIP SHELF LIFE]) otherwise null
        in 
            if dte = null or ssl = null then null 
            else (dte - ssl) / 30, type number),
    
    // Last Ship Date (legacy Total_Inv_Batch.m line 16)
    WithLastShipDate = Table.AddColumn(WithMTS, "Last Ship Date", each 
        let 
            exp = try Date.From([Expiry]) otherwise null,
            ssl = try Number.From([SHIP SHELF LIFE]) otherwise null
        in 
            if exp = null or ssl = null then null 
            else Date.AddDays(exp, -ssl), type date),
    
    // 8. Merge with OnOrder
    MergedOnOrder = Table.NestedJoin(WithLastShipDate, {"Product Code", "Warehouse"}, OnOrder, {"ECC CODE", "Inbound Warehouse"}, "OnOrder_Table", JoinKind.LeftOuter),
    ExpandedOnOrder = Table.ExpandTableColumn(MergedOnOrder, "OnOrder_Table", {"OnOrderQty"}, {"OnOrderQty"}),
    
    FinalTyped = Table.TransformColumnTypes(ExpandedOnOrder, {{"Expiry", type date}, {"SHIP SHELF LIFE", Int64.Type}, {"OnOrderQty", Int64.Type}, {"CurrMonthADS", type number}}),
    
    // C-02 FIX: Match legacy Total_Inv_Batch.m Sort → Index → RemoveColumns
    Sorted = Table.Sort(FinalTyped, {{"Expiry", Order.Ascending}, {"FORECAST SUB-TIER", Order.Ascending}}),
    Indexed = Table.AddIndexColumn(Sorted, "Index", 1, 1, Int64.Type),
    
    // Remove columns that legacy explicitly dropped
    Cleaned = Table.RemoveColumns(Indexed, {"Combined Storage Type", "Combined Storage Bin", "D56 ITEM NMBR", "1-6-3-3", "SHORT 1633", "SHIP SHELF LIFE", "Days to Expiry"}, MissingField.Ignore)
in
    Cleaned
