let
    // Helper: Get Latest File from Folder
    fn_GetLatestFile = (SourceFolder as table, FileStartWith as text, FileEndWith as text) as binary =>
        let
            Filtered = Table.SelectRows(SourceFolder, each Text.StartsWith([Name], FileStartWith) and Text.EndsWith([Name], FileEndWith)),
            Sorted = Table.Sort(Filtered, {{"Date modified", Order.Descending}}),
            Latest = Table.First(Sorted)[Content]
        in
            Latest,

    // Helper: Clean Column Headers
    fn_CleanHeaders = (SourceTable as table) as table =>
        let
            Promoted = Table.PromoteHeaders(SourceTable, [PromoteAllScalars=true])
        in
            Promoted
in
    [
        fn_GetLatestFile = fn_GetLatestFile,
        fn_CleanHeaders = fn_CleanHeaders
    ]
