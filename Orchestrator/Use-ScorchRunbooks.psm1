[cmdletbinding()]
#region Global Params
[string]$global:SCORCHServer 
[bool]$global:UseHTTP = $false
[string]$global:RunbookGUID
[hashtable]$global:Headers
[hashtable]$global:InputParameters
[pscredential]$global:Cred
[array]$global:ReturnParameters
[string]$global:baseURL
[int]$global:APIVersion
[string]$global:LogFolder = "Logs"
[string]$global:EnvVarName = "Logs"
#endregion

#region Logging - DO NOT EDIT

# Validate Logs path and variable
if (!(Get-Variable "$($global:EnvVarName)")) {
	# Check for Logs path
	if (!(Test-Path "$($env:ProgramData)\$($global:LogFolder)")) {
		# Create it if not found
		New-Item -Type Directory -Path "$($env:ProgramData)\$($global:LogFolder)"
	}
	# Set persistent machine variable for $env:Logs to Logs folder
	[System.Environment]::SetEnvironmentVariable("$($global:EnvVarName)", "$($env:ProgramData)\$($global:LogFolder)", "Machine")
}

# Logging vars
$ScriptLogLocation = "$($global:EnvVarName)\"
$ScriptFile = Split-Path $PSCommandPath -Leaf
$scriptName = $ScriptFile.Substring(0, $ScriptFile.LastIndexOf("."))
$ScriptLogFile = "$($scriptName).log"

Function Write-Log {
	param (
		[Parameter(Mandatory = $false)]
		[string]$Message,
		[Parameter(Mandatory = $false)]
		[string]$LogLocation = $ScriptLogLocation,
		[Parameter(Mandatory = $false)]
		[string]$LogFile = $ScriptLogFile,
		[Parameter()]
		[ValidateSet("Info", "Warn", "Error")]
		[string]$Status = "Info"
	)
	
	function private:write-line {
		$TimeGenerated = "$(Get-Date -Format HH:mm:ss).$((Get-Date).Millisecond)+000"
		$Line = '<![LOG[{0}]LOG]!><time="{1}" date="{2}" component="{3}" context="" type="{4}" thread="" file="">'
		$LineFormat = $Message, $TimeGenerated, (Get-Date -Format MM-dd-yyyy), ("$($MyInvocation.ScriptName | Split-Path -Leaf):$($MyInvocation.ScriptLineNumber)"), $LogLevel
		$Line = $Line -f $LineFormat
		Add-Content -Value $Line -Path $logpath
	}
	
	#Create the full logpath variable
	$logpath = $Loglocation + $Logfile
	
	#Test for file existence, create if it isn't present.
	if (!(Test-Path $logpath -PathType Leaf)) {
		New-Item -Type file -Path $loglocation -Name $Logfile | Out-Null
	}
	
	#If the Try/Catch loop caught an error capture the error and the line, add it to the log file.
	#Clear the error variable to avoid reporting false errors as the script progresses.
	if ($Error) {
		$Status = "Error"
	}
	
	switch ($Status) {
		"Error" {
			$LogLevel = 3
			Write-Host "$($ScriptFile) - $($Message)" -ForegroundColor Red
			if ($Error) {
				$Error.clear()
			}
		}
		"Warn" {
			write-warning "$($ScriptFile) - $($Message)"
			$LogLevel = 2
		}
		default {
			write-verbose "$($ScriptFile) - $($Message)"
			$LogLevel = 1
		}
	}
	write-line
}

#endregion

#region API Config
$headersAPIv2 = @{
	'Accept'       = 'application/json;odata.metadata=none'
	'Content-Type' = 'application/json'
}

$headersAPIv1 = @{
	'Accept'                = 'application/atom+xml,application/xml'
	'Content-Type'          = 'application/atom+xml'
	'DataServiceVersion'    = '1.0;NetFx'
	'MaxDataServiceVersion' = '2.0;NetFx'
	'Pragma'                = 'no-cache'
}
#endregion

#region Internal Functions
function Test-APIUrl {
	param (
		[Parameter(Mandatory)]
		[string]$URL
	)
	
	try {
		Write-Log "Testing APIUrl: $URL"
		if ($global:Cred) {
			$apiStatus = [int](Invoke-WebRequest $URL -Credential $global:Cred -ea SilentlyContinue -UseBasicParsing).StatusCode
		}
		else {
			$apiStatus = [int](Invoke-WebRequest $URL -UseDefaultCredentials -ea SilentlyContinue -UseBasicParsing).StatusCode
		}
		
		Write-Log "Status: $apiStatus"
		$apiStatus
	}
 catch {
		$apiStatus = [int]$_.Exception.Response.StatusCode
		Write-Log "Status: $apiStatus"
		$apiStatus
	}
}

