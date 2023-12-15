# löve-build
An app for quickly packaging LÖVE games for distribution, based off the most recent comments in [this issue](https://github.com/love2d/love/issues/890).

The goal is to make something eventually maintained by the LÖVE team that can let new developers build their games cross-platform from their own machine in a single step - with zero dependencies and no need for VMs.

*This app will build + export your game for LÖVE (.love), Windows (.exe), MacOS (.app), and Linux (.zip)!*

![alt text](resources/preview.png)


---


## Usage
First you will need to setup a `build.lua` file in the root of your project:
```lua
return {
  
  -- basic settings:
  name = 'SuperGame', -- name of the game for your executable
  developer = 'CoolDev', -- dev name used in metadata of the file
  output = 'dist', -- output location for your game, defaults to $SAVE_DIRECTORY
  version = '1.1a', -- 'version' of your game, used to make a version folder in output
  love = '11.5', -- version of LÖVE to use, must match github releases
  ignore = {'dist', '.DS_Store'}, -- folders/files to ignore in your project
  icon = 'resources/icon.png', -- 256x256px PNG icon for game, will be converted for you
  
  -- optional settings:
  use32bit = false, -- set true to build windows 32-bit as well as 64-bit
  identifier = 'com.love.supergame', -- macos team identifier, defaults to game.developer.name
  libs = {'resources/plugin.dll'} -- files to place in output directly rather than fuse
  platforms = {'windows'} -- set if you only want to build for a specific platform
  
}
```

Then download the build application for your OS from the [releases](https://github.com/ellraiser/love-build/releases) page.

To use the app directly, simply run it. You will see a screen prompting you to drag your `main.lua` file into the app - doing so will start the build process and export your game, opening the export location when finished. A `build.log` file will also be created to view any errors (see [Troubleshooting](#troubleshooting) for common issues).

You can view the `example-project` in this repository for an example setup/config.

> Note: First time builds will be slower due to downloading and caching LÖVE source files - after that it'll be much faster!


---


## Command Line
If you want to run via CLI, the application accepts an argument which is the full path to your `main.lua` file:

Windows => `build.exe FULL/PATH/TO/main.lua`  
MacOS => `build/Contents/MacOS/love FULL/PATH/TO/main.lua`  
Linux => `build.AppImage FULL/PATH/TO/main.lua`

You can also pass a second option to specify the target platforms you want - by default all platforms are specified (`windows,macos,linux`), but if you want to only build for one specific platform you can do so like:  
`build.exe FULL/PATH/TO/main.lua windows`


---


## Cross-Platform Building
Regardless of the platform you run the builder from it will export your game to all 3 platforms.  
These will each be put in their own `.zip` file inside the `output/version` folder specified by your `build.lua`.

| Build From  | Windows | MacOS | Linux |
| ----------- | ------- | ----- | ----- |
| Windows     |    ✓    |   ✓   |   ✓^  |
| MacOS       |    ✓    |   ✓   |   ✓^  |
| Linux       |    ✓    |   ✓   |   ✓^  |

^ Linux builds are currently a 'basic' export, not an AppImage - chmod+run the `AppRun` file to run

> Note: MacOS builds are _not_ signed so are not suitable for AppStore distribution


---


## Troubleshooting
These are the common errors you might see when building.  
You can view the logs inside `output/version/build.log` after running the builder.

| Error                                                           | Info                                                       |
| --------------------------------------------------------------- | ---------------------------------------------------------- |
| Failed to mount project path                                    | The project path isn't readable by the executable
| Failed to mount output path                                     | The output path isn't read/writeable by the executable
| No build.lua file in project root                               | The path given doesn't have a build.lua
| Invalid build.lua file in project root                          | The build.lua in the project doesn't return a valid table
| No main.lua file in project root                                | The path you provided doesn't have a main.lua
| Path must be to your game\'s "main.lua" file                    | The path given doesn't lead to a main.lua file
| Failed to create .lovefile                                      | Failed to create lovefile, check logs for info
| Source download failed                                          | Failed to download release from github
| Source file must be supplied to build this version              | Specificed version doesn't have a release on github

> Note: If you want to build with 12.0 you'll need to provide the source zips yourself in the `%appdata%/love-build/cache` directory, you can download the builds from the [latest successful 12.0-dev action](https://github.com/love2d/love/actions/workflows/main.yml?query=branch%3A12.0-development)


---


## Todo
**.AppImages for Linux export**  
Currently the `love-squashfs` lib handles decompressing squashfs binaries fine, however resquashing them has an issue I'm working on. At the moment the Linux export just uses the same AppImage directory format with a `AppRun` entrypoint and fused binary, which will work fine for most distros so no harm there.
 
Once the lib issues are fixed we'll be able to export as a proper `.AppImage`, but I think we should still keep the `-linux.zip` output as an option for people who want it, similar to the additional 32bit option windows has.

---


**Windows.exe metadata**  
The current `love-exedit` module is very basic and only lets you modify ICON resources at the moment. I've made some work on parsing the VERSION_INFO to change the name/description, but it still needs finishing off and writing the changes before all the metadata stuff is finished.


---


**Distributing lovebuild as .love file**  
We *could* make the builder more portable and distribute as a `.love` - this would make it a smaller file to download BUT it'd mean we'd be using whatever version of LÖVE the developer has locally, if they're using 11.X (or older) a bunch of things will fail as `love-build` itself was built with 12.0 and uses some of the newer methods internally.

The main issues we would have are replacing `mountFullPath` (would need to be replaced with terminal commands), and the `https` module. We only use http.request for downloading the source initially, however as it's an SSL endpoint (github releases), we would need `lua-https` - we can't just use luasocket. However `lua-https` has not been built for MacOSX ARM64 yet so we wouldn't have complete support but this would be the best option if someone can build it for the project.

I think even then, distributing as a `.love` file that works with 11.X we would still have issues with older builds and I think it's more consistent to offer a pre-built application and not have to worry about what a dev might have locally


---


See [todo.md](todo.md) for stuff planned in future
