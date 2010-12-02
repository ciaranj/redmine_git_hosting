class GitosisObserver < ActiveRecord::Observer
  observe :project, :user, :gitosis_public_key, :member, :role, :repository
  
  
#  def before_create(object)
#    if object.is_a?(Project)
#      repo = Repository::Git.new
#      repo.url = repo.root_url = File.join(Gitosis::GITOSIS_BASE_PATH,"#{object.identifier}.git")
#      object.repository = repo
#    end
#  end
  
  def after_save(object) ; update_repositories(object) ; end
  def after_destroy(object) ; update_repositories(object) ; end
  
  protected
  
  def update_repositories(object)
    case object
      when Project then projects_need_update(object)
      when Repository then projects_need_update(object.project)
      when User then projects_need_update(object.projects)
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
end
