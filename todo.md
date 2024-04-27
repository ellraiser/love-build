# Before 1.0
[misc]
- improve zip speed, bottleneck is crc32 checksum i think?

[love-exedit]
- add VERSION_INFO modifier for `love-exedit`


---


# Future Stuff
[misc]
- wildcards * for ignore/lib paths

[linux]
- add `love-squashfs` :compress() for repackaging linux
- still keep the 'basic' output for linux, maybe -linux vs -AppImage ZIPs

[love-exedit]
- add option to pass rsrc file



---


# Probably Won't Add
- option to NOT zip up output and make folders instead, this is because you'd
  require 'Run As System Administrator' for running on windows for macos/linux
  as windows needs `mklink` for making the symlinks (which we avoid by rezipping)
- running with window disabled for pure CLI version, this is possible BUT
  `love-icon` + `love-exedit` both rely on love.graphics for resizing stuff
  so we'd need to recreate the functionality without it, or make people provide 
  all sizes+formats of icons which isn't nice
  