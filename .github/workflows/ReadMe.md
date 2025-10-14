# GitHub Workflows
Info about the GitHub Actions workflows here

## 📦 PublishPSModuleToGallery
For publishing a PowerShell module to the corresponding PSResourceRepository. Has some logic to publish to dev/prod PSResourceRepo based on the triggering event, like a GitHub Release, or a direct workflow invocation.

GitHub Deployment Environment info for variables / secrets for this workflow:

### Variables

| Variable | Example Value | Description |
| -------- | ------------- | ----------- |
PSGALLERY_DISPLAYNAME | `PSGallery` | Value to use a display name of PSResource Repo that will be temporarily registered in the runner, and to which to publish the PowerShell module
PSGALLERY_URI | https://www.powershellgallery.com/api/v2 | URI of target PS Resource repository to which to publish PowerShell module

### Secrets

| Secret | Example Value | Description |
| ------ | ------------- | ----------- |
PSGALLERY_APIKEY | `mysuperAPIKey-70821435-764a-4e6a-a397-9a48977be13b` | API key that provides write rights to the given PS Resource reposity (like myget.org or powershellgallery.com)