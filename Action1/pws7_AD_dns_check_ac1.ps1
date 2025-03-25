<#
.SYNOPSIS
    [pws7_AD_dns_check.ps1] - See for computers with no dns or ptr.
 
.DESCRIPTION
    This file needs powershell 7, Get a list of all computers from Active Directory and check for DNS status, if host A or ptr need to be created and send report to e-mail.
 
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
    1.0 main
	1.1 Adapatation for datasource in Action1 challenge 2025
#>

Import-Module DnsServer 
Import-Module ActiveDirectory

# will asumme AD controleer is dns too
$dnsserver = (Get-ADDomainController).name
$HostDomainName = (Get-WmiObject win32_computersystem -ComputerName $dnsserver ).domain



$FileTimeSuffix = Get-date -UFormat "%Y-%m-%d-%H_%M"

# variable set for parallel
$tw=""
$twREF= [ref]$tw

#will get a lsit of computers from AD for check dns health
Write-host "1- Getting list from AD"

$servers = Get-ADComputer -Filter 'operatingsystem -like "*server*" -and enabled -eq "true"' -server $dnsserver | Sort-Object name

Write-host "1- Getting zones from DNS"

$reverseZones = (Get-DnsServerZone -ComputerName $dnsserver | Where-Object {$_.IsReverseLookupZone -match "True" -and $_.IsDsIntegrated -match "True"} | Select-Object ZoneName).ZoneName

$ExistingPtr_main = $reverseZones | ForEach-Object {Get-DnsServerResourceRecord -ZoneName $_ -ComputerName $dnsserver -RRType PTR}

$mycomputerlist = (Get-DnsServerResourceRecord -Cimsession $dnsserver -zonename $HostDomainName -RRType "A" )

Write-host "Servers in AD ::" + $servers.count
Write-host "Zones in DNS ::" + $reverseZones.count
Write-host "Records PTR in DNS ::" + $ExistingPtr_main.count
Write-host "Records A in DNS ::" + $mycomputerlist.count

$mycount = [System.Math]::Round(($servers.count/4),0)

### uncomment for debug

