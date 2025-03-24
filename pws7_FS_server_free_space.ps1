<#
.SYNOPSIS
    [pws7_FS_server_free_space.ps1] - See for computers for 20% space disk
 
.DESCRIPTION
    This file needs powershell 7, Get a list of all computers from Active Directory and check for space disk issues. Usually less than 20% disk
 
.AUTHOR
    [Chejov Suzdal] - [agr.suzdal@gmail.com]
 

.LICENSE
MIT License (https://opensource.org/licenses/MIT)
 
Copyright (c) 2020 ChejovSuzdal(Acracio Guerrero)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

 
.NOTES
    [Cualquier nota adicional, requisitos, dependencias, etc.]
 
.VERSION
    1.0
#>

Import-Module ActiveDirectory

$FileTimeSuffix = ((Get-Date -Format dMMMyy).ToString()) + "-" + ((get-date -Format hhmmsstt).ToString())
$PrefixFile = ""<----- YOUR Path to reports goes here  ---->""
$ResultFile = $PrefixFile + "FS-" + $FileTimeSuffix + ".csv"

$base = "SERVERname;DRIVEletter;DRIVEname;DRIVEfs;Size;DRIVEfreespace;DRIVEpercent" 
Add-Content $ResultFile  $base

Write-host "1- Getting list from AD"
$servers = Get-ADComputer -Filter 'operatingsystem -like "*server*" -and enabled -eq "true"' | sort name


$mycount = [System.Math]::Round(($servers.count/4),0)


$tw = [System.IO.TextWriter]::Synchronized([System.IO.File]::AppendText("$ResultFile"))

Write-host "2- Getting list from AD::" + $servers.count + " vs " $mycount

$servers | Foreach-object -throttlelimit $mycount -Parallel {

	$writer = $($Using:tw)
	$myserver = $_.name
	#Write-host ":: PING ::" + $myserver
	if (Test-Connection -ComputerName $myserver -count 1 -ErrorAction SilentlyContinue) {
		try {
			#$res1 = $( Get-Ciminstance -Class Win32_LogicalDisk -ComputerName $myserver -Filter "DriveType=3" -ErrorAction SilentlyContinue )
			#$res2 = $( $res1 | select SystemName,VolumeName,DeviceID, FileSystem, FreeSpace,Size )
			
			$res1 = $( Get-Ciminstance -ComputerName $myserver -query "select * from win32_volume" -ErrorAction SilentlyContinue )
			$res2 = $( $res1 | select SystemName,Name,DeviceID, FileSystem, FreeSpace,Capacity )
			
			#$res3 = $( $res2 | % {$_.FreeSpace=($_.FreeSpace/1GB);$_.Size=($_.Size/1GB);$_} )
			#$res4 = $( $res3 | Format-Table SystemName,VolumeName,DeviceID, FileSystem, @{n='FreeGB';e={'{0:N2}'-f $_.FreeSpace}}, @{n='CapacityGb';e={'{0:N3}' -f $_.Size}} )
			#Write-host ":: DONE CIM ::" + $myserver
			#Write-host "-1-" $res1
			#Write-host "-2-" $res2
			#Write-host "-3-" $res3
			#Write-host "-4-" $res4
			
			foreach ($server in $res2) {
				
				$name = ""
				$DRIVEname = ""
				$DRIVEletter = ""
				$DRIVEfs = ""
				[int64] $Size = ""
				[int64] $DRIVEfreespace = ""
				$DRIVEpercent = ""
				$DRIVE20 = ""

				
				$name = $server.SystemName
				$DRIVEname = $server.Name
				$DRIVEletter = $server.DeviceID
				$DRIVEfs = $server.FileSystem

				[int64] $Size = [System.Math]::Round(($server.Capacity),2)
				[int64] $DRIVEfreespace = [System.Math]::Round(($server.FreeSpace),2)
				$DRIVEpercent = [System.Math]::Round( (($DRIVEfreespace * 100)/$Size),2)
				
				if ( $DRIVEpercent -le 20 ) {
					$DRIVE20 = "NO OK"
					#Excepciones
					switch ($name) {
						"serverTOignore1" {
							if ( $DRIVEname -like "*driveNAME*" ) { $DRIVE20 = "OK" }
							continue
						}
						"serverTOignore2" {
							if ( $DRIVEname -like "*driveNAME*" ) { $DRIVE20 = "OK" }
							continue
						}
					}
					#if ($DRIVEfreespace -ge 42949672960 ) {
					#	$DRIVE20 = "OK"
					#}
				} else { 
				$DRIVE20 = "OK"
				}
			

				if ( $DRIVE20 -eq "NO OK" ) {
					$objCOMPLIANT_b = $name + ";" + $DRIVEletter + ";" + $DRIVEname + ";" + $DRIVEfs + ";" + $Size + ";" + $DRIVEfreespace + ";" + $DRIVEpercent + ";" + $DRIVE20		
					$writer.WriteLine($objCOMPLIANT_b.toString() )
				
				} else { 
					#NOTHING
				}

			}
		}
		catch
		{
			Write-host ":: CATCH CIM ::" + $myserver
		}
	}
	else
	{
		Write-host ":: NO PING ::" + $myserver
	}

}
$tw.Close()



					# Send mail notification with report
					$From = "youmailhere@domain.com"
					$To = "anothermail@domain.com"
					$cc = "other@domain.com"
					$Subject = "SRV - Review free space in server"
					
						$body = "Please review report `n `n"
						
						$body = $body + "Review attached report with 20% less server disk space. `n" 
						$body = $body + "Please mind: `n `n"
						
						$body = $body + "1. Review the attached list of servers with less than 20% free space (DRIVEpercent column). The goal is to leave it above this value. 'n"
						$body = $body + "2. If you are unable to free up disk space, ask for your IT SYSAdmin. 'n 'n"

						$body = $body + "Indicate the routes where space has been freed up and the actions taken. 'n"
						$body = $body + "If the space is less than 5% give it priority. 'n 'n"

						$body = $body + "tnxs `n `n"

					$SmtpServer = "YOUR_smtp_server_here.fqdn"
					Send-MailMessage -From $From -To $To -Cc $cc -Subject $Subject -Body $Body -SmtpServer $SmtpServer -Port 25 -Attachments $ResultFile
