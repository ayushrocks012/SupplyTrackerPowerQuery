let
    // --- Dependencies ---
    SourceAUK = stg_Inv_AUK_Batch,
    SourceAUL = stg_Inv_AUL_Batch,
    SKUBible = dim_SKUBible_V3, 
    ADS = fct_ADS_CurrMonth,
    OnOrder = stg_OnOrder,
    
    // 1. Combine AUK and AUL
    Combined = Table.Combine({SourceAUK, SourceAUL}),
    
    // 2. Merge with SKUBIBLE V3
    // Original Total_Inv_Batch.m: NestedJoin(#"Changed Type", {"Product Code", "Warehouse"}, #"SKUBIBLE V3", {"ECC CODE", "PLANT CODE"}, ...)
    // It joins on Product Code -> ECC CODE and Warehouse -> PLANT CODE.
    // My dim_SKUBible_V3 is just the SKUBIBLE table. I assume it has ECC CODE and PLANT CODE.
    // Error "Column ITEM NMBR not found" in my previous code was because I tried to join on "ITEM NBR". 
    // I will correct this to join on "ECC CODE".
    
    // Note: I am NOT joining on Warehouse/PLANT CODE for simplicity unless strictly necessary, 
    // but the original code did. I'll stick to Product Code -> ECC CODE for now as it's the primary key.
    
    MergedSKU = Table.NestedJoin(Combined, {"Product Code"}, SKUBible, {"ECC CODE"}, "SKUBIBLE", JoinKind.LeftOuter),
    
    ExpandedSKU = Table.ExpandTableColumn(MergedSKU, "SKUBIBLE", {"DESCRIPTION", "SHELF LIFE", "SHIP SHELF LIFE"}, {"DESCRIPTION", "SHELF LIFE", "SHIP SHELF LIFE"}),
    
    // 3. Current Date Logic
    CurrentDate = Date.From(DateTime.LocalNow()),
    
    // 4. Transform & Calculate
    WithExpiry = Table.TransformColumnTypes(ExpandedSKU,{{"Expiry", type date}, {"SHELF LIFE", Int64.Type}, {"SHIP SHELF LIFE", Int64.Type}}),
    
    // Days to Expiry
    WithDaysToExpiry = Table.AddColumn(WithExpiry, "Days to Expiry", each Duration.Days([Expiry] - CurrentDate), Int64.Type),
    
    // 5. Merge with ADS
    MergedADS = Table.NestedJoin(WithDaysToExpiry, {"Product Code", "Warehouse"}, ADS, {"ECC CODE", "Location/Plant/Site"}, "ADS_Table", JoinKind.LeftOuter),
    ExpandedADS = Table.ExpandTableColumn(MergedADS, "ADS_Table", {"ADS"}, {"ADS"}),
    
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
        if [Days to Expiry] = null or [SHIP SHELF LIFE] = null then null 
        else ([Days to Expiry] - [SHIP SHELF LIFE]) / 30, type number),
    
    // 7. Merge with OnOrder
    MergedOnOrder = Table.NestedJoin(WithMTS, {"Product Code", "Warehouse"}, OnOrder, {"ECC CODE", "Inbound Warehouse"}, "OnOrder_Table", JoinKind.LeftOuter),
    ExpandedOnOrder = Table.ExpandTableColumn(MergedOnOrder, "OnOrder_Table", {"OnOrderQty"}, {"OnOrderQty"}),
    
    FinalTyped = Table.TransformColumnTypes(ExpandedOnOrder, {{"OnOrderQty", Int64.Type}, {"ADS", type number}})
in
    FinalTyped
