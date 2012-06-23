require_dependency 'application_controller'
module GitHosting
  module Patches
    module ApplicationControllerPatch
	  def self.included(base)
        base.class_eval do
          unloadable
        end
        base.send(:prepend_around_filter, :handle_githosting_project_updates)
      end
	  private
		def handle_githosting_project_updates
			Thread.current[:githosting_project_updates]= []

			yield # Continue the filter chain.

			if Thread.current[:githosting_project_updates].length > 0
				logger.info("Action needs to update Gitosis repositories")
				#todo: we've lost the delete_repos flag here..
				GitHosting::update_repositories(Thread.current[:githosting_project_updates],false)
			end
		end
    end
  end
end
