# CliTool

Have trouble with advanced command line options, software dependency presence validation, handling inputs, confirmations and colorizing? Then this gem is for you. It provides you with some modules you can include to add those specific features.

## Installation

Add this line to your application's Gemfile:

    gem 'cli_tool'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install cli_tool

## Usage

**To include the GetoptLong option parser:**

``` ruby
include CliTool::OptionParser
```

You can then define command line arguments using the following class method.

```ruby
class New
  include CliTool::OptionParser

  options {
    :log => :required,
    [:other, :alias] => {
      :dependency => :optional, # Valid values are :none, :optional and :required.
      :short      => :o,        # The short arg this would be '-o'
      :default    => 'default value'
    }
  }
```

These are then returned as GetoptLong array syntax. So to use in GetoptLong:

```ruby
GetoptLong(*New.options).each |option, value|
  puts option
  # => :other
  puts value
  # => 'default value'
end
```

**To include the software dependency module**

```ruby
include CliTool::SoftwareDependencies
```

You can then have you application check that dependencies are accessible in your $PATH on startup by using the following class method.

```ruby
class New
  include CliTool::SoftwareDependencies

  software(:git, :ls, :cp, :mysqld, ...)
end
```

If the executable cannot be found in the $PATH then it will throw `CliTool::MissingDependencies`.

**To include the input, confirm and colorized_puts tool**

```ruby
include CliTool::StdinOut
```

You can then make use of the methods as follows.

```ruby
include CliTool::StdinOut

puts("My normal message", :red)
puts("My normal message", [:red, :purple_bg, :bold])

input("What is your name?", :red)
input("What is your name?", [:red, :purple_bg, :bold])

confirm("Do you really want to do that?", :red)
confirm("Do you really want to do that?", [:red, :purple_bg, :bold])
```

The available options for the methods are.

`puts(message, color = :reset, sleep_in_seconds = nil)`
`input(message, color = :reset, timeout_in_seconds = nil, default_value_for_timeout = nil)`
`confirm(message, color = :reset, default_value = :n, timeout_in_seconds = nil)`

The only required values are message.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
