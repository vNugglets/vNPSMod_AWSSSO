function New-VNAWSSSOOIDCTokenViaDeviceCode {
    <#
        .Description
        Generate SSO OIDC Token using a device code via AWS SSO and SSOOIDC. To then subsequently use to get SSO role temporary credentials

        .Example
        New-VNAWSSSOOIDCTokenViaDeviceCode -StartUrl https://mycoolstart.awsapps.com/start/
        Go through the process of getting a new SSO OIDC token, using browser for credential verification, and specified "Start" URL

        .Notes
        That this uses a browser for credential verification, you should have already authenticated in your browser with at least the credential to use for subsequent AWS role interaction. That is, if using Microsoft Online for account management, have authenticated with the desired account at http://myaccount.microsoft.com before using this script to generate a new AWS OIDC token

        Handy: so as to be able to use this cmdlet with some default StartUrl, you can leverage the PowerShell feature PSDefaultParameterValues:
            $PSDefaultParameterValues['New-VNAWSSSOOIDCTokenViaDeviceCode:StartUrl'] = "https://mycoolstart.awsapps.com/start/"
        Adding this to somewhere like, say, your PowerShell profile will then use that default value for the -StartUrl parameter to this cmdlet (easy!)

    #>
    #Requires -Module AWS.Tools.SSO, AWS.Tools.SSOOIDC
    [CmdletBinding()]
    param (
        ## AWSApps "Start" url
        [parameter(Mandatory = $true)][System.Uri]$StartUrl,

        ## AWS Region to use
        $Region = "us-east-2"
    )
    begin {
        ## set the AWS region to use for this script
        Set-DefaultAWSRegion -Scope Script -Region $Region
        ## set the AWS anonymous credentials to use for this script (actual user-specific creds are used in the browser)
        Set-AWSCredential -Scope Script -Credential ([Amazon.Runtime.AnonymousAWSCredentials]::new())
        ## register the SSO OIDC client for use in device authorization and token creation
        $oSSOOIDCClient = Register-SSOOIDCClient -ClientName powershell-sso-client -ClientType public
    }

    process {
        ## API doc at https://docs.aws.amazon.com/singlesignon/latest/OIDCAPIReference/API_StartDeviceAuthorization.html
        $oDeviceAuthorization = $oSSOOIDCClient | Start-SSOOIDCDeviceAuthorization -StartUrl $StartUrl

        ## currently, launch web browser to authenticate
        $oTmp = Start-Process -PassThru $oDeviceAuthorization.VerificationUriComplete

        ## try to generate a new SSO OIDC token
        try {
            while (-not $oSSOOIDCToken) {
                try { $oSSOOIDCToken = $oSSOOIDCClient | New-SSOOIDCToken -DeviceCode $oDeviceAuthorization.DeviceCode -GrantType "urn:ietf:params:oauth:grant-type:device_code" }
                ## if still pending authorization, continue to wait and retry
                catch [Amazon.SSOOIDC.Model.AuthorizationPendingException] {
                    Write-Verbose -Message "Standing by for authorization in browser (yes, by _you_!)"; Start-Sleep -Seconds 1
                }
            }
            ## set as global variable, for subsequent use later in this session
            $oSSOOIDCToken | Add-Member -MemberType NoteProperty -Name ExpiresAt -Value (Get-Date).AddSeconds($oSSOOIDCToken.ExpiresIn)
            Set-Variable -Scope Global -Name AWSSSOOIDCToken -Value $oSSOOIDCToken
            Write-Verbose -Message "Generated new SSO OIDC token valid for a timespan of '$(New-TimeSpan -Seconds $oSSOOIDCToken.ExpiresIn)' (expires at '$($oSSOOIDCToken.ExpiresAt)'). Save as global variable '`$global:AWSSSOOIDCToken'"
            Write-Verbose -Message "You can use the SSO OIDC token for getting SSO accounts and their associated roles (via Get-SSOAccountList/Get-SSOAccountRoleList), and for generating new temporary credentials from an SSO role (say, via Get-SSORoleCredential or some helper script)"
            return $oSSOOIDCToken
        }
        ## else, return the error
        catch { $_ }
    }
}


