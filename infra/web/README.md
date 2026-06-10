# MicroHack SQL 2026 Lab Deployer

Local web UI for configuring and launching the MicroHack SQL 2026 lab deployment.

## Run

```powershell
cd web
npm install
npm start
```

Open <http://127.0.0.1:3000>.

## What it does

- Serves a plain HTML/CSS/JS frontend from `web\public`.
- Lists Azure subscriptions using `az account list`.
- Starts preview or deployment jobs by shelling out to `..\scripts\deploy.ps1` with `pwsh -File`.
- Streams live stdout/stderr logs to the browser with Server-Sent Events.
- Tracks in-memory job status at `/api/jobs/:jobId`.

The PowerShell invocation uses this contract:

```powershell
-SubscriptionId -TenantId -UserCount -StartIndex -Location -Prefix -VmAdminPassword -SqlAdminPassword -DeploySqlMi -DeploySourceVm -CreateUsers -WhatIf -SetupScriptUri
```

## Security warning

This tool binds to `127.0.0.1` only, but it runs Azure deployments using the caller's current Azure CLI login. Run it only on a trusted machine and do not expose it to a network.
