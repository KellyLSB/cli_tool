# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'cli_tool/version'

Gem::Specification.new do |spec|
  spec.name          = "cli_tool"
  spec.version       = CliTool::VERSION
  spec.authors       = ["Kelly Becker"]
  spec.email         = ["kellylsbkr@gmail.com"]
  spec.description   = %q{Have trouble with advanced command line options, software dependency presence validation, handling inputs, confirmations and colorizing? Then this gem is for you. It provides you with some modules you can include to add those specific features.}
  spec.summary       = %q{Tools to help with writing command line applications}
  spec.homepage      = "http://kellybecker.me"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
  spec.add_dependency "awesome_print"
  spec.add_dependency "pry"
end
