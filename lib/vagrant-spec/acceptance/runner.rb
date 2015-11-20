require "set"

require "rspec"

module Vagrant
  module Spec
    module Acceptance
      # The runner configures RSpec to run the given components.
      class Runner
        def initialize(paths: nil)
          @world = RSpec::Core::World.new
          prepare_world!
          @components = Components.new(@world, paths || [])
          prepare_components!
        end

        def components
          @components.components
        end

        def run(components)
          components = Set.new(components || [])

          args = [
            "--color",
            "--format", "Vagrant::Spec::Acceptance::Formatter",
          ]

          with_world do
            # Filter out the components
            if !components.empty?
              bad = []
              @world.example_groups.each do |g|
                next if !g.metadata.has_key?(:component)
                bad << g if !components.include?(g.metadata[:component])
              end

              bad.each do |b|
                puts "Skipping: #{b.metadata[:component]}"
                @world.example_groups.delete(b)
              end
            end

            RSpec::Core::Runner.run(args)
          end
        end

        protected

        def prepare_world!
          with_world do
            require_relative "../acceptance/rspec"
          end
        end

        def prepare_components!
          with_world do
            # Define the provider example group
            Acceptance.config.providers.each do |name, opts|
              @components.provider_features.each do |feature|
                component = "provider/#{name}/#{feature}"

                g = RSpec::Core::ExampleGroup.describe(
                  component, component: component)

                # Include any extra contexts defined
                (opts[:contexts] || []).each do |context|
                  g.include_context(context)
                end

                g.it_should_behave_like("provider/#{feature}", name, opts)
                RSpec.world.register(g)
              end
            end
          end
        end

        def with_world
          # Set the world
          old_world = RSpec.world
          RSpec.world = @world

          yield
        ensure
          RSpec.world = old_world
        end
      end
    end
  end
end
