# This script checks the current encryption method of the device. If the device is not encrypted or is encrypted with a method other than XTS-AES-256, it will decrypt the drive and then re-encrypt it using XTS-AES-256
# Check if BitLocker is enabled and if the encryption method is XTS-AES-256
if ($BitLockerStatus.ProtectionStatus -eq 'On' -and $BitLockerStatus.EncryptionMethod -eq 'XTSAES256')
{
    Write-Host "BitLocker is already enabled with XTSAES256 encryption. No action needed."
    exit
}

# If BitLocker is not enabled with AES-256, check if it's currently encrypted or not
if ($BitLockerStatus.ProtectionStatus -eq 'Off')
{
    Write-Host "BitLocker is not enabled. Starting encryption with XTSAES256."
    
    
    manage-bde.exe -protectors -delete C:
    Add-BitLockerKeyProtector -MountPoint "C:" -RecoveryPasswordProtector
    # Start encryption with AES256
    Enable-BitLocker -MountPoint "C:" -EncryptionMethod XtsAes256 -TpmProtector -SkipHardwareTest

    # Wait until encryption is complete (optional, can be adjusted based on your needs)
    Write-Host "Encryption in progress..."
    while ((Get-BitLockerVolume -MountPoint "C:").VolumeStatus -ne 'FullyEncrypted') {
        Start-Sleep -Seconds 10
    }

    Write-Host "Encryption completed successfully."
}
else
{
    Write-Host "BitLocker is enabled but not with XTSAES256 encryption. Decrypting and re-encrypting with AES-256."

    # Decrypt the drive
    Disable-BitLocker -MountPoint "C:"
    
    # Wait until decryption is complete (optional, can be adjusted based on your needs)
    Write-Host "Decryption in progress..."
    while ((Get-BitLockerVolume -MountPoint "C:").VolumeStatus -ne 'FullyDecrypted') {
        Start-Sleep -Seconds 10
    }

    Write-Host "Decryption completed successfully."
    manage-bde.exe -protectors -delete C:
    Add-BitLockerKeyProtector -MountPoint "C:" -RecoveryPasswordProtector

    # Re-encrypt with XTSAES256
    Enable-BitLocker -MountPoint "C:" -EncryptionMethod XtsAes256 -TpmProtector -SkipHardwareTest
    

    # Wait until encryption is complete (optional, can be adjusted based on your needs)
    Write-Host "Re-encryption in progress..."
    while ((Get-BitLockerVolume -MountPoint "C:").VolumeStatus -ne 'FullyEncrypted') {
        Start-Sleep -Seconds 10
    }

    Write-Host "Re-encryption completed successfully."
}