function Get-SCORCHAPIURL {
	param (
		[Parameter(Mandatory)]
		[string]$server
	)
	Write-Log -message "Getting API URL from $server"
	$apiPaths = @("Orchestrator2012/Orchestrator.svc", "api")
	foreach ($apiPath in $apiPaths) {
		Write-Log "Testing APIPath: $apiPath"
		switch ($global:UseHTTP) {
			$true {
				Write-Log "Using HTTP"
				$apiURL = "http://$($server):8080/$($apiPath)"
			}
			default {
				Write-Log "Using HTTPS"
				$apiURL = "https://$($server):8443/$($apiPath)"
			}
		}
		$apiTest = Test-APIUrl $apiURL
		if ($apiTest -eq 200) {
			Write-Log -Message "API URL is: $($apiURL)"
			$global:APIVersion = ($apiPaths.indexOf($apiPath) + 1)
			Write-Log -Message "API Version is: $global:APIVersion"
			return $apiURL
		}
	}
}

function Invoke-RunbookAPIv1 {
	[CmdletBinding()]
	param (
		[parameter()]
		[bool]$useDefaultCreds,
		[parameter()]
		[bool]$MonitorJob,
		[parameter()]
		[bool]$WaitForCompletion
	)
	
	function New-WebRequest {
		param ([string]$url,
			[string]$method)
		
		write-log -LogLocation $ScriptLogLocation -LogFile $ScriptLogFile -Message "Building request from $($url) and $($method)"
		
		$req = [System.Net.HttpWebRequest]::Create($url)
		
		# Build the request header
		$req.Method = $method
		$req.UserAgent = "Microsoft ADO.NET Data Services"
		$req.Accept = "application/atom+xml,application/xml"
		$req.ContentType = "application/atom+xml"
		$req.Headers.Add("Accept-Encoding", "identity")
		$req.Headers.Add("Accept-Language", "en-US")
		$req.Headers.Add("DataServiceVersion", "1.0;NetFx")
		$req.Headers.Add("MaxDataServiceVersion", "2.0;NetFx")
		$req.Headers.Add("Pragma", "no-cache")
		
		switch ($method) {
			"POST" {
				$req.KeepAlive = $true
			}
			"GET" {
				$req.Timeout = 120000
			}
			default {
			}
		}
		
		if ($useDefaultCreds) {
			write-log -LogLocation $ScriptLogLocation -LogFile $ScriptLogFile -Message "Using Default Creds"
			$req.UseDefaultCredentials = $true
		}
		else {
			write-log -LogLocation $ScriptLogLocation -LogFile $ScriptLogFile -Message "Using Supplied Creds"
			$req.Credentials = $global:Cred
		}
		
		return $req
	}
	
	function Invoke-SCORCHWebRequest {
		param ($req,
			$body)
		
		write-log -LogLocation $ScriptLogLocation -LogFile $ScriptLogFile -Message "Sending Web Request: $($req)"
		if ($body) {
			Write-Log -LogLocation $ScriptLogLocation -LogFile $ScriptLogFile -Message "Request has body, writing request stream."
			$requestStream = new-object System.IO.StreamWriter $req.GetRequestStream()
			$requestStream.Write($body)
			$requestStream.Flush()
			$requestStream.Close()
		}
		
		# Get the response from the request
		Write-Log -LogLocation $ScriptLogLocation -LogFile $ScriptLogFile -Message "Getting Response"
		[System.Net.HttpWebResponse]$res = [System.Net.HttpWebResponse]$req.GetResponse()
		
		write-log -LogLocation $ScriptLogLocation -LogFile $ScriptLogFile -Message "Returning Response"
		return $res
	}
	
	function Get-ResponseXML {
		param ($res)
		
		write-log -LogLocation $ScriptLogLocation -LogFile $ScriptLogFile -Message "Opening ResponseStream"
		# Write the HttpWebResponse to String
		$responseStream = $res.GetResponseStream()
		$readStream = new-object System.IO.StreamReader $responseStream
		$responseString = $readStream.ReadToEnd()
		
		# Close the streams
		$readStream.Close()
		$responseStream.Close()
		
		write-log -LogLocation $ScriptLogLocation -LogFile $ScriptLogFile -Message "Returning XML"
		Write-Debug "XML Data is: $($responseString)"
		return [xml]$responseString
	}
	
	function New-RunbookJob {
		write-log -LogLocation $ScriptLogLocation -LogFile $ScriptLogFile -Message "Creating Runbook Job"
		
		# Create the request object
		$request = New-WebRequest -url ($global:baseURL + "/Jobs") -method "POST"
		
		# If runbook servers are specified, format the string
		$rbServerString = ""
		if (-not [string]::IsNullOrEmpty($RunbookServers)) {
			$rbServerString = -join ("<d:RunbookServers>", $RunbookServers, "</d:RunbookServers>")
		}
		
		# Format the Runbook parameters, if any
		$rbParamString = ""
		if ($global:InputParameters -ne $null) {
			
			# Format the param string from the Parameters hashtable
			$rbParamString = "<d:Parameters><![CDATA[<Data>"
			foreach ($p in $global:InputParameters.GetEnumerator()) {
				$rbParamString = -join ($rbParamString, "<Parameter><ID>{", $p.key, "}</ID><Value>", $p.value, "</Value></Parameter>")
			}
			$rbParamString += "</Data>]]></d:Parameters>"
		}
		
		$requestBody = @"
<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<entry xmlns:d="http://schemas.microsoft.com/ado/2007/08/dataservices" xmlns:m="http://schemas.microsoft.com/ado/2007/08/dataservices/metadata" xmlns="http://www.w3.org/2005/Atom">
    <content type="application/xml">
        <m:properties>
            <d:RunbookId m:type="Edm.Guid">$global:RunbookGUID</d:RunbookId>
            $rbserverstring
            $rbparamstring
        </m:properties>
    </content>
</entry>
"@
		
		# Make Web Request and get Response
		$response = Invoke-SCORCHWebRequest -req $request -body $requestBody
		
		# Get the ID of the resulting job
		if ($response.StatusCode -eq 'Created') {
			$xmlDoc = Get-ResponseXML -res $response
			$jobId = $xmlDoc.entry.content.properties.Id.InnerText
			#LogWrite -logstring ("Successfully started runbook. Job ID: " + $jobId)
			write-log -LogLocation $ScriptLogLocation -LogFile $ScriptLogFile -Message ($jobID + ' has been started')
			if ($MonitorJob -or $WaitForCompletion -or ($global:ReturnParameters -ne $null)) {
				if ($MonitorJob) {
					Write-Host "Job Created with ID: $($jobId)"
				}
				
				Watch-RunbookJob -jobGUID $jobId
			}
		}
	}
	
	function Watch-RunbookJob {
		param ($jobGUID)
		
		write-log -LogLocation $ScriptLogLocation -LogFile $ScriptLogFile -Message "Waiting for Job to Complete"
		
		$complete = $false
		$i = 0
		do {
			$i = ($i + 10)
			start-sleep -s 10
			
			write-log -LogLocation $ScriptLogLocation -LogFile $ScriptLogFile -Message "Building Request for Job Monitoring"
			$request = New-WebRequest -url ($global:baseURL + "/Jobs(guid'$($jobGUID)')") -method "GET"
			
			write-log -LogLocation $ScriptLogLocation -LogFile $ScriptLogFile -Message "Calling Make-WebRequest for Job Monitoring"
			$response = Invoke-SCORCHWebRequest -req $request
			
			write-log -LogLocation $ScriptLogLocation -LogFile $ScriptLogFile -Message "Getting XML Data from Response"
			$xmlDoc = Get-ResponseXML -res $response
			
			$Status = $xmlDoc.entry.content.properties.Status
			
			if ($MonitorJob) {
				write-host "Monitoring Job"
				$message = "Current job status after $($i) seconds: $($Status)"
				switch ($Status) {
					"Pending" {
						write-host $message -ForegroundColor Yellow
					}
					"Running" {
						write-host $message -ForegroundColor White
					}
					"Completed" {
						write-host $message -ForegroundColor Green
					}
					default {
						write-host $message
					}
				}
			}
			
			if ($i -eq 1800 -and $Status -ne 'completed') {
				write-log -LogLocation $ScriptLogLocation -LogFile $ScriptLogFile -Message "$($jobGUID) did not complete in maximum time of five minutes." -LogLevel 3
				write-log -LogLocation $ScriptLogLocation -LogFile $ScriptLogFile -Message "If error continues, contact your System Center Orchestrator Adaministrator." -LogLevel 2
			}
		} Until ($i -eq 1800 -or $Status -eq 'Completed')
		
		if ($Status -eq "completed" -and ($global:ReturnParameters -ne $null)) {
			write-log -LogLocation $ScriptLogLocation -LogFile $ScriptLogFile -Message "Calling Parse-Instances"
			Get-Instances -jobGUID $jobGUID
		}
	}
	
	function Get-Instances {
		param ([string]$jobGUID)
		
		$request = New-WebRequest -url "$($global:baseURL)/Jobs(guid'$($jobGUID)')/Instances" -method "GET"
		$response = Invoke-SCORCHWebRequest -req $request
		$outXML = Get-ResponseXML -res $response
		$instancesURL = $outXML.feed.entry.id
		Get-ReturnedData -url $instancesURL
	}
	
	function Get-ReturnedData {
		param ([string]$url)
		write-log -LogLocation $ScriptLogLocation -LogFile $ScriptLogFile -Message "Getting returned data"
		$request = New-WebRequest -url "$($url)/Parameters" -method "GET"
		
		$response = Invoke-SCORCHWebRequest -req $request
		
		$outXML = Get-ResponseXML -res $response
		
		$data = @{
		}
		foreach ($parameter in $global:ReturnParameters) {
			$value = $outXML.feed.entry | where {
				$_.title.'#text' -eq $parameter
			} | % {
				$_.content.properties.Value
			}
			$data.Add($parameter, $value)
		}
		
		return $data	
	}
	
	New-RunbookJob
}

