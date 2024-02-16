# Before 1.0
[misc]
- improve zip speed, bottleneck is crc32 checksum i think?

[love-exedit]
- add VERSION_INFO modifier for `love-exedit`


---


# Future Stuff
[misc]
- wildcards * for ignore/lib paths
- platform specific libs options
- option to NOT zip up output and make folders instead?
  this would require 'Run As System Administrator' for running on windows for macos/linux
  as windows needs `mklink` for making the symlinks (which we avoid by rezipping)
- run with window disabled for pure CLI version?
  yes however `love-icon` + `love-exedit` relies on love.graphics for resizing stuff
  so we'd need to recreate the functionality without it (or make people provide all sizes)

[linux]
- fix `love-squashfs` :compress() for repackaging linux
- still keep the 'basic' output for linux, maybe -linux vs -AppImage ZIPs

[love-exedit]
- add option to pass rsrc file
