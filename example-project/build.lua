return {
  name = 'ExampleGame',
  developer = 'ellraiser',
  output = 'dist',
  version = '1.0.0',
  love = '11.5',
  ignore = {'dist', '.DS_Store'},
  libs = {
    macos = {'resources/macos/https.so'},
    windows = {'resources/windows/https.dll'},
    linux = {'resources/linux/https.so'},
    all = {'resources/license.txt'}
  },
  icon = 'resources/icon.png',
  platforms = {'windows', 'macos', 'linux'}
}