function Get-AllRunbookGuidsAPIv1 {
	#-------------------------------------------------------------------------------------------------------------
	# Author: Denis Rougeau
	# Date  : January 2014
	#
	# Purpose:  
	# Query SC Orchestrator 2012 Web Service and list all runbook and Parameter GUIDs.
	#
	# Version:
	# 1.0 - Initial Release
	#
	# Disclaimer: 
	# This program source code is provided "AS IS" without warranty representation or condition of any kind            
	# either express or implied, including but not limited to conditions or other terms of merchantability and/or            
	# fitness for a particular purpose. The user assumes the entire risk as to the accuracy and the use of this            
	# program code.    
	#-------------------------------------------------------------------------------------------------------------
	#
	# Configure the following variables
	[CmdletBinding()]
	param (
		[parameter(Mandatory = $false)]
		[bool]$SecureWeb = (!($UseHTTP)),
		[parameter(Mandatory = $false)]
		[string]$OrchServer = $global:SCORCHServer,
		[parameter(Mandatory = $false)]
		[bool]$UseDefaultCreds = $true
	)
	#
	#-------------------------------------------------------------------------------------------------------------
	
	function QuerySCOWebSvc {
		Param ([string]$url)
		
		$textXML = ""
		
		# Get the Request XML
		$SCOrequest = [System.Net.HttpWebRequest]::Create($url)
		$SCOrequest.Method = "GET"
		$SCOrequest.UserAgent = "Microsoft ADO.NET Data Services"
		
		# Set the credentials to default or prompt for credentials
		if ($UseDefaultCreds) {
			$SCOrequest.UseDefaultCredentials = $true
		}
		Else {
			$SCOrequest.Credentials = Get-Credential
		}
		
		# Get the response from the request
		[System.Net.HttpWebResponse]$SCOresponse = [System.Net.HttpWebResponse]$SCOrequest.GetResponse()
		
		# Build the XML 
		$reader = [IO.StreamReader]$SCOresponse.GetResponseStream()
		$textxml = $reader.ReadToEnd()
		[xml]$textxml = $textxml
		$reader.Close()
		
		Return $textxml
		
		Trap {
			Write-Host "-> Error Querying Orchestrator Web Service."
			Return ""
		}
	}
	
	if ($SecureWeb) {
		$protocol = "https://"
		$port = "8443"
	}
 else {
		$protocol = "http://"
		$port = "8080"
	}
	
	# Main
	$i = 0
	$colRunbooks = @()
	
	$SCOurl = "$($protocol)$($OrchServer):$($port)/Orchestrator2012/Orchestrator.svc/Runbooks?`$inlinecount=allpages"
	$SCOxml = QuerySCOWebSvc $SCOurl
	
	# Get the Number of Runbooks returned
	$RunbookEntries = $SCOxml.getElementsByTagName('entry')
	[int]$iNumRunbooks = $RunbookEntries.Count
	
	# Get the number Runbooks total
	[int]$iTotRunbooks = $SCOxml.GetElementsByTagName('m:count').innertext
	
	# Process Runbooks by pages if greater the the limits the web service can return.
	while ($i -lt $iTotRunbooks) {
		$Runbookurl = "$($protocol)$($OrchServer):$($port)/Orchestrator2012/Orchestrator.svc/Runbooks?`$skip=" + $i.ToString()
		$Runbookxml = QuerySCOWebSvc $Runbookurl
		
		# Get the Runbooks returned
		$RunbookEntries = $Runbookxml.getElementsByTagName('entry')
		
		foreach ($Entry in $RunbookEntries) {
			$RbkGUID = $Entry.GetElementsByTagName("content").childNodes.childnodes.item(0).innerText
			$RbkName = $Entry.GetElementsByTagName("content").childNodes.childnodes.item(2).innerText
			$RbkPath = $Entry.GetElementsByTagName("content").childNodes.childnodes.item(9).innerText
			
			$oRunbooks = New-Object System.Object
			$oRunbooks | Add-Member -type NoteProperty -name Guid -value $RbkGUID
			$oRunbooks | Add-Member -type NoteProperty -name Name -value $RbkName
			$oRunbooks | Add-Member -type NoteProperty -name Path -value $RbkPath
			$oRunbooks | Add-Member -type NoteProperty -name Param -value ""
			
			$colRunbooks += $oRunbooks
			
			# Get list of Parameters for the Runbook
			$urlrunbookparam = "$($protocol)$($OrchServer):$($port)/Orchestrator2012/Orchestrator.svc/Runbooks(guid'$RbkGUID')/Parameters"
			$runbookxmlparam = QuerySCOWebSvc $urlrunbookparam
			
			# Get all the entry nodes
			$ParamEntries = $runbookxmlparam.getElementsByTagName('entry')
			foreach ($ParamEntry in $ParamEntries) {
				$ParamGUID = $ParamEntry.GetElementsByTagName("content").childNodes.childnodes.item(0).innerText
				$ParamName = $ParamEntry.GetElementsByTagName("content").childNodes.childnodes.item(2).innerText
				
				$oRunbooks = New-Object System.Object
				$oRunbooks | Add-Member -type NoteProperty -name Guid -value $ParamGUID
				$oRunbooks | Add-Member -type NoteProperty -name Name -value $RbkName
				$oRunbooks | Add-Member -type NoteProperty -name Path -value $RbkPath
				$oRunbooks | Add-Member -type NoteProperty -name Param -value $ParamName
				
				$colRunbooks += $oRunbooks
				
			} # Loop ParamEntries
		} # Loop RunbookEntries
		$i += $iNumRunbooks
	}
	
	$colRunbooks | Sort-object Path, Name, Param | Select Path, GUID, Name, Param
	Write-Host "#Runbooks returned: $iNumRunbooks"
	Write-Host "#Runbooks total: $iTotRunbooks"
}

