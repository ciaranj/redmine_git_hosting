require 'redmine'
require_dependency 'principal'
require_dependency 'user'
require_dependency 'member'

require_dependency 'git_hosting'
require 'git_hosting/patches/application_controller_patch'
require 'git_hosting/patches/repositories_controller_patch'
require 'git_hosting/patches/repositories_helper_patch'
require 'git_hosting/patches/git_adapter_patch'
require 'git_hosting/patches/projects_controller_patch' 

Dispatcher.to_prepare do
  GitHostingObserver.instance

  require 'repositories_controller'
  require 'projects_controller'
  ApplicationController.send(:include, GitHosting::Patches::ApplicationControllerPatch) unless ApplicationController.included_modules.include?(GitHosting::Patches::ApplicationControllerPatch)
  RepositoriesController.send(:include, GitHosting::Patches::RepositoriesControllerPatch) unless RepositoriesController.include?(GitHosting::Patches::RepositoriesControllerPatch)
  RepositoriesController.send(:include, GitHosting::Patches::ApplicationControllerPatch) unless RepositoriesController.included_modules.include?(GitHosting::Patches::ApplicationControllerPatch)
  RepositoriesHelper.send(:include, GitHosting::Patches::RepositoriesHelperPatch) unless RepositoriesHelper.include?(GitHosting::Patches::RepositoriesHelperPatch)
  Redmine::Scm::Adapters::GitAdapter.send(:include, GitHosting::Patches::GitAdapterPatch) unless Redmine::Scm::Adapters::GitAdapter.include?(GitHosting::Patches::GitAdapterPatch)
  ProjectsController.send(:include, GitHosting::Patches::ProjectsControllerPatch) unless ProjectsController.include?(GitHosting::Patches::ProjectsControllerPatch)

  # initialize association from user -> public keys
  User.send(:has_many, :gitolite_public_keys, :dependent => :destroy)

  # initialize observer
  ActiveRecord::Base.observers = ActiveRecord::Base.observers << GitHostingObserver
end

Redmine::Plugin.register :redmine_git_hosting do
	name 'Redmine Git Hosting Plugin'
	author 'Eric Bishop, Christian Käser, Zsolt Parragi, Yunsang Choi, Joshua Hogendorn, Jan Schulz-Hofen and others'
	description 'Enables Redmine to control hosting of git repositories'
	version '0.1.0'
	settings :default => {
		'allProjectsUseGit' => 'false',
		'gitServer' => 'localhost',
		'httpServer' => 'localhost',
		'gitUser' => 'git',
		'gitUserIdentityFile'  => RAILS_ROOT + '/.ssh/git_user_id_rsa',
		'gitoliteIdentityFile' => RAILS_ROOT + '/.ssh/gitolite_admin_id_rsa',
		'gitRepositoryBasePath' => 'repositories/',
		'deleteGitRepositories' => 'false'
		}, 
		:partial => 'redmine_git_hosting'
end

# initialize hooks
class GitProjectShowHook < Redmine::Hook::ViewListener
	render_on :view_projects_show_left, :partial => 'git_urls'
end

class GitRepoUrlHook < Redmine::Hook::ViewListener
	render_on :view_repositories_show_contextual, :partial => 'git_urls'
end