function Get-VNAWSSSOAccountAndRoleInfo {
    <#
        .Description
        Get the AWS SSO account(s) and role(s) to which an identity has access (the identity associated with the given AccessToken), for subsequent use for generating temporary credentials for any such account/role

        .Example
        New-VNAWSSSOOIDCTokenViaDeviceCode -StartUrl https://mycoolstart.awsapps.com/start/ | Get-VNAWSSSOAccountAndRoleInfo
        Get a new SSO OIDC access token for some identity, then get the SSO accounts and roles to which the access token provides permission

        .Example
        Get-VNAWSSSOAccountAndRoleInfo -Name mysandbox*, mydev*
        Get the SSO accounts and roles to which the previously retrieved access token (via New-VNAWSSSOOIDCTokenViaDeviceCode) provides permission. Uses the wildcarded names to filter _which_ AWS accounts for which to get the account- and role info
    #>
    #Requires -Module AWS.Tools.SSO
    [CmdletBinding()]
    param (
        ## AWS SSO OIDC access token to use for SSO getting role/credential items. Generated from something like New-VNAWSSSOOIDCTokenViaDeviceCode
        [parameter(ValueFromPipelineByPropertyName = $true)][String]$AccessToken = ${global:AWSSSOOIDCToken}.AccessToken,

        ## Name(s) of AWS account(s) of interest, for which to get account/role information. Defaults to getting role information for all AWS accounts to which the given access token has permissions. Supports using wildcards.
        [SupportsWildcards()][String[]]$Name = "*",

        ## AWS Region to use
        $Region = "us-east-2"
    )
    begin {
        ## set the AWS region to use for this script
        Set-DefaultAWSRegion -Scope Script -Region $Region
        ## set the AWS anonymous credentials to use for this script (actual user-specific creds are used in the browser)
        Set-AWSCredential -Scope Script -Credential ([Amazon.Runtime.AnonymousAWSCredentials]::new())
    }

    process {
        ## for this script, let's set the AccessToken for the SSO cmdlets to use; make sure that we have a defaultParams hashtable for starters
        $private:PSDefaultParameterValues = if ($private:PSDefaultParameterValues) { $private:PSDefaultParameterValues } else { @{} }
        $private:PSDefaultParameterValues['Get-SSO*:AccessToken'] = $AccessToken
        ## get the SSO Account(s) and corresponding Roles that this SSO OIDC access token has permissions to use (can later be used to generate role temporary credential via something like Get-SSORoleCredential)
        Get-SSOAccountList -PipelineVariable oThisSSOAccountItem | Where-Object {$Name.Where({$oThisSSOAccountItem.AccountName -like $_})} | Get-SSOAccountRoleList | Select-Object @{n="AccountName"; e={$oThisSSOAccountItem.AccountName }}, *, @{n="Region"; e={$Region}}
    }
}



