# Future Stuff
[linux]
- add `love-squashfs` :compress() for repackaging linux as an AppImage (chunk cap check)
  + still keep the 'basic' output for linux, i.e. both -linux AND -AppImage ZIPs 
  + appimage issue max chunk size check in case we store bigger blocks?

[windows]
- file version doesnt seem to update correctly all the time, need to update the FIXED_FILE_INFO as well I think


---


# Things Not Being Added
- any external libraries or dependencies, some stuff might be quicker with a 
  seperate app but the point is to make a self-contained pure love/lua solution

- an export option for lovejs - if there ends up being official support for it 
  then I might consider it but I want to keep this to platforms that are 
  maintained by the LÖVE Development team

- option to NOT zip up output and make folders instead - this is because you'd
  require 'Run As System Administrator' for running on windows for macos/linux
  exports because windows needs `mklink` for making the symlinks 
  (which we avoid by rezipping as the symlinks are preserved)

- running with window disabled for a 'pure CLI' version, this is possible BUT
  `love-icon` + `love-exedit` both rely on love.graphics for resizing the icons
  so we'd need to recreate the functionality without it as I don't want to force
  devs to have to provide multiple icon sizes
