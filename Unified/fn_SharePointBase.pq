// fn_SharePointBase — Single entry point for all SharePoint navigation.
// All staging, dimension, and fact queries should reference this instead of
// calling SharePoint.Contents independently. Reduces REST API round-trips
// from 17 to 1 site crawl + lazy folder evaluation.
let
    Source = SharePoint.Contents(
        "https://abbott.sharepoint.com/sites/GB-AN-HeadOffice", 
        [ApiVersion = 15]
    ),
    SharedDocs = Source{[Name="Shared Documents"]}[Content],
    General = SharedDocs{[Name="General"]}[Content],
    Demand = General{[Name="Demand"]}[Content],
    MasterDataFiles = Demand{[Name="Master Data Files"]}[Content]
in
    [
        Demand = Demand,
        MasterDataFiles = MasterDataFiles,
        DailyTracker = MasterDataFiles{[Name="Daily Tracker Files"]}[Content],
        Wholesaler = MasterDataFiles{[Name="Daily Tracker Files - Wholesaler"]}[Content],
        UKDepartures = MasterDataFiles{[Name="Daily Tracker Files UK Departures PBI"]}[Content],
        MasterData = MasterDataFiles{[Name="Daily Tracker - Master Data"]}[Content],
        ArrivalSchedule = MasterDataFiles{[Name="Daily Tracker - Master Arrival Schedule"]}[Content],
        DMFNew = MasterDataFiles{[Name="DMF New"]}[Content]
    ]
