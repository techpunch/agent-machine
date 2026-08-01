---
name: filevault-off
summary: FileVault turned off — start this now, it runs for a while
when: before-you-start
---
Start it immediately and let it work in the background while we do everything else.

    sudo fdesetup disable

Why: FileVault requires someone to type a password at the login screen after every boot, and
this server has to come back from a power cut with nobody in the building. The two cannot
coexist. Decryption of an already-encrypted disk can take a long time, which is why this
goes first.

On a Mac set up with an Apple ID, FileVault is usually already on, so assume you need this
unless `fdesetup status` says otherwise.

The trade is real and worth knowing: with FileVault off, someone who physically steals this
Mac can read its disk. Encryption at rest that survives unattended reboot is designed but
not yet built — see recipes/make-data-encrypted.
