let
    // --- Dependencies (Shared Base) ---
    DemandPath = fn_SharePointBase[DMFNew],

    FileContent = fn_GetLatestFile(DemandPath, "MasterMassiveNew", ".xlsb"),
    Excel = Excel.Workbook(FileContent, null, true),
    
    // Attempt to get Table or Sheet
    TableData = try Excel{[Item="MergedData", Kind="Table"]}[Data] 
                otherwise Excel{[Name="MergedData"]}[Data],
    
    // FIX: Promote Headers
    Promoted = Table.PromoteHeaders(TableData, [PromoteAllScalars=true]),
    
    // Logic from MergedData.m — restore legacy predicates
    FilteredKF = Table.SelectRows(Promoted, each [Key Figures] <> "Baselined History"),
    FilteredCountry = Table.SelectRows(FilteredKF, each [Country] = "075"),
    FilteredAPO = Table.SelectRows(FilteredCountry, each [APO Customer] <> "NORTHERN IRELAND"),
    // Keep location filter as additional guard
    FilteredRows = Table.SelectRows(FilteredAPO, each ([#"Location/Plant/Site"] = "075-UK" or [#"Location/Plant/Site"] = "075-UL")),
    CleanedDate = Table.TransformColumns(FilteredRows,{{"RowDate", each Date.From(_), type date}}),
    
    // Merging with SKUBIBLE V2
    // FIX: Join on "Local Item number" -> "LOCAL ITEM NBR"
    SKUBible = dim_SKUBible_V2, 
    Merged = Table.NestedJoin(CleanedDate, {"Local Item number"}, SKUBible, {"LOCAL ITEM NBR"}, "SKUBIBLE", JoinKind.LeftOuter),
    
    // FIX: Expand correct columns
    Expanded = Table.ExpandTableColumn(
        Merged, 
        "SKUBIBLE", 
        {"DESC", "1-6-3-3", "SHORT 1633", "ECC CODE", "ADULT/PAED", "REIMBURSED/OOP", "FORECAST TIER", "FORECAST MID-TIER", "FORECAST SUB-TIER", "GROWTH DRIVER", "GROWTH SUB-DRIVER", "PRODUCT STATUS"}, 
        {"DESC", "1-6-3-3", "SHORT 1633", "ECC CODE", "ADULT/PAED", "REIMBURSED/OOP", "FORECAST TIER", "FORECAST MID-TIER", "FORECAST SUB-TIER", "GROWTH DRIVER", "GROWTH SUB-DRIVER", "PRODUCT STATUS"}
    ),
    
    Typed = Table.TransformColumnTypes(Expanded,{{"Data", Int64.Type}, {"RowDate", type date}})
in
    Typed
