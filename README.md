# Tablo-Video-Scripts
Scripts to import and convert Tablo Videos into mp4 files

This is a collection of scripts organized within a winform Menu structure, that will assist in retrieving and encoding Tablo videos.  

Prerequisites:
  The following items copied from the Tablo storage disk
    Tablo.db - SQL database containing the names and id's of recorded videos.
    REC -  directory containing the recorded videos 
    DB Browser (SQLite) needs to be installed.
      SQLite3 ODBC Driver
        Download from the developer's website:
        https://www.ch-werner.de/sqliteodbc/
        This driver lets PowerShell connect to a SQLite database through Windows ODBC.
        Make sure you install the driver version that matches the bitness of the PowerShell process running your script (32-bit           or 64-bit). Since you use PowerShell 7 (pwsh) as well as Windows PowerShell 5.1, check which one launches your script and         whether it is 64-bit.

    
    
Note:  Use an external usb drive on the Tablo to capture video so that it can be connected to computer.  Tablo uses a Linux file system so in Windows computer use apps such as "DiskiInternals Linux Reader" to retrieve the necessary files.  

Within the Xmenu menu system there is a utility menu with a settings option that allows administering the location of both Tablo.db database and Tablo Video folder.  


