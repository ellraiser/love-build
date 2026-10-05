# 12.0 Source Files
Currently LÖVE 12 is not yet released - as such love-build requires the source zips 
for each platform if you want to build with them.

You will need to put these source files in:
`SAVE_DIR/love-build/cache/`

I try and keep reasonably up to date with latest 12 changes, the builds below are 
from this commit:  
https://github.com/love2d/love/commit/b7daef0f7c1dc5888090f5d5b22d4eaf4ffd1d87  
https://github.com/love2d/love/actions/runs/35517017483  
I have tested love-build with these 12.0 versions on all platforms.

You can get your own builds from any successful workflow action run here:  
https://github.com/love2d/love/actions

I would recommend unzipping and rezipping everything to make sure there's no 
problems due to github artifact zipping - be sure to check the source files here 
for the expected structure of source zips.

If you're having trouble getting the structure right, you can also use the `unzippedsrc` option.  
See the bottom of the `readme.md` for expected structure/files for this unzipped cache format.