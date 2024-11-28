require "log4r"

module VagrantPlugins
  module TerraformProvider
    module Action
      class IsRunning
        def initialize(app, env)
          @app = app
          @logger = Log4r::Logger.new("vagrant_terraform::action::is_created")
        end

        def call(env)
          env[:result] = env[:machine].state.id == :running
          @app.call(env)
        end
      end
    end
  end
end
