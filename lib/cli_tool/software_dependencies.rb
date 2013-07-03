module CliTool
  class MissingDependencies < StandardError; end;

  module SoftwareDependencies

    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods

      # Create the options array
      def software(*soft)
        @@software ||= []

        # If no software dependencies were passed then return
        return @@software.uniq unless soft

        # Find missing software
        missing = []
        soft.each do |app|
          %x{which #{app}}
          missing << app unless $?.success?
        end

        # Raise if there were any missing software's
        unless missing.empty?
          missing = missing.join(', ')
          raise CliTool::MissingDependencies,
            %{The required software packages "#{missing}" could not be found in your $PATH.}
        end

        # Append to the software list
        @@software = @@software.concat(soft).uniq
      end
    end
  end
end
