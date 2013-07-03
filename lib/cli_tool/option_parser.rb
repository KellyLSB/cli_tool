require 'getoptlong'

module CliTool
  module OptionParser

    # Use to add the methods below to any class
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods

      # Map for symbol types
      GOL_MAP = {
        :none     => GetoptLong::NO_ARGUMENT,
        :optional => GetoptLong::OPTIONAL_ARGUMENT,
        :required => GetoptLong::REQUIRED_ARGUMENT
      }

      # Create the options array
      def options(opts = nil)
        @@options ||= []

        # If no options were passed then return
        return @@options.uniq unless opts

        _create_attrs_(opts)
        @@options = @@options.concat(_create_gola_(opts)).uniq
      end

      private

      def _create_attrs_(opts)

        # Get the option keys for attr creation
        keys = opts.keys

        # "symlink" the additional names to the original method
        keys.each do |key|
          default = nil
          key = [key] unless key.is_a?(Array)
          key.each_with_index do |k, i|
            if i < 1
              default = k.to_sym
              attr_accessor(k.to_sym)
            else
              define_method("#{k}=", Proc.new { |x| send(default, x) })
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
            dependency ||= details
          end

          # Prepare the GetoptLong Array option
          golao  = []
          golao << short if short
          golao << GOL_MAP[dependency.to_sym]

          # If the option has aliases then create
          # additional GetoptLong Array options
          if opt.is_a?(Array)
            opt.each do |key|
              golaot = golao.dup
              golaot.unshift(key)
              gola << golaot
            end
          else
            golao.unshift(opt)
            gola << golao
          end
        end

        gola
      end
    end
  end
end
