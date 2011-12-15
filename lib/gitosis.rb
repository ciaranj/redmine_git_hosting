require 'lockfile'
require 'inifile'
require 'net/ssh'
require 'tmpdir'

module Gitosis
  def self.renderReadOnlyUrls(baseUrlStr, projectId)
    rendered = ""
    if (baseUrlStr.length == 0)
      return rendered
    end
    
    baseUrlList = baseUrlStr.split("%p")
    if (not defined?(baseUrlList.length))
      return rendered
    end
    
    rendered = rendered + "<strong>Read Only Url:</strong><br />"
    rendered = rendered + "<ul>"
    
    rendered = rendered + "<li>" + baseUrlList[0] + projectId + baseUrlList[1] + "</li>"
    
    rendered = rendered + "</ul>\n"
    
    return rendered
  end
  
	def self.renderUrls(baseUrlStr, projectId, isReadOnly)
		rendered = ""
		if(baseUrlStr.length == 0)
			return rendered
		end
		baseUrlList=baseUrlStr.split(/[\r\n\t ,;]+/)

		if(not defined?(baseUrlList.length))
			return rendered
		end


		rendered = rendered + "<strong>" + (isReadOnly ? "Read Only" : "Developer") + " " + (baseUrlList.length == 1 ? "URL" : "URLs") + ": </strong><br/>"
				rendered = rendered + "<ul>";
				for baseUrl in baseUrlList do
						rendered = rendered + "<li>" + "<span style=\"width: 95%; font-size:10px\">" + baseUrl + projectId + ".git</span></li>"
				end
		rendered = rendered + "</ul>\n"
		return rendered
	end 

	def self.custom_allowed_to?(user, project, action)
		# Becauase User#allowed_to? always returns true for admin users we have
		# to replicate *some* of that logic here :( 
		return false unless project.active?
		# No action allowed on disabled modules
		return false unless project.allows_to?(action)
		
		roles = user.roles_for_project(project)
		return false unless roles
		return roles.detect {|role| (project.is_public? || role.member?) && role.allowed_to?(action)}
	end
	
	def self.update_repositories(projects)
		projects = (projects.is_a?(Array) ? projects : [projects])

		# Don't bother doing anything if none of the projects we've been handed have a Git repository
		unless projects.detect{|p|  p.repository.is_a?(Repository::Git) }.nil?

			lockfile=File.new(File.join(RAILS_ROOT,"tmp",'redmine_gitosis_lock'),File::CREAT|File::RDONLY)
			retries=5
			loop do
				break if lockfile.flock(File::LOCK_EX|File::LOCK_NB)
				retries-=1
				sleep 2
				raise Lockfile::MaxTriesLockError if retries<=0
			end
			begin 

				# HANDLE GIT

				# create tmp dir
				local_dir = File.join(RAILS_ROOT,"tmp","redmine_gitosis_#{Time.now.to_i}")

				Dir.mkdir local_dir

				# clone repo
				`git clone #{Setting.plugin_redmine_gitosis['gitosisUrl']} #{local_dir}/gitosis`

				# write key files
				all_users= User.find(:all)
				all_users.map{|u| u.gitosis_public_keys.active}.flatten.compact.uniq.each do |key|
					File.open(File.join(local_dir, 'gitosis/keydir',"#{key.identifier}.pub"), 'w') {|f| f.write(key.key.gsub(/\n/,'')) }
				end

				# delete inactives
				all_users.map{|u| u.gitosis_public_keys.inactive}.flatten.compact.uniq.each do |key|
					File.unlink(File.join(local_dir, 'gitosis/keydir',"#{key.identifier}.pub")) rescue nil
				end
				
				conf = IniFile.new(File.join(local_dir,'gitosis','gitosis.conf'))
				original = conf.clone
				
				projects.select{|p| p.repository.is_a?(Repository::Git)}.each do |project|
					# fetch users
					users = project.member_principals.map(&:user).compact.uniq
					write_users = users.select do |user|
						# Becauase User#allowed_to? always returns true for admin users we have
						# to replicate *some* of that logic here :( 
						custom_allowed_to?(user, project, :commit_access)
					end
					read_users = users.select do |user|
						custom_allowed_to?(user, project, :view_changesets) && !custom_allowed_to?(user, project, :commit_access)
					end

					name = "#{project.identifier}"

					conf["group #{name}_readonly"]['readonly'] = name
					conf["group #{name}_readonly"]['members'] = read_users.map{|u| u.gitosis_public_keys.active}.flatten.map{ |key| "#{key.identifier}" }.join(' ')

					conf["group #{name}"]['writable'] = name
					conf["group #{name}"]['members'] = write_users.map{|u| u.gitosis_public_keys.active}.flatten.map{ |key| "#{key.identifier}" }.join(' ')

				end
				conf.write 
				git_push_file = File.join(local_dir, 'git_push.bat')

				new_dir= File.join(local_dir,'gitosis')
				new_dir.gsub!(/\//, '\\')
				File.open(git_push_file, "w") do |f|
					f.puts "cd #{new_dir}"
					f.puts "git add -u"
					f.puts "git add keydir/*"
					f.puts "git config user.email '#{Setting.mail_from}'"
					f.puts "git config user.name 'Redmine'"
					f.puts "git commit -m 'updated by Redmine Gitosis'"
					f.puts "git push"
				end
				File.chmod(0755, git_push_file)

				# add, commit, push, and remove local tmp dir
				`#{git_push_file}`
				
				# remove local copy
				`rm -Rf #{local_dir}`
			ensure
				lockfile.flock(File::LOCK_UN)
			end
		end

	end
	
end
