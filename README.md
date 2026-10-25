# Tablo-Video-Scripts
Scripts to import and convert Tablo Videos into mp4 files

This is a collection of scripts organized within a winform Menu structure, that will assist in retrieving and encoding Tablo videos.  

Prerequisites:
    Using an external usb drive on Tablo to capture recordings, connect to pc and copy the following
    to a folder within the windows pc.
      Tablo.db - SQL database containing the names and id's of recorded videos.
      REC -  directory containing the recorded videos. It has a list of folders, each containing a SEGS 
      directory containing the .ts files.  The directory names are the indexes contained within the 
      Tablo.db.
    DB Browser (SQLite) needs to be installed.
      SQLite3 ODBC Driver
        Download from the developer's website:
        https://www.ch-werner.de/sqliteodbc/
        This driver lets PowerShell connect to a SQLite database through Windows ODBC.
        Make sure you install the driver version that matches the bitness of the PowerShell process running your script (32-bit           or 64-bit). Since you use PowerShell 7 (pwsh) as well as Windows PowerShell 5.1, check which one launches your script and         whether it is 64-bit.

    Create Tablo directory.  Copy the Xmenu directory and all files. Run menu.bat.
    
Note:  Use an external usb drive on the Tablo to capture video so that it can be connected to computer.  Tablo uses a Linux file system so in Windows computer use apps such as "DiskiInternals Linux Reader" to retrieve the necessary files.  

Within the utilities menu there is a menu option for setting locations for various items that may be needed by
the system.

The menus within the xmenu system can be administered using the menu maintenance opiton with the utilities menu.
Within the data directory is a data file, buttons.txt where the administered data is stored.  The following
is the contents of buttons.txt located in the default system.  This shows the menu option along with the
script that is being executed.

  Rename Tablo Video Directories|60cf5438-afe9-4261-8ded-16968110c45c|{DRIVE}\Xmenu\etc\rename.ps1
  MCEBuddy ts > mp4|caee909b-6b0a-449c-8baa-26c3bfa3b4ac|{DRIVE}\Xmenu\etc\convert-mcebuddy.ps1
  FFmpeg  ts > mp4|de2fcee6-6a69-43e4-b4ce-4bdea3885da1|{DRIVE}\Xmenu\etc\VideoJoin.ps1
  FFmpeg/Handbrake Re-encode mp4 > mp4|9a48567b-fcf4-4d22-be9f-176e309a17fc|{DRIVE}\Xmenu\etc\videoEncode.ps1
  FFmpeg Remux  mkv > mp4|54e44dac-c6f9-48b1-8cdd-e27964c856fa|{DRIVE}\Xmenu\etc\ffmpegCopy.ps1|

The Rename Tablo Video Directories option will setup the rename the folders within the REC folder to 
a format that can be used by PLEX.  It takes the index found in tablo.db, searches the folder names for
a match, then renames the folder with the data associated with index in tablo.db.  

The remaining menu options are then used to convert the files, these can be chosen depending on
if using MCEbuddy, FFmpeg or Handbrake. 



 



of both Tablo.db database and Tablo Video folder.  


