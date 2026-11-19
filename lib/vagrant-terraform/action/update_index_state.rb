require "log4r"

module VagrantPlugins
  module TerraformProvider
    module Action
      # Wraps a state-changing action chain and, once it has finished,
      # refreshes this machine's entry in Vagrant's global machine index
      # (what `vagrant global-status` displays).
      #
      # Vagrant core only writes the index entry's state in two places:
      # Machine#id= (sets it to "preparing" when the machine is first
      # created) and Machine#state (sets it to the provider's current short
      # state). Our up/halt chains read state via the ReadState middleware
      # directly, never via Machine#state, so without this a freshly created
      # VM stays "preparing" and a halted one stays "running" in
      # global-status until someone happens to run `vagrant status`.
      class UpdateIndexState
        def initialize(app, env)
          @app    = app
          @logger = Log4r::Logger.new("vagrant_terraform::action::update_index_state")
        end

        def call(env)
          @app.call(env)

          # No id means the machine isn't (or is no longer) registered in
          # the index; Machine#state would have nothing to update.
          return if env[:machine].id.nil?

          begin
            env[:machine].state
          rescue => e
            # Purely bookkeeping: don't fail an otherwise successful action.
            @logger.warn("failed to refresh machine index state: #{e.class}: #{e.message}")
          end
        end
      end
    end
  end
end
