require 'redmine'
require_dependency 'principal'
require_dependency 'user'
require_dependency 'member'

require_dependency 'gitosis'
require 'gitosis/patches/application_controller_patch'
require 'gitosis/patches/repositories_controller_patch'
require 'gitosis/patches/repositories_helper_patch'
require 'gitosis/patches/git_adapter_patch'

Dispatcher.to_prepare do
  GitosisObserver.instance

  ApplicationController.send(:include, Gitosis::Patches::ApplicationControllerPatch) unless ApplicationController.included_modules.include? Gitosis::Patches::ApplicationControllerPatch
  RepositoriesController.send(:include, Gitosis::Patches::RepositoriesControllerPatch) unless RepositoriesController.include?(Gitosis::Patches::RepositoriesControllerPatch)
  RepositoriesHelper.send(:include, Gitosis::Patches::RepositoriesHelperPatch) unless RepositoriesHelper.include?(Gitosis::Patches::RepositoriesHelperPatch)
  Redmine::Scm::Adapters::GitAdapter.send(:include, Gitosis::Patches::GitAdapterPatch) unless Redmine::Scm::Adapters::GitAdapter.include?(Gitosis::Patches::GitAdapterPatch)

  # initialize association from user -> public keys
  User.send(:has_many, :gitosis_public_keys, :dependent => :destroy)

  # initialize observer
  ActiveRecord::Base.observers = ActiveRecord::Base.observers << GitosisObserver
end
Redmine::Plugin.register :redmine_gitosis do
  name 'Redmine Gitosis plugin'
  author 'Jan Schulz-Hofen'
  description 'Enables Redmine to update a gitosis server.'
  version '0.0.5alpha'
  settings :default => {
    'gitosisUrl' => 'git@localhost:gitosis-admin.git',
    'gitosisIdentityFile' => '/srv/projects/redmine/miner/.ssh/id_rsa',
    'developerBaseUrls' => 'git@www.salamander-linux.com:,https://[user]@www.salamander-linux.com/git/',
    'readOnlyBaseUrls' => 'http://www.salamander-linux.com/git/',
    'basePath' => '/srv/projects/git/repositories/',
    }, 
    :partial => 'redmine_gitosis'
end

# initialize hook
class GitosisPublicKeyHook < Redmine::Hook::ViewListener
  render_on :view_my_account_contextual, :inline => "| <%= link_to(l(:label_public_keys), public_keys_path) %>" 
end

class GitosisProjectShowHook < Redmine::Hook::ViewListener
  render_on :view_projects_show_left, :partial => 'redmine_gitosis'
end
