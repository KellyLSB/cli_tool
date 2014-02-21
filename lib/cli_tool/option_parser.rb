require 'getoptlong'

module CliTool
  module OptionParser

    # Use to add the methods below to any class
    def self.included(base)
      base.extend(ClassMethods)
      base.options({
        dependency: :none,
        short: :h
      })
    end

    module ClassMethods

      # Map for symbol types
      GOL_MAP = {
        none: GetoptLong::NO_ARGUMENT,
        optional: GetoptLong::OPTIONAL_ARGUMENT,
        required: GetoptLong::REQUIRED_ARGUMENT
      }

      # Create the options array
      def options(opts = nil)
        @@options ||= []

        # If no options were passed then return
        return @@options.uniq unless opts

        _create_preprocess(opts)
        _create_help_(opts)
        _create_attrs_(opts)
        default_options(opts)
        @@options = @@options.concat(_create_gola_(opts)).uniq
      end

      def default_options(opts = {})
        @@defaults ||= []

        # If no options were passed then return
        return @@defaults.uniq.inject({}) { |o,(k,v)| o[k] = v; o } unless opts

        # Set the default options
        opts.each do |opt, details|
          next unless details.is_a?(Hash)
          next unless details[:default]
          opt = opt.first if opt.is_a?(Array)
          @@defaults << [optionify(opt), details[:default]]
        end

        @@defaults = @@defaults.uniq
      end

      # Parse to correct option set
      def optionify(option, setter = false)
        option = "#{option}".gsub(/^[\-]+/, '').gsub(/(-| )/, '_')
        (setter ? option + '=' : option).to_sym
      end

      # Handle running options
      def run(entrypoint = false, *args, &block)
        if args.last.instance_of?(self)
          obj = args.pop
        else
          obj = self < Singleton ? instance : new
        end

        # Option Setter Proc
        option_setter = Proc.new do |option, value|
          value = case value
          when ''
            true
          when 'true'
            true
          when 'false'
            false
          else
            value
          end

          # Run any preprocessors on the data before assignment
          preprocessor =  @@preprocessors[optionify(option)]
          if preprocessor
            value = obj.__send__(:instance_exec, value, &preprocessor)
          end

          # Show notice of the setting being accepted
          if @@__secure_options.include?(optionify(option))
            puts "Securely Setting @#{optionify(option)} = #{'*' * value.length}"
          else
            peuts "Setting @#{optionify(option)} = #{value}"
          end

          # Do the actual set for us
          obj.__send__(optionify(option, :set), value)
        end

        # Set options
        puts "CliTool... Loading Options..."
        default_options.each(&option_setter)
        GetoptLong.new(*options).each(&option_setter)
        puts ''

        if obj.help
          puts help
          exit
        end

        # Handle the entrypoint
        if entrypoint
          entrypoint = optionify(entrypoint)
          obj.__send__(entrypoint, *args, &block)
        else
          obj
        end
      end

      def help(message = nil)
        if message.nil?
          help_text = @@help_options.map do |option|
            case options[:dependency]
            when :required
              long_dep = "=<#{options[:default] || 'value'}>"
              short_dep = " <#{options[:default] || 'value'}>"
            when :optional
              long_dep = "=[#{options[:default] || 'value'}]"
              short_dep = " [#{options[:default] || 'value'}]"
            when :none
              long_dep = ''
              short_dep = ''
            end

            message = options[:keys].map{ |x| "--#{x}#{long_dep}"}.join(', ')
            message << ", -#{options[:short]}#{short_dep}" if option[:short]
            message << %{ :: Default: "#{options[:default]}"} if options[:default]
            message << %{\n\t#{options[:documentation]}} if options[:documentation]
            message << "\n"
          end

          <<-HELP
          #{$0}

          #{help_text.join("\n")}

          #{@@help_message || "No additional documentation"}
          HELP
        else
          @@help_message = message
        end
      end

      private

      def _create_preprocess_(opts)
        @@preprocessors = opts.reduce({}) do |out, (keys, other)|
          keys.reduce(out) do |o, key|
            o.merge(key => other[:preprocess])
          end
        end
      end

      def _create_help_(opts)
        @@help_options = opts.reduce([]) do |out, (keys, other)|
          out << other.merge(keys: [keys].flatten.compact)
        end
      end

      def _create_attrs_(opts)

        # Create secure options (don't shwow assignment in terminal)
        @@__secure_options = opts.reduce([]) do |out, (keys, other)|
          other[:secure] == true ? (out << keys).flatten.compact.uniq : out
        end

        # Get the option keys for attr creation
        keys = opts.keys

        # "symlink" the additional names to the original method
        keys.each do |key|
          default = nil
          key = [key] unless key.is_a?(Array)
          key.each_with_index do |k, i|
            if i < 1
              default = optionify(k)
              attr_accessor(default)
            else
              define_method(optionify(k, :set), Proc.new { |x| send("#{default}=", x) })
            end
          end
        end
      end

      def _create_gola_(opts)
        gola = []

        # Loop through the options to create
        # the GetoptLong configuration array
        opts.each do |opt, details|

          short = nil
          dependency = :none

          # If we have extended details determine them
          if details.is_a?(Hash)
            short = details[:short]
            dependency = details[:dependency]
          else
            dependency = details
          end

          # Prepare the GetoptLong Array option
          golao  = []
          golao << "-#{short}" if short
          golao << GOL_MAP[dependency.to_sym]

          # If the option has aliases then create
          # additional GetoptLong Array options
          if opt.is_a?(Array)
            opt.each do |key|
              golaot = golao.dup
              golaot.unshift("--#{key}")
              gola << golaot
            end
          else
            golao.unshift("--#{opt}")
            gola << golao
          end
        end

        gola
      end
    end
  end
end