function New-VNAWSSSORoleTempCredential {
    <#
    .Description
    Generate temporary credentials for some account(s) and role(s) via AWS SSO and SSOOIDC

    .Example
    New-VNAWSSSOOIDCTokenViaDeviceCode -StartUrl https://mycoolstart.awsapps.com/start/; Get-VNAWSSSOAccountAndRoleInfo -Name my-cool-account-* | Where-Object RoleName -match _mycoolrole_ | New-VNAWSSSORoleTempCredential | Set-AWSCredential -ProfileLocation (Resolve-Path ~\.aws\credentials) -Verbose
    For the SSO accounts/roles to which the given user is entitled and whose attributes match the filters (account name, role name), generate temporary credentials for the role and save in default AWS local creds store as specified "StoreAs" profile name in the object piped to Set-AWSCredential

    .Example
    New-VNAWSSSOOIDCTokenViaDeviceCode -StartUrl https://mycoolstart.awsapps.com/start/; Get-VNAWSSSOAccountAndRoleInfo | New-VNAWSSSORoleTempCredential | Set-AWSCredential -Verbose
    For all of the SSO accounts/roles to which the given user is entitled, generate temporary credentials for the role and save the credentials (from help for Set-AWSCredential, not specifying -ProfileLocation will try to use "the encrypted credential file used by the AWS SDK for .NET and AWS Toolkit for Visual Studio first. If the profile is not found then the cmdlet will search in the ini-format credential file at the default location: (user's home directory)\.aws\credentials")
#>
    #Requires -Module AWS.Tools.SSO
    [CmdletBinding(SupportsShouldProcess)]
    param (
        ## AWS Account ID (account number) for which to get temporary credential for SSO role
        [parameter(Mandatory, ValueFromPipelineByPropertyName = $true)][String]$AccountId,

        ## Name of AWS Role for which to getting temporary credentials
        [parameter(Mandatory, ValueFromPipelineByPropertyName = $true)][String]$RoleName,

        ## Diplay Name of AWS account involved. Only used for saving the credentials as a profile name. If none, AccountId is used for the persisted profile name
        [parameter(ValueFromPipelineByPropertyName = $true)][String]$AccountName,

        ## AWS SSO OIDC access token to use for SSO getting role/credential items. Generated from something like New-VNAWSSSOOIDCTokenViaDeviceCode, and possibly already defined as a global variable by such script, so may not need to explicitly pass here
        [parameter(ValueFromPipelineByPropertyName = $true)][String]$AccessToken = ${global:AWSSSOOIDCToken}.AccessToken,

        ## AWS Region to use
        [parameter(ValueFromPipelineByPropertyName = $true)]$Region = "us-east-2"
    )

    begin {
        ## set the AWS region to use for this script
        Set-DefaultAWSRegion -Scope Script -Region $Region
        ## set the AWS anonymous credentials to use for this script (actual user-specific creds are used in the browser)
        Set-AWSCredential -Scope Script -Credential ([Amazon.Runtime.AnonymousAWSCredentials]::new())
    }

    process {
        ## params for getting role credential
        $hshParamsForGetSSORoleCredential = @{
            AccountId        = $AccountId
            RoleName         = $RoleName
            AccessToken      = $AccessToken
            PipelineVariable = "oThisRoleCredential"
        }

        ## ShouldProcess args
        $strShouldProcessMsg = "Get temporary credential for role '$RoleName'"
        $strShouldProcessTarget = "AWS account '{0}'" -f $(if ($PSBoundParameters.ContainsKey("AccountName")) { "$AccountName ($AccountId)" } else { $AccountId })

        if ($PSCmdlet.ShouldProcess($strShouldProcessTarget, $strShouldProcessMsg)) {
            ## get the role credential for the given acct/role, then write to local AWS temp creds store
            Get-SSORoleCredential @hshParamsForGetSSORoleCredential | ForEach-Object {
                ## make an object with the properties that Set-AWSCredential takes from pipeline (and an extra, informational property, "Note")
                New-Object -Type PSObject -Property @{
                    AccessKey    = $_.AccessKeyId
                    SecretKey    = $_.SecretAccessKey
                    SessionToken = $_.SessionToken
                    StoreAs      = if ($PSBoundParameters.ContainsKey("AccountName")) { $AccountName } else { $AccountId }
                    Note         = "credential for $strShouldProcessTarget, role '$RoleName'; expires at '{0} {1}' (in timespan of '{2}')" -f ($dteCredExpiry = Get-Date -UnixTimeSeconds ($oThisRoleCredential.Expiration / 1000)), ([System.DateTimeOffset]::Now).Offset.ToString(), $(New-TimeSpan -End $dteCredExpiry)
                } -OutVariable oCredsInfoItem
                Write-Verbose -Message "Got $($oCredsInfoItem.Note)"
            }
        }
    }
}