function Get-AllRunbooksAPIv2 {
	Write-Log "Calling $global:baseURL/Runbooks for Runbooks."
	return (Invoke-RestMethod -Uri "$global:baseURL/Runbooks" -Headers $global:Headers -UseDefaultCredentials).value | select Name, Id, Description | Sort-Object -Property Name
}

function Invoke-RunbookAPIv2 {
	param (
		[parameter()]
		[bool]$ReturnsData,
		[parameter()]
		[bool]$MonitorJob,
		[parameter()]
		[bool]$WaitForCompletion
	)
	$RunbookJob = New-RunbookJobAPIv2
	Write-Log -Message "RunbookJobId: $($RunbookJob.Id)"
	if ($ReturnsData -or $MonitorJob -or $WaitForCompletion) {
		Watch-RunbookJobAPIv2 $RunbookJob.Id
		if ($ReturnsData) {
			return Get-RunbookReturnAPIv2 $RunbookJob.Id
		}
	}
}

function New-RunbookJobAPIv2 {
	Write-Log -Message "Creating new Runbook Job"
	$paramString = ""
	if ($global:InputParameters) {
		Write-Log -Message "Input parameters specified. Creating Parameter JSON"
		$params = New-Object -TypeName System.Collections.ArrayList
		
		foreach ($p in $global:InputParameters.GetEnumerator()) {
			[void]$params.add($p)
		}
		
		$params = $params | convertto-json
		$paramString = ",""Parameters"": $($params)"
		
	}
	Write-Log -Message "Building web request body."
	$body = "{""RunbookId"":""$($global:RunbookGUID)""$paramString}"
	
	$runbookJob = switch ($AuthType) {
		"Default" {
			Write-Log -Message "Calling SCORCH with default credentials."
			(Invoke-RestMethod -Uri "$global:baseURL/Jobs" -Method Post -UseDefaultCredentials -Body $body -Headers $global:Headers)
		}
		default {
			Write-Log -Message "Calling SCORCH URL '$global:baseURL/Jobs' with provided credentials for $(($global:Cred).username)"
			(Invoke-RestMethod -Uri "$global:baseURL/Jobs" -Method Post -Credential $global:Cred -Body $body -Headers $global:Headers)
		}
	}
	Write-Log -Message "Returning Runbook Job"
	return $runbookJob
}

