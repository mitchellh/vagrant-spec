require "net/http"

require "vagrant-spec/server"
require "vagrant-spec/acceptance/isolated_environment"

shared_context "acceptance" do
  include Vagrant::Spec::Server

  # Setup the environment so that we have an isolated area
  # to run Vagrant. We do some configuration here as well in order
  # to replace "vagrant" with the proper path to Vagrant as well
  # as tell the isolated environment about custom environmental
  # variables to pass in.
  let!(:environment) { new_environment }

  let(:config) { Vagrant::Spec::Acceptance.config }

  let(:extra_env) { {} }

  # The skeleton paths that will be used to configure environments.
  let(:skeleton_paths) do
    root = Vagrant::Spec.source_root.join("acceptance", "support-skeletons")
    config.skeleton_paths.dup.unshift(root)
  end

  after(:each) do
    environment.close
  end

  # Creates a new isolated environment instance each time it is called.
  #
  # @return [Acceptance::IsolatedEnvironment]
  def new_environment(env=nil)
    apps = { "vagrant" => config.vagrant_path }
    env  = config.env.merge(env || {})
    env.merge!(extra_env)

    Vagrant::Spec::AcceptanceIsolatedEnvironment.new(
      apps: apps,
      env: env,
      skeleton_paths: skeleton_paths,
    )
  end

  # Executes the given command in the context of the isolated environment.
  #
  # @return [Object]
  def execute(*args, env: nil, log: config.log_execute, &block)
    env ||= environment
    status("Execute: #{args.join(" ")}") if log
    env.execute(*args, &block)
  end

  # This method is an assertion helper for asserting that a process
  # succeeds. It is a wrapper around `execute` that asserts that the
  # exit status was successful.
  def assert_execute(*args, env: nil, &block)
    result = execute(*args, env: env, &block)
    expect(result).to exit_with(0)
    result
  end

  # Tests that the host can access the VM through the network.
  #
  # @param [String] url URL to request from the host.
  # @param [Integer] guest_port Port to run a web server on the guest.
  def assert_network(url, guest_port)
    # Start up a web server in another thread by SSHing into the VM.
    thr = Thread.new do
      assert_execute("vagrant", "ssh", "-c", "python -m SimpleHTTPServer #{guest_port}")
    end

    # Verify that port forwarding works by making a simple HTTP request
    # to the port. We should get a 200 response. We retry this a few times
    # as we wait for the HTTP server to come online.
    tries = 0
    begin
      result = Net::HTTP.get_response(URI.parse(url))
      expect(result.code).to eql("200")
    rescue
      if tries < config.assert_retries
        tries += 1
        sleep 2
        retry
      end

      raise
    end
  ensure
    thr.kill if thr
  end

  def status(message)
    RSpec.world.reporter.message(message)
  end
end
