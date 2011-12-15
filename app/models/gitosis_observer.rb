class GitosisObserver < ActiveRecord::Observer
  unloadable
  observe :project, :user, :gitosis_public_key, Member, Role, :repository
  
  def after_save(object) ; update_repositories(object) ; end
  def after_destroy(object) ; update_repositories(object) ; end
  
  protected
  
  def update_repositories(object)
    case object
      when Repository then projects_need_update(object.project)
      when User then projects_need_update(object.projects) unless is_login_save?(object)
      when GitosisPublicKey then projects_need_update(object.user.projects)
      when Member then projects_need_update(object.project)
      when Role then projects_need_update(object.members.map(&:project).uniq.compact)
    end
  end
  
  private
  
  # Mark project(s) as requiring a gitosis-admin update.
  def projects_need_update(projects)
	Thread.current[:gitosis_project_updates] << projects
	Thread.current[:gitosis_project_updates].flatten!
	Thread.current[:gitosis_project_updates].uniq!
	Thread.current[:gitosis_project_updates].compact!
  end

  # Test for the fingerprint of changes to the user model when the User actually logs in.
  def is_login_save?(user)
    user.changed? && user.changed.length == 2 && user.changed.include?("updated_on") && user.changed.include?("last_login_on")
  end
end