function Watch-RunbookJobAPIv2 {
	param (
		[guid]$jobId
	)
	Write-Log -Message "Waiting for Runbook Job to complete."
	$complete = $false
	$i = 0
	do {
		$i = ($i + 10)
		start-sleep -s 10
		$Status = switch ($AuthType) {
			"Default" {
				(Invoke-RestMethod -Uri "$global:baseURL/Jobs?`$filter=Id eq $($jobId)" -Method Get -UseDefaultCredentials -Headers $global:Headers).value.Status
			}
			default {
				(Invoke-RestMethod -Uri "$global:baseURL/Jobs?`$filter=Id eq $($jobId)" -Method Get -Credential $global:Cred -Headers $global:Headers).value.Status
			}
		}
		if ($MonitorJob) {
			write-host "Monitoring Job $($jobId)"
			$message = "Current job status after $($i) seconds: $($Status)"
			switch ($Status) {
				"Pending" {
					write-host $message -ForegroundColor Yellow
				}
				"Running" {
					write-host $message -ForegroundColor White
				}
				"Completed" {
					write-host $message -ForegroundColor Green
				}
				default {
					write-host $message
				}
			}
		}
	} Until ($Status -eq 'Completed')
}

function Get-RunbookReturnAPIv2 {
	param (
		[guid]$JobId
	)
	Write-Log -Message "Getting returned data from Runbook."
	$data = switch ($AuthType) {
		"Default" {
			$runbookInstanceId = (Invoke-RestMethod -Uri "$global:baseURL/RunbookInstances?`$filter=JobId eq $($JobId)" -Method Get -UseDefaultCredentials -Headers $global:Headers).value.Id
			Write-Log -Message "RunbookInstanceID: $($runbookInstanceId)"
			(Invoke-RestMethod -Uri "$global:baseURL/RunbookInstanceParameters?`$filter=RunbookInstanceId eq $($runbookInstanceId) and Direction eq 'Out'" -Method Get -UseDefaultCredentials -Headers $global:Headers).value
		}
		default {
			$runbookInstanceId = (Invoke-RestMethod -Uri "$global:baseURL/RunbookInstances?`$filter=JobId eq $($JobId)" -Method Get -Credential $global:Cred -Headers $global:Headers).value.Id
			(Invoke-RestMethod -Uri "$global:baseURL/RunbookInstanceParameters?`$filter=RunbookInstanceId eq $($runbookInstanceId) and Direction eq 'Out'" -Method Get -Credential $global:Cred -Headers $global:Headers).value
		}
	}
	return ($data | select Name, Value)
}
#endregion

