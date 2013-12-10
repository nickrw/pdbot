Gem::Specification.new do |s|
  s.name = 'pdbot'
  s.version = '1.0.0'
  s.summary = 'PagerDuty Bot'
  s.description = 'PagerDuty Bot'
  s.authors = ['Nicholas Robinson-Wall']
  s.email = ['nick@robinson-wall.com']
  s.required_ruby_version = '>= 1.9.1'
  s.files = Dir['{lib}/**/*']

  s.add_dependency 'cinch', '>= 2.0.5'
  s.add_dependency 'cinchize'
  s.add_dependency 'httparty'
  s.add_dependency 'hashie'
end
