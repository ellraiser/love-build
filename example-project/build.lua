return {
  name = 'ExampleGame',
  developer = 'ellraiser',
  output = 'dist',
  version = '1.0.0',
  love = '11.5',
  ignore = {'dist', '.DS_Store', 'postprocess.sh', 'preprocess.sh'},
  libs = {
    macos = {'resources/macos/https.so'},
    windows = {'resources/windows/https.dll'},
    linux = {'resources/linux/https.so'},
    all = {'resources/license.txt'}
  },
  hooks = {
    before_build = 'resources/preprocess.sh',
    after_build = 'resources/postprocess.sh'
  },
  icon = 'resources/icon.png',
  platforms = {'windows', 'macos', 'linux'}
}