#region Exported Functions
function Connect-SCORCHAPI {
	param (
		[parameter(Mandatory = $true)]
		[string]$Server
	)
	Write-Log -Message "Connecting to $Server."
	
	$global:SCORCHServer = $Server
	$global:baseURL = Get-SCORCHAPIURL -server $Server
	$global:Headers = switch ($global:APIVersion) {
		1 {
			$headersAPIv1
		}
		default {
			$headersAPIv2
		}
	}
}

function Get-AllScorchRunbooks {
	Write-Log "Getting Runbooks from $($global:SCORCHServer) using API version $($global:APIVersion)"
	switch ($global:APIVersion) {
		1 {
			Get-AllRunbookGuidsAPIv1
		}
		2 {
			Get-AllRunbooksAPIv2
		}
	}
}

function Get-RunbookGuid {
	param (
		[Parameter(Mandatory)]
		[string]$RunbookName
	)
	Write-Log -Message "Getting Runbook GUID for $($RunbookName)"
	$currenHeaders = $global:Headers
	$global:Headers = $headersAPIv2
	switch ($global:APIVersion) {
		1 {
			if ($global:Cred -ne $null) {
				((Invoke-WebRequest -Uri "$global:baseURL/Runbooks?`$filter=Name eq '$($RunbookName)'" -Headers $Global:Headers -Credential $global:Cred).content | ConvertFrom-Json).d.results.id
			}
			else {
				((Invoke-WebRequest -Uri "$global:baseURL/Runbooks?`$filter=Name eq '$($RunbookName)'" -Headers $Global:Headers -UseDefaultCredentials).content | ConvertFrom-Json).d.results.id
			}
			
		}
		2 {
			if ($global:Cred -ne $null) {
				(Invoke-RestMethod -Uri "$global:baseURL/Runbooks?`$filter=Name eq '$($RunbookName)'" -Headers $global:Headers -cred $Cred).value | select -ExpandProperty Id
			}
			else {
				(Invoke-RestMethod -Uri "$global:baseURL/Runbooks?`$filter=Name eq '$($RunbookName)'" -Headers $global:Headers -UseDefaultCredentials).value | select -ExpandProperty Id
			}
			
		}
	}
	$global:Headers = $currenHeaders
}

