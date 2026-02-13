// base_LX02_Raw — Shared buffered staging for the LX02 Excel file.
// Both stg_Inv_AUK and stg_Inv_AUK_Batch consume this instead of
// independently downloading the same file from SharePoint.
let
    DemandPath = fn_SharePointBase[DailyTracker],
    FileContent = fn_GetLatestFile(DemandPath, "LX02", ".xlsx"),
    Excel = Excel.Workbook(FileContent, null, true),
    Sheet = try Excel{[Item="Sheet1"]} otherwise Excel{[Name="Sheet1"]},
    Data = Sheet[Data],
    Promoted = Table.PromoteHeaders(Data, [PromoteAllScalars=true])
in
    Promoted