$servers | Foreach-object -throttlelimit $mycount -Parallel {

	$writer = $Using:twREF
	$in_dnsserver = $Using:dnsserver
	$in_HostDomainName = $Using:HostDomainName
		
	$reverseZones_PR = $($Using:reverseZones)
	$ExistingPtr_main_PR = $($Using:ExistingPtr_main)
	$mycomputerlist_PR = $($Using:mycomputerlist)
	
	$server = $($_.name.Split(" ")[0])
	#Write-host " "

	if (Test-Connection -ComputerName $server -count 1 -ErrorAction SilentlyContinue)
	{
		#Write-Host "Check for existing DNS record(s) ::"$server
		$NodeARecord = Get-DnsServerResourceRecord -ZoneName $in_HostDomainName -ComputerName $in_dnsserver -Node $server -RRType A -ErrorAction SilentlyContinue
		if($NodeARecord -eq $null){
			$FQDN_A = $server + '.' + $in_HostDomainName
			$myip = (Test-NetConnection $server).RemoteAddress.IPAddressToString
			
			$IPAddressAsArray = $myip.Split('.') # Convert IP address to array using the dot as delimiter 
			[array]::Reverse($IPAddressAsArray) 
			$reversedIP = $IPAddressAsArray -join '.' # The name of the PTR record will be got from reversed IP stored in the variable 
			$PtrDomainName = $FQDN_A + '.' # for PTR records the dot is added to the domain name
			[string]$theReverseZone = $reverseZones_PR -match "^($($myip.Split('.')[2]))?\.?($($myip.Split('.')[1]))?\.?($($myip.Split('.')[0]))\.in-addr\.arpa" | Sort-Object Length -Descending | Select-Object -First 1 
			$ptrRRName = $reversedIP -replace "(.*)$('\.' + $($theReverseZone -replace '\.in-addr\.arpa'))(.*)", '$1$2'  # The resource record name 
			
			###Write-Host "-- No A record found ::"$FQDN_A "::" $myip
			$objCOMPLIANT_a = "$FQDN_A;ADD A + PTR;$myip;$in_HostDomainName;$ptrRRName;$PtrDomainName;$theReverseZone"
			###write-host "$FQDN_A;ADD A + PTR;$myip;$in_HostDomainName;$ptrRRName;$PtrDomainName;$theReverseZone"

			#Add-DnsServerResourceRecord -CimSession $in_dnsserver -ZoneName $in_HostDomainName -A -Name $server.ToUpper() -IPv4Address $myip -createPTR -ErrorAction SilentlyContinue
			$NodeARecord = Get-DnsServerResourceRecord -ZoneName $in_HostDomainName -ComputerName $in_dnsserver -Node $server -RRType A -ErrorAction SilentlyContinue
			###Write-Host "++ No A record found ::"$NodeARecord.hostname "::" $NodeARecord.RecordData.IPv4Address.IPAddressToString
			$writer.value += $objCOMPLIANT_a.toString()
		} else {

			$hostName = $server.split(".")[0].ToUpper()
			#$FQDN = $hostName + '.' + $in_HostDomainName
			#$hostIP1 = $($server | Where-Object {$_.hostname -eq $server.hostname}).RecordData.IPv4Address.IPAddressToString
			#region PTR 
			
			$WMMnode = $($mycomputerlist_PR | Where-Object {
				$_.hostname.ToUpper() -eq $server.ToUpper()}
			)
			
			$hostNameIP = $WMMnode.hostname.split(".")[0].ToUpper() 
			$FQDN = $hostNameIP.ToUpper() + '.' + $in_HostDomainName
			$myhostIP = ($WMMnode).RecordData.IPv4Address.IPAddressToString.Split(' ')
			
			
			#$hostName = $machine.hostname.split(".")[0] 
			#$FQDN = $hostName + '.' + $in_HostDomainName
			#$hostIP = $($machine | Where-Object {$_.hostname -eq $machine.hostname}).RecordData.IPv4Address.IPAddressToString
			
			foreach ( $hostIP in $myhostIP )
			{
			
				# Get Reverse Zones, except "fakes" (0.in-addr.arpa, 127.in-addr.arpa, 255.in-addr.arpa)
				$ExistingPtr = $ExistingPtr_main_PR | Where-Object{$_.RecordData.PtrDomainName -match $hostNameIP}
				
				#reverse IP Address 
				$IPAddressAsArray = $hostIP.Split('.') # Convert IP address to array using the dot as delimiter
				[array]::Reverse($IPAddressAsArray) 
				$reversedIP = $IPAddressAsArray -join '.' # The name of the PTR record will be got from reversed IP stored in the variable 
				
				#Get list of reverse lookup zones overlap, the IP may correspond to more than one zone.
				#get first zone with less class lengt
				[string]$theReverseZone = $reverseZones_PR -match "^($($hostIP.Split('.')[2]))?\.?($($hostIP.Split('.')[1]))?\.?($($hostIP.Split('.')[0]))\.in-addr\.arpa" | Sort-Object Length -Descending | Select-Object -First 1 
				
				#Create / Change PTR-record 
				If( !([string]::IsNullOrWhiteSpace($theReverseZone)) )#if reverse lookup zone for the IP exists 
				{
					$PtrDomainName = $FQDN + '.' # for PTR records the dot is added to the domain name 
					
					#reverese lookup zone name starts with IP-octet(s) (from 1 to 3). 
					#respectively resource record name contains remainig octets (from 3 to 1) 
					#Octet-parts of Zone Name are subtracted out of reversed IP. 
					$ptrRRName = $reversedIP -replace "(.*)$('\.' + $($theReverseZone -replace '\.in-addr\.arpa'))(.*)", '$1$2'  # The resource record name 
					$OldObj = $(Try {Get-DnsServerResourceRecord -Node $($ExistingPtr | Select-Object -ExpandProperty HostName | Where-Object {$ptrRRName -eq $_}) -ZoneName $theReverseZone -RRType "PTR" -ComputerName $in_dnsserver -ErrorAction SilentlyContinue} Catch {$null})
						If ($OldObj -eq $null) 
						{ 
							#Object does not exist in DNS, creating new one 
							$objCOMPLIANT_b = "$FQDN;ADD PTR;$hostIP;$in_HostDomainName;$ptrRRName;$PtrDomainName;$theReverseZone"
							###write-host "$FQDN;ADD PTR;$hostIP;$in_HostDomainName;$ptrRRName;$PtrDomainName;$theReverseZone"
							###write-host $FQDN + ":ADD PTR:" + $hostIP + "--" + $ptrRRName + "--" + $PtrDomainName + "--" + $theReverseZone
							Try {
								# -----   this line add A host automaticaly, at your own risk, you can try with -whatif
								#Add-DnsServerResourceRecordPtr -Name $ptrRRName -PtrDomainName $PtrDomainName -ZoneName $theReverseZone -ComputerName $in_dnsserver -ErrorAction SilentlyContinue
							} Catch {
								###write-host "Catch ADD DNS"
							}
							$writer.value += $objCOMPLIANT_b.toString()
						}
						Else 
						{
							$NewObj = Get-DnsServerResourceRecord -Node $($ExistingPtr | Select-Object -ExpandProperty HostName | Where-Object {$ptrRRName -eq $_}) -ZoneName $theReverseZone -RRType "PTR" -ComputerName $in_dnsserver 
							if ( $NewObj.count -eq 1)
							{
								$NewObj.RecordData.PtrDomainName = $FQDN + '.' 
								If (($NewObj.RecordData.PtrDomainName -ine $OldObj.RecordData.PtrDomainName)) 
								{
									#Objects are different: old - $OldObj, new - $NewObj. Performing change in DNS
									#write-host "::" $NewObj.RecordData.PtrDomainName "::" $OldObj.RecordData.PtrDomainName
									#write-host "$FQDN;UPD PTR;$hostIP;$NewObj;$OldObj;$theReverseZone"
									#write-host $FQDN + ":UPD PTR:" + $hostIP + "--" + $NewObj + "--" $OldObj + "--" + $theReverseZone
									Try {
										# -----   this line add PTR automaticaly, at your own risk, you can try with -whatif
										#Set-DnsServerResourceRecord -NewInputObject $NewObj -OldInputObject $OldObj -ZoneName $theReverseZone -ComputerName $in_dnsserver -ErrorAction SilentlyContinu
									} Catch {
										###write-host "Catch ADD PTR"
									}
						
								}
							}
							else
							{
								###write-host ":catch:" $NewObj.RecordData.PtrDomainName "::" $OldObj.RecordData.PtrDomainName
								# host have more than one ptr
							}
						}
					$OldObj = $null 
					$NewObj = $null 
				
				}

			}

		}
	} else {
	###Write-host "##### NO PING " $server
	}
}

#here are your results
$tw