function Get-RunbookParams {
	param (
		[Parameter(ParameterSetName = "Name", Mandatory)]
		[string]$RunbookName,
		[Parameter(ParameterSetName = "Id", Mandatory)]
		[ValidateScript({
				try {
					[System.Guid]::Parse($_) | Out-Null
					$true
				}
				catch {
					$false
				}
			})]
		[guid]$RunbookId
	)
	switch ($PSCmdlet.ParameterSetName) {
		"Name" {
			$RunbookId = Get-RunbookGuid -RunbookName $RunbookName
		}
		"Id" {
			break
		}
		default {
			Write-Log -Message "No Runbook specified."
			$allRBs = Get-AllScorchRunbooks
			$allRBs | Out-GridView -OutputMode Single -OutVariable selRB -Title "Select Runbook" | Out-Null
			if ($selRB) {
				Write-Log "Selected Runbook: $($selRB.Name)"
				$RunbookId = $selRB.Id
			}
		}
	}
	Write-Log -Message "Getting all parameters for $($RunbookId)"
	$currenHeaders = $global:Headers
	$global:Headers = $headersAPIv2
	switch ($global:APIVersion) {
		1 {
			(Invoke-RestMethod -uri "$global:baseURL/Runbooks(guid'$RunbookId')/Parameters" -Headers $global:Headers -UseDefaultCredentials).d.results | select Name, Direction, Description, ID
		}
		2 {
			(Invoke-RestMethod -uri "$global:baseURL/RunbookParameters?`$filter=RunbookId eq $($RunbookId)" -Headers $global:Headers -UseDefaultCredentials).value | select Name, Direction, Description
		}
	}
	$global:Headers = $currenHeaders
}

function Get-RunbookInputParams {
	param (
		[Parameter(ParameterSetName = "Id")]
		[string]$RunbookId,
		[Parameter(ParameterSetName = "Name")]
		[string]$RunbookName
	)
	
	switch ($PSCmdlet.ParameterSetName) {
		"Name" {
			$RunbookId = Get-RunbookGuid -RunbookName $RunbookName
		}
		"Id" {
			break
		}
		default {
			Write-Log -Message "No Runbook specified."
			$allRBs = Get-AllScorchRunbooks
			$allRBs | Out-GridView -OutputMode Single -OutVariable selRB -Title "Select Runbook" | Out-Null
			if ($selRB) {
				Write-Log "Selected Runbook: $($selRB.Name)"
				$RunbookId = $selRB.Id
			}
		}
	}
	Write-Log -Message "Getting input parameters for $($RunbookId)"
	Get-RunbookParams -RunbookId $RunbookId | Where {
		$_.direction -eq "In"
	}
}

function Get-RunbookOutputParams {
	param (
		[Parameter(ParameterSetName = "Name", Mandatory)]
		[string]$RunbookName,
		[Parameter(ParameterSetName = "Id", Mandatory)]
		[ValidateScript({
				try {
					[System.Guid]::Parse($_) | Out-Null
					$true
				}
				catch {
					$false
				}
			})]
		[guid]$RunbookId
	)
	
	switch ($PSCmdlet.ParameterSetName) {
		"Name" {
			$RunbookId = Get-RunbookGuid -RunbookName $RunbookName
		}
		"Id" {
			break
		}
		default {
			Write-Log -Message "No Runbook specified."
			$allRBs = Get-AllScorchRunbooks
			$allRBs | Out-GridView -OutputMode Single -OutVariable selRB -Title "Select Runbook" | Out-Null
			if ($selRB) {
				Write-Log "Selected Runbook: $($selRB.Name)"
				$RunbookId = $selRB.Id
			}
		}
	}
	Write-Log -Message "Getting output parameters for $($RunbookId)"
	Get-RunbookParams -RunbookId $RunbookId | Where {
		$_.direction -eq "Out"
	}
}

