let
    // === Parameters ===
    MonthsBack = -2,
    MonthsForward = 6,
    CurrentDate = Date.From(DateTime.LocalNow()),
    StartDate = Date.AddMonths(CurrentDate, MonthsBack),
    EndDate = Date.AddMonths(CurrentDate, MonthsForward),

    // === Load SharePoint Files (Direct Folder Access) ===
    Source = SharePoint.Contents("https://abbott.sharepoint.com/sites/GB-AN-HeadOffice", [ApiVersion = 15]),
    Folder = Source{[Name="Shared Documents"]}[Content],
    DemandFolder = Folder{[Name="General"]}[Content]{[Name="Demand"]}[Content]{[Name="Master Data Files"]}[Content]{[Name="Daily Tracker Files UK Departures PBI"]}[Content],

    FilteredFiles = Table.SelectRows(DemandFolder, each Text.StartsWith([Name], "UK Departures") and Text.EndsWith([Name], ".xlsx")),
    SortedFiles = Table.Sort(FilteredFiles, {{"Date modified", Order.Descending}}),
    LatestFile = SortedFiles{0}[Content],

    // === Load Excel Sheet ===
    ExcelData = Excel.Workbook(LatestFile, null, true),
    WarehouseSheet = Table.PromoteHeaders(Table.Skip(ExcelData{[Item="Warehouse",Kind="Sheet"]}[Data], 1), [PromoteAllScalars=true]),

    // === Clean & Transform ===
    CleanedData = Table.SelectRows(WarehouseSheet, each not List.IsEmpty(List.RemoveMatchingItems(Record.FieldValues(_), {"", null}))),
    ChangedTypes = Table.TransformColumnTypes(CleanedData,{
        {"ETD", type date}, {"DEPARTURE", Int64.Type}, {"Price", type number}, {"Units", type number}, {"Breda Tour", type text},
        {"Breda Status Date", type date}, {"EXP_DATE", type date}, {"MFG_DATE", type date}
    }),
    FilteredETD = Table.SelectRows(ChangedTypes, each [ETD] >= StartDate and [ETD] <= EndDate),

    // === Merge with A2B Summary ===
    BufferedA2B = Table.Buffer(#"A2B Summary"),
    MergedA2B = Table.NestedJoin(FilteredETD, {"Breda Tour", "DEPARTURE"}, #"A2B Summary", {"Breda Tour", "Departure"}, "A2B Summary", JoinKind.LeftOuter),
    ExpandedA2B = Table.ExpandTableColumn(MergedA2B, "A2B Summary", {"Collection Date", "Expected Delivery Date", "Breda Tour", "Departure", "Status", "Location", "Custom Cleared Status"}, {"A2B.Collection Date", "A2B.Expected Delivery Date", "A2B.Breda Tour", "A2B.Departure", "A2B.Status", "A2B.Location", "A2B.Custom Cleared Status"}),

    // === Add Columns ===
    AddedInboundWarehouse = Table.AddColumn(ExpandedA2B, "Inbound Warehouse", each "075-" & [TO]),
    AddedInboundStatus = Table.AddColumn(
    AddedInboundWarehouse,
    "Inbound Status",
    each
        let
            // Base inputs (convert to Date where possible)
            expectedDD = try Date.From([A2B.Expected Delivery Date]) otherwise null,
            etdDate    = try Date.From([ETD]) otherwise null,
            forwarder  = Text.Upper(Text.Trim(try Text.From([FORWARDER]) otherwise "")),

            // Effective delivery date:
            // If Expected Delivery Date is null and forwarder is NOUWENS, use ETD + 1
            deliveryDate =
                if expectedDD = null then
                    if forwarder = "NOUWENS" and etdDate <> null then
                        Date.AddDays(etdDate, 1)
                    else
                        null
                else
                    expectedDD,

            // Week difference from CurrentDate (assumes CurrentDate is already defined as a Date)
            weekDiff =
                if deliveryDate = null then
                    null
                else
                    (Date.Year(deliveryDate) - Date.Year(CurrentDate)) * 52
                    + (Date.WeekOfYear(deliveryDate) - Date.WeekOfYear(CurrentDate))
        in
            if deliveryDate = null then
                null
            else if weekDiff = -1 then
                "Inbound - Last Week"
            else if weekDiff = 0 then
                "Inbound - Current Week"
            else if weekDiff = 1 then
                "Inbound - Next Week"
            else if weekDiff > 1 then
                "Inbound - Newer than 2 Weeks"
            else
                "Inbound - Older than 2 Weeks"
),
    AddedGITValue = Table.AddColumn(AddedInboundStatus, "GIT Value (£)", each [Units]*[Price], type number),

    // === Merge SKU Bible ===
    BufferedSKU = Table.Buffer(SKUBIBLE),
    MergedSKU = Table.NestedJoin(AddedGITValue, {"1633 Item Code"}, BufferedSKU, {"SHORT 1633"}, "SKUBIBLE", JoinKind.LeftOuter),
    ExpandedSKU = Table.ExpandTableColumn(MergedSKU, "SKUBIBLE", {"ECC CODE"}, {"ECC CODE"}),

    // === Add Year & Month ===
    AddedYearMonth = Table.AddColumn(ExpandedSKU, "Year (Current)", each Date.Year([ETD])),
    AddedMonth = Table.AddColumn(AddedYearMonth, "Month (Current)", each Text.PadStart(Text.From(Date.Month([ETD])), 2, "0") & " - " & Text.Start(Date.MonthName([ETD]), 3)),

    // === Sort ===
    SortedRows = Table.Sort(AddedMonth, {{"DEPARTURE", Order.Descending}})
in
    SortedRows
