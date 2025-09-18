# AWS SSO Programmatic Credentials, Programmatically
When credentials are available via the AWS SSO Identity Center ("IDC"), we can [reasonably] easily get AWS credentials for use with the AWS tools that we know and love (SDKs, CLIs, PowerShell modules, etc.).

Herein is a PowerShell module that simplifies getting accounts, roles, and credentials for some identity (the user).

## What
Simplify the creation of AWS credentials to SSO accounts/roles that an identity is entitled via AWS SSO Identity Center.

## Quick Start
To import this module
1. Save or install the module from the PowerShell Gallery:
    ```powershell
    ## save it locally for initial inspection -- safety first!
    Find-Module vN.AWSSSO | Save-Module -Path C:\Temp
    ## ..then inspect code to confirm trustworthiness

    ## orrr, install straight away, as vNugglets is a reputable publisher
    Find-Module vN.AWSSSO | Install-Module
    ```
1. Profit (see examples in [How](#how) section below)

### And, handy default value for Parameter
To simplify even further the getting of temporary credentials from AWS for accounts/roles, we can make a default value for the `-StartUrl` parameter of `New-VNAWSSSOOIDCTokenViaDeviceCode`:
```powershell
$PSDefaultParameterValues['New-VNAWSSSOOIDCTokenViaDeviceCode:StartUrl'] = "https://mycoolstart.awsapps.com/start/"
```
This then passes the given URL as the value for `-StartUrl` to this cmdlet each time we invoke the cmdlet. And, of course, we could put that default parameter value definition in somewhere like our PowerShell profile so that this default is always in place.

## Why
It is currently a bit more involved than "auth, then get creds for account/role". So, to make most simple the flow of getting such credentials in a natural way (minimal/zero configuration, and with rich objects and normal filtering we all know and love), let's abstract away the intricacies and make things "just work". 👍

## Gist
Super simple pseudo code depiction:
```
new oidc token | get accounts | get roles | get rolecred | do something with rolecred
```

A bit more explicit-, but still pseudo, flow:
```PowerShell
## some pseudo code to describe the flow
## get the SSO OIDC access token that will allow us to do subsequent things (get account info, get account role info, get role cred)
new ssooidc token
## get the accounts to which the OIDC token provides access
get sso account list | Foreach-Object
    ## get the SSO-related roles to which we are entitled in the given AWS account
    get sso account role list |
        ## filter on <whatveer we like> to get just the account/role info for which to get temp creds
        Where-Object rolename matches something | Foreach-Object
            ## get the temp creds for the given account and role combos
            Get-SSORoleCredential
## do something with those creds; for example, save them in the AWS creds location like .NET SDK or CLI "shared-creds" ini file)
| save the AWS credential

## then, profit!
```
## How
A mostly realistic example of getting some credentials.

1. Authenticate in your web browser as the account you want to use for AWS SSO interaction. For example, if Microsoft is the federated identity provider, go to the account management page there (https://myaccount.microsoft.com) and ensure that the desired account is "signed in" in the given web browser
1. Using cmdlets from this module, get and filter some role/account info, generate new temp credentials, and save them:
    ```PowerShell
    ## make a new SSO OIDC token
    New-VNAWSSSOOIDCTokenViaDeviceCode -StartUrl https://mycoolstart.awsapps.com/start/ -Verbose
    ## get account/role info, filter, get cred for role, get AWS temp cred
    Get-VNAWSSSOAccountAndRoleInfo |
        Where-Object accountname -like my-cool-account-* |
        Where-Object RoleName -match _myadminrole_ |
        New-VNAWSSSORoleTempCredential -Verbose |
        ## save to the AWS creds file the temp creds for each account/role
        Set-AWSCredential -ProfileLocation (Resolve-Path ~\.aws\credentials)
    ```

And, to see that example as a likely candidate to paste straight into a PowerShell session (one-line format):
```PowerShell
## make a new SSO OIDC token, get account/role info, filter, get cred for role, get AWS temp cred, save to the AWS creds file the temp creds for each account/role
New-VNAWSSSOOIDCTokenViaDeviceCode -StartUrl https://mycoolstart.awsapps.com/start/; Get-VNAWSSSOAccountAndRoleInfo | Where-Object accountname -like my-cool-account-* | Where-Object RoleName -match _myadminrole_ | New-VNAWSSSORoleTempCredential -Verbose | Set-AWSCredential -ProfileLocation (Resolve-Path ~\.aws\credentials)
```

## More Coolness 😎
One of the wonderful things that this approach enables is the programmatic retrieval of accounts and roles to which an identity/user is entitled.

It is in the "get temp creds" example above, but to focus on the, "get all the roles/accounts I _could_ use" use case:
```PowerShell
## get _all_ account/role info for this user identity
Get-VNAWSSSOAccountAndRoleInfo
## *poof*!

## get account/role info, filter like all the other PowerShell filtering we already know and love ❣!
Get-VNAWSSSOAccountAndRoleInfo |
    Where-Object accountname -like my-cool-account-* |
    Where-Object RoleName -match _myadminrole_
```

## Other
The native AWS cmdlets can make all of this happen. This module is to simplify such things, so we can:
- easily get the accounts and roles to which our identity is entitled
    - this enables the natural PowerShell behavior we know and love of, "get some stuff, maybe filter some stuff, then do something with the stuff"
    - so, for example, we can now programmatically get all of the accounts/roles to which we are entitled _as objects_, and then do the rest of the "cool" (valuable) stuff for the use case -- audit access, filter which roles to generate creds for, etc
- easily generate role credentials
    - this also enables some natural PowerShell behavior:  get some creds and do something with them; namely, save in the \<wherever the use case dictates> location
    - ...say, by piping the object to something that will store the credential, like `Set-AWSCredential`, and with the flexibility to specify the traditional filesystem shared-credentials file, or in a secure place (.NET SDK store), or wherever

This module provides similar outcomes to the module https://github.com/e0c615c8e4d846ef817cd5063a88716c/AWSSSOHelper, but also focuses on enabling those aforementioned "natural" PowerShell capabilities / experiences / use-cases.