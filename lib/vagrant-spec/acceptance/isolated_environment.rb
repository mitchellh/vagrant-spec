require "fileutils"
require "pathname"

require "log4r"
require "childprocess"

require "vagrant-spec/isolated_environment"
require "vagrant-spec/subprocess"
require "vagrant-spec/which"

module Vagrant
  module Spec
    # This class extends the normal IsolatedEnvironment to add some
    # additional helpers for executing applications within that environment.
    class AcceptanceIsolatedEnvironment < IsolatedEnvironment
      attr_accessor :env
      
      def initialize(apps: nil, env: nil, skeleton_paths: nil)
        super()

        @logger = Log4r::Logger.new("test::acceptance::isolated_environment")

        @apps = (apps || {}).dup
        @env  = (env || {}).dup
        @skeleton_paths = (skeleton_paths || []).map do |path|
          Pathname.new(path)
        end

        # Set the home directory for any apps we execute
        @env["HOME"] = @homedir.to_s
        @env["VAGRANT_HOME"] = @homedir.to_s

        # Replace some special variables
        @env.each do |k, v|
          @env[k] = @homedir.to_s if v == "{{homedir}}"
        end
      end

      # Executes a command in the context of this isolated environment.
      # Any command executed will therefore see our temporary directory
      # as the home directory.
      #
      # If the command has been defined with a special path, then the
      # command will be replaced with the full path to that command.
      def execute(command, *args, **options)
        # Create the command
        command = replace_command(command)
        command = Which.which(command)

        # Build up the options
        options[:env] = @env
        options[:notify] = [:stdin, :stderr, :stdout]
        options[:workdir] = @workdir.to_s

        # Execute, logging out the stdout/stderr as we get it
        @logger.info("Executing: #{[command].concat(args).inspect}")
        Subprocess.execute(command, *args, **options) do |type, data|
          @logger.debug("#{type}: #{data}") if type == :stdout || type == :stderr
          yield type, data if block_given?
        end
      end

      # Copies the skeleton directory into the working directory.
      #
      # @param [String] name Name of the skeleton to copy.
      def skeleton(name)
        path = @skeleton_paths.find do |p|
          p.join(name).directory?
        end

        if !path
          raise ArgumentError,
            "Skeleton '#{name}' not found in any directory."
        end

        path.join(name).children.each do |c|
          FileUtils.cp_r(c, @workdir.to_s)
        end
      end

      protected

      # This replaces a command with a replacement defined when this
      # isolated environment was initialized. If nothing was defined,
      # then the command itself is returned.
      def replace_command(command)
        return @apps[command] if @apps.has_key?(command)
        return command
      end
    end
  end
end
