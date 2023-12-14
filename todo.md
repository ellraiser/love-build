# Todo
- add option to specify platforms in `build.lua` for people who want 1 platform
- make the app quit after building when run directly so it closes then opens the output?
- fix `love-squashfs` for repackaging linux
  still keep the 'basic' output for linux, maybe -linux vs -AppImage ZIPs
- add VERSION_INFO modifier for `love-exedit`
- cap `love-exedit` png data so it doesnt mess up exe length
- rename application so that the %appdata% folder is more obvious

# Cleanup
- update `love-zip` to use the `readUInt()` from the other modules
- update `love-icon` + `love-zip` to use love.data.pack instead of intToBytes
- no longer need slash prop in love-build
