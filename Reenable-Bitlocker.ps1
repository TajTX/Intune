<#
DISCLAIMER:
This script is provided "as is" without warranty of any kind, express or implied. Use this script at your own risk.
The author and contributors are not responsible for any damage or issues potentially caused by the use of this script.
Always test scripts in a non-production environment before deploying them into a production setting.
#>

$Mount = "C:"
$LogDir = "$env:ProgramData\BitLocker"
$LogFile = Join-Path $LogDir "Reenable-BitLocker.log"
New-Item -Path $LogDir -ItemType Directory -Force | Out-Null

function Log($msg) {
    $stamp = (Get-Date).ToString("s")
    "$stamp  $msg" | Out-File -FilePath $LogFile -Append -Encoding utf8
}

try {
    $bl = Get-BitLockerVolume -MountPoint $Mount
} catch {
    Log "ERROR: Get-BitLockerVolume failed. $_"
    exit 1
}

Log "State: VolumeStatus=$($bl.VolumeStatus) ProtectionStatus=$($bl.ProtectionStatus) EncryptionMethod=$($bl.EncryptionMethod) Encryption%=$($bl.EncryptionPercentage)"

# 1) If an operation is already running, don't interfere
if ($bl.VolumeStatus -in @("EncryptionInProgress","DecryptionInProgress")) {
    Log "No action: BitLocker operation already in progress ($($bl.VolumeStatus))."
    exit 0
}

# 2) If already compliant, exit
# ProtectionStatus in Get-BitLockerVolume indicates whether protectors are actively protecting the volume key. 
if ($bl.VolumeStatus -eq "FullyEncrypted" -and $bl.EncryptionMethod -eq "XtsAes256" -and $bl.ProtectionStatus -eq 1) {
    Log "No action: FullyEncrypted + XtsAes256 + Protection On."
    exit 0
}

# 3) Ensure TPM is ready before attempting TPM protector enablement
$tpm = Get-Tpm
if (-not $tpm.TpmPresent -or -not $tpm.TpmReady) {
    Log "ERROR: TPM not present/ready. Cannot enforce TPM protector."
    exit 2
}

# Helper: ensure recovery password protector exists (do not delete existing protectors)
function Ensure-RecoveryPasswordProtector($blObj) {
    $hasRecoveryPw = $blObj.KeyProtector | Where-Object { $_.KeyProtectorType -eq "RecoveryPassword" }
    if (-not $hasRecoveryPw) {
        Log "Adding RecoveryPassword protector."
        Add-BitLockerKeyProtector -MountPoint $Mount -RecoveryPasswordProtector | Out-Null
    } else {
        Log "RecoveryPassword protector already present."
    }
}

# 4) If fully encrypted but wrong encryption method -> start decryption and exit
# Encryption method changes require re-encryption; policy changes don't restart encryption.
if ($bl.VolumeStatus -eq "FullyEncrypted" -and $bl.EncryptionMethod -ne "XtsAes256") {
    Log "Starting decryption (current method=$($bl.EncryptionMethod)) so next run can re-encrypt with XtsAes256."
    Disable-BitLocker -MountPoint $Mount
    exit 0
}

# 5) If fully decrypted -> enable BitLocker with XtsAes256 + TPM protector and exit
# Microsoft shows enabling BitLocker with TPM protector and XtsAes256 for automation scenarios.
if ($bl.VolumeStatus -eq "FullyDecrypted") {
    Ensure-RecoveryPasswordProtector -blObj $bl
    Log "Enabling BitLocker with XtsAes256 + TPM protector."
    Enable-BitLocker -MountPoint $Mount -EncryptionMethod XtsAes256 -TpmProtector -SkipHardwareTest
    exit 0
}

# 6) If encrypted but protection is off, resume protection (don’t delete protectors)
# ProtectionStatus indicates whether key protectors are being used. 
if ($bl.VolumeStatus -eq "FullyEncrypted" -and $bl.ProtectionStatus -eq 0) {
    Log "Protection is Off while encrypted. Attempting Resume-BitLocker."
    Resume-BitLocker -MountPoint $Mount
    exit 0
}

# 7) Catch-all: log state and exit
Log "No direct action taken for current state."
exit 0
