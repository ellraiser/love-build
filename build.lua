-- using love-build to build love-build, nice
return {
  name = 'love-build',
  version = '0.2',
  love = '12.0',
  icon = 'resources/love-hammer.png',
  identifier = 'com.love.build',
  ignore = {
    'dist', 'example-project', '.DS_Store',
    '.git', '.gitattributes', 'gitignore'
  }
}
