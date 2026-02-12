let
    // Connect to SharePoint root
    Source = SharePoint.Contents("https://abbott.sharepoint.com/sites/GB-AN-HeadOffice", [ApiVersion = 15]),

    // Navigate to folder where MasterMassiveNew.xlsb resides
    SharedDocs = Source{[Name="Shared Documents"]}[Content],
    GeneralFolder = SharedDocs{[Name="General"]}[Content],
    DemandFolder = GeneralFolder{[Name="Demand"]}[Content],
    MasterDataFolder = DemandFolder{[Name="Master Data Files"]}[Content],
    DMFNewFolder = MasterDataFolder{[Name="DMF New"]}[Content],

    // Get the file
    MasterFile = DMFNewFolder{[Name="MasterMassiveNew.xlsb"]}[Content],

    // Load Excel workbook and select MergedData sheet
    ExcelData = Excel.Workbook(MasterFile, null, true),
    MergedData1 = ExcelData{[Name="MergedData"]}[Data],
    // Promote headers
    PromotedHeaders = Table.PromoteHeaders(MergedData1, [PromoteAllScalars=true]),
    // Filter rows
    FilteredRows = Table.SelectRows(
        PromotedHeaders,
        each ([Key Figures] <> "Baselined History") and ([Country] = "075") and ([APO Customer] <> "NORTHERN IRELAND")
    ),

    // Merge with SKUBIBLE (assuming SKUBIBLE also uses SharePoint.Contents)
    MergedQueries = Table.NestedJoin(
        FilteredRows,
        {"Local Item number"},
        SKUBIBLE,
        {"LOCAL ITEM NBR"},
        "SKUBIBLE",
        JoinKind.LeftOuter
    ),
    ExpandedSKUBIBLE = Table.ExpandTableColumn(
        MergedQueries,
        "SKUBIBLE",
        {"DESC", "1-6-3-3", "SHORT 1633", "ECC CODE", "ADULT/PAED", "REIMBURSED/OOP", "FORECAST TIER", "FORECAST MID-TIER", "FORECAST SUB-TIER", "GROWTH DRIVER", "GROWTH SUB-DRIVER", "PRODUCT STATUS"},
        {"DESC", "1-6-3-3", "SHORT 1633", "ECC CODE", "ADULT/PAED", "REIMBURSED/OOP", "FORECAST TIER", "FORECAST MID-TIER", "FORECAST SUB-TIER", "GROWTH DRIVER", "GROWTH SUB-DRIVER", "PRODUCT STATUS"}
    ),

    // Change types
    ChangedType = Table.TransformColumnTypes(ExpandedSKUBIBLE, {{"Data", type number}, {"RowDate", type date}})
in
    ChangedType