function Invoke-Runbook {
	[cmdletbinding()]
	param (
		[parameter(Mandatory)]
		[string]$OrchServer,
		[Parameter(ParameterSetName = "APIv2", Mandatory)]
		[string]$RunbookName,
		[Parameter(ParameterSetName = "APIv1", Mandatory)]
		[ValidateScript({
				try {
					[System.Guid]::Parse($_) | Out-Null
					$true
				}
				catch {
					$false
				}
			})]
		[guid]$RunbookGuid,
		[parameter(ParameterSetName = "APIv1")]
		[parameter(ParameterSetName = "APIv2")]
		[hashtable]$InputParameters,
		[parameter(ParameterSetName = "APIv1")]
		[parameter(ParameterSetName = "APIv2")]
		[switch]$MonitorJob,
		[parameter(ParameterSetName = "APIv1")]
		[parameter(ParameterSetName = "APIv2")]
		[switch]$WaitForCompletion,
		[parameter(ParameterSetName = "APIv1")]
		[parameter(ParameterSetName = "APIv2")]
		[pscredential]$Cred,
		[parameter(ParameterSetName = "APIv1")]
		[switch]$SecureWeb,
		[parameter(ParameterSetName = "APIv1")]
		[switch]$InTaskSequence,
		[parameter(ParameterSetName = "APIv1")]
		[switch]$useDefaultCreds,
		[parameter(ParameterSetName = "APIv1")]
		[array]$returnParameters,
		[parameter(ParameterSetName = "APIv2")]
		[switch]$ReturnsData,
		[parameter(ParameterSetName = "APIv2")]
		[ValidateSet("Default", "TaskSequence", "Provided")]
		[string]$AuthType = "Default"
	)
	
	if ($InputParameters) {
		$global:InputParameters = $InputParameters
	}
	if ($Cred) {
		$global:Cred = $Cred
	}
 elseif ($AuthType -eq "Provided") {
		$global:Cred = Get-Credential -Message "Please enter Credentials with access to the Runbook."
	}
	if ($InTaskSequence -or ($AuthType -eq "TaskSequence")) {
		Write-Log -Message "In TaskSequence, providing NetworkAccessAccount Credentials."
		$tsenv = New-Object -ComObject Microsoft.SMS.TSEnvironment
		$NaaUser = $tsenv.Value("_SMSTSReserved1-000")
		$NaaPW = $tsenv.Value("_SMSTSReserved2-000")
		$PWSecure = ConvertTo-SecureString $NaaPW -AsPlainText -Force
		$global:Cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $NaaUser, $PWsecure
		Write-Log -Message "NAA Creds created."
	}
	
	switch ($PSCmdlet.ParameterSetName) {
		"APIv1" {
			if ($returnParameters) {
				$global:ReturnParameters = $returnParameters
			}
			$global:SCORCHServer = $OrchServer
			$global:RunbookGUID = $RunbookGuid
			$global:baseURL = Get-SCORCHAPIURL -server $OrchServer
			$global:Headers = $headersAPIv1
			
			Invoke-RunbookAPIv1 -useDefaultCreds $useDefaultCreds -MonitorJob $MonitorJob -WaitForCompletion $WaitForCompletion
		}
		
		"APIv2" {
			$global:SCORCHServer = $OrchServer
			$global:baseURL = Get-SCORCHAPIURL -server $OrchServer
			$global:Headers = $headersAPIv2
			
			$global:RunbookGUID = Get-RunbookGuid -RunbookName $RunbookName
			Invoke-RunbookAPIv2 -MonitorJob $MonitorJob -WaitForCompletion $WaitForCompletion -ReturnsData $ReturnsData
		}
	}	
}
#endregion

Export-ModuleMember -Function Connect-SCORCHAPI
Export-ModuleMember -Function Get-AllScorchRunbooks
Export-ModuleMember -Function Get-RunbookGuid
Export-ModuleMember -Function Get-RunbookParams
Export-ModuleMember -Function Get-RunbookInputParams
Export-ModuleMember -Function Get-RunbookOutputParams
Export-ModuleMember -Function Invoke-Runbook