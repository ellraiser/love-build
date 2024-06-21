-- using love-build to build love-build, nice
return {
  name = 'love-build',
  version = '0.6',
  love = '12.0',
  icon = 'resources/love-hammer.png',
  identifier = 'com.love.build',
  ignore = {
    'dist', 'example-project',
    'love12', 'love12.zip', 'love-macos', -- github workflow
  }
}
