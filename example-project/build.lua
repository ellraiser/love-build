return {
  name = 'ExampleGame',
  developer = 'ellraiser',
  output = 'dist',
  version = '1.0.0',
  love = '11.5',
  ignore = {'dist', '.DS_Store'},
  libs = {
    macos = {'resources/plugin.dylib'},
    windows = {'resources/plugin.dll'},
    linux = {'resources/plugin.so'},
    all = {'resources/license.txt'}
  },
  icon = 'resources/icon.png',
  platforms = {'windows', 'macos', 'linux'}
}
