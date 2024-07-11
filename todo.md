# Before 1.0
[love-exedit]
- add VERSION_INFO modifier for `love-exedit`


---


# Future Stuff
[misc]
- create github workflow action for people to use
- wildcards (*) for ignore/lib paths
- put module stuff (extract/compress etc) into threads to prevent hanging on large files

[linux]
- add `love-squashfs` :compress() for repackaging linux (chunk cap?)
- still keep the 'basic' output for linux, maybe -linux vs -AppImage ZIPs

[love-exedit]
- add option to pass rsrc file


---


# Things Not Being Added
- option to NOT zip up output and make folders instead, this is because you'd
  require 'Run As System Administrator' for running on windows for macos/linux
  as windows needs `mklink` for making the symlinks (which we avoid by rezipping)
- running with window disabled for pure CLI version, this is possible BUT
  `love-icon` + `love-exedit` both rely on love.graphics for resizing stuff
  so we'd need to recreate the functionality without it, or make people provide 
  all sizes+formats of icons which isn't nice
  
