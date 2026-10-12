<#
.SYNOPSIS
  Build, start, and restore the Tier 2 VMs (Windows host). kbook-vm.sh is the
  same driver for Linux and macOS hosts.

.DESCRIPTION
  kbook-vm.ps1 build                   build all VMs and snapshots (about 30-45 min)
  kbook-vm.ps1 restore <snapshot>      prereqs | cluster | cluster-prev
  kbook-vm.ps1 snapshots               list the snapshots
  kbook-vm.ps1 up | halt | status      start, stop, or show the VMs
  kbook-vm.ps1 ssh [vm]                open a shell on a VM (default cp1)
  kbook-vm.ps1 destroy                 delete the VMs and their snapshots

  Snapshots:
    prereqs        containerd and kubeadm/kubelet/kubectl at K8S_VERSION, no cluster (Chapter 18)
    cluster        a ready three-node cluster at K8S_VERSION (most Tier 2 labs)
    cluster-prev   a ready three-node cluster at K8S_PREV_VERSION (Chapter 19 upgrades it)
#>
param(
  [Parameter(Position = 0)] [string] $Command = "help",
  [Parameter(Position = 1)] [string] $Name = ""
)
$ErrorActionPreference = "Stop"
Set-Location -LiteralPath $PSScriptRoot

$Snapshots = @("prereqs", "cluster", "cluster-prev")
$Workers = @("node1", "node2")

function Read-Versions {
  $versions = @{}
  foreach ($line in Get-Content -LiteralPath (Join-Path $PSScriptRoot "..\..\versions.env")) {
    $line = $line.Trim()
    if ($line -eq "" -or $line.StartsWith("#")) { continue }
    $key, $value = $line.Split("=", 2)
    $versions[$key.Trim()] = ($value -split "#", 2)[0].Trim()
  }
  return $versions
}

# Run vagrant and stop the script if it fails.
function V {
  & vagrant @args
  if ($LASTEXITCODE -ne 0) { throw "vagrant $($args -join ' ') failed (exit code $LASTEXITCODE)" }
}

function Step([string] $Text) {
  Write-Host ""
  Write-Host ("==> {0}  [{1:HH:mm:ss}]" -f $Text, (Get-Date)) -ForegroundColor Cyan
}

# Wait until every node of the cluster on cp1 is Ready.
function Wait-Cluster {
  V ssh cp1 -c "kubectl wait --for=condition=Ready node --all --timeout=600s >/dev/null && kubectl get nodes -o wide"
}

# Install the tools at one version, then build a cluster and save it as a snapshot.
function Build-Cluster([string] $K8sVersion, [string] $SnapshotName, [bool] $SavePrereqs) {
  $env:KBOOK_K8S_VERSION = $K8sVersion
  Step "Installing kubeadm, kubelet and kubectl $K8sVersion"
  V provision --provision-with k8s-tools
  if ($SavePrereqs) {
    $env:KBOOK_SNAPSHOT = "prereqs"
    V provision --provision-with mark
    Step "Saving snapshot prereqs"
    V snapshot save --force prereqs
  }
  Step "kubeadm init on cp1 ($K8sVersion)"
  V provision cp1 --provision-with cluster-init
  Step "Joining the workers"
  V provision @Workers --provision-with cluster-join
  Step "Waiting until the Pod network works on every node"
  V provision cp1 --provision-with network-ready
  Wait-Cluster
  $env:KBOOK_SNAPSHOT = $SnapshotName
  V provision --provision-with mark
  Step "Saving snapshot $SnapshotName"
  V snapshot save --force $SnapshotName
}

$versions = Read-Versions
switch ($Command) {
  "build" {
    $started = Get-Date
    Step "Removing any old VMs"
    V destroy -f
    # A build that failed half way can leave a VM folder without a VM in it,
    # which makes VirtualBox refuse the name the next time.
    $vmDir = Join-Path $env:USERPROFILE "VirtualBox VMs"
    foreach ($vm in @("cp1") + $Workers) {
      $dir = Join-Path $vmDir "kbook-$vm"
      if ((Test-Path -LiteralPath $dir) -and -not (Test-Path -LiteralPath (Join-Path $dir "kbook-$vm.vbox"))) {
        Remove-Item -LiteralPath $dir -Recurse -Force
      }
    }
    Step "Creating the VMs (no provisioning yet)"
    V up --no-provision
    Step "Preparing the operating system on every VM"
    V provision --provision-with os
    Step "Saving the base snapshot os"
    V snapshot save --force os

    Build-Cluster $versions["K8S_VERSION"] "cluster" $true

    Step "Back to the base snapshot for the previous-version cluster"
    V snapshot restore os --no-provision
    Build-Cluster $versions["K8S_PREV_VERSION"] "cluster-prev" $false

    Step "Restoring snapshot cluster"
    V snapshot restore cluster --no-provision
    Wait-Cluster
    Remove-Item Env:\KBOOK_K8S_VERSION, Env:\KBOOK_SNAPSHOT -ErrorAction SilentlyContinue
    Step ("Build finished in {0:N0} minutes. The VMs are on snapshot cluster." -f ((Get-Date) - $started).TotalMinutes)
  }
  "restore" {
    if ($Snapshots -notcontains $Name) { throw "usage: kbook-vm.ps1 restore <$($Snapshots -join '|')>" }
    $started = Get-Date
    Step "Restoring snapshot $Name on every VM"
    V snapshot restore $Name --no-provision
    if ($Name -ne "prereqs") { Wait-Cluster }
    Step ("Snapshot {0} restored in {1:N0} seconds. Work on cp1: kbook-vm.ps1 ssh" -f $Name, ((Get-Date) - $started).TotalSeconds)
  }
  "snapshots" { V snapshot list }
  "up"        { V up --no-provision }
  "halt"      { V halt }
  "status"    { V status }
  "ssh"       { if ($Name -eq "") { $Name = "cp1" }; V ssh $Name }
  "destroy"   { V destroy -f }
  default     { Get-Help $PSCommandPath -Detailed }
}
