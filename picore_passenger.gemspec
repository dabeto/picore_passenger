# encoding: utf-8

Gem::Specification.new do |gem|

  gem.name        = 'picore_passenger'
  gem.version     = '0.0.2'
  gem.platform    = Gem::Platform::RUBY
  gem.authors     = 'Daniel Rodríguez'
  gem.email       = 'dabeto@gmail.com'
  #gem.homepage    = 'https://github.com/meskyanichi/mongoid-paperclip'
  gem.summary     = 'Picore Passenger Model'
  gem.description = 'Picore Passenger Model'

  gem.files         = %x[git ls-files].split("\n")
	#gem.files         = 'lib/mongoidbi.rb'
  #gem.files = Dir['Rakefile', '{bin,lib,man,test,spec}/**/*', 'README*', 'LICENSE*'] & `git ls-files -z`.split("\0")
  gem.test_files    = %x[git ls-files -- {spec}/*].split("\n")
  gem.require_path  = 'lib'
  gem.add_dependency 'mongoid'
  gem.add_dependency 'mongoid-paperclip'
  gem.add_dependency 'simple_enum', '~> 2.0'

end
