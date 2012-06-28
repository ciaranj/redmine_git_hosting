require_dependency 'redmine/scm/adapters/git_adapter'
module GitHosting
	module Patches
		module GitAdapterPatch
			
# raised if scm command exited with error, e.g. unknown revision.
			def self.included(base)
				base.class_eval do
					unloadable
				end
				base.send(:alias_method_chain, :lastrev,   :time_fixed)
				base.send(:alias_method_chain, :revisions, :time_fixed)
				
				begin			
					base.send(:alias_method_chain, :scm_cmd, :ssh)
				rescue Exception =>e
				end
				
				base.extend(ClassMethods)
				base.class_eval do
					class << self
						alias_method_chain :sq_bin, :ssh
						begin
							alias_method_chain :client_command, :ssh
						rescue Exception =>e
						end
					end
				end
			
			end
	


			module ClassMethods
				def sq_bin_with_ssh
					return Redmine::Scm::Adapters::GitAdapter::shell_quote(GitHosting::git_exec())
				end
                                def client_command_with_ssh
            				return GitHosting::git_exec()
                                end
			end

			
			
			def scm_cmd_with_ssh(*args, &block)
				repo_path = root_url || url
				full_args = [GitHosting::git_exec(), '--git-dir', repo_path]
				if self.class.client_version_above?([1, 7, 2])
					full_args << '-c' << 'core.quotepath=false'
					full_args << '-c' << 'log.decorate=no'
				end
				full_args += args
				ret = shellout(full_args.map { |e| shell_quote e.to_s }.join(' '), &block)
				if $? && $?.exitstatus != 0
					raise Redmine::Scm::Adapters::GitAdapter::ScmCommandAborted, "git exited with non-zero status: #{$?.exitstatus}"
				end
				ret
			end


			def lastrev_with_time_fixed(path,rev)
				return nil if path.nil?
				git_bin = Redmine::Scm::Adapters::GitAdapter::sq_bin()
				cmd = "#{git_bin} --git-dir #{target('')} log --pretty=fuller --date=rfc --no-merges -n 1 "
				cmd << " #{shell_quote rev} " if rev 
				cmd <<  "-- #{path} " unless path.empty?
				shellout(cmd) do |io|
					begin
						id = io.gets.split[1]
						author = io.gets.match('Author:\s+(.*)$')[1]
						2.times { io.gets }
						time = io.gets.match('CommitDate:\s+(.*)$')[1]

						Redmine::Scm::Adapters::Revision.new({
							:identifier => id,
							:scmid => id,
							:author => author, 
							:time => Time.rfc2822(time),
							:message => nil, 
							:paths => nil 
						})
					rescue NoMethodError => e
						logger.error("The revision '#{path}' has a wrong format")
						return nil
					end
				end
			end


			def revisions_with_time_fixed(path, identifier_from, identifier_to, options={})
				revisions = Redmine::Scm::Adapters::Revisions.new

				git_bin = Redmine::Scm::Adapters::GitAdapter::sq_bin()
				cmd = "#{git_bin} --git-dir #{target('')} log --raw --date=rfc --pretty=fuller"
				cmd << " --reverse" if options[:reverse]
				cmd << " --all" if options[:all]
				cmd << " -n #{options[:limit]} " if options[:limit]
				cmd << " #{shell_quote(identifier_from + '..')} " if identifier_from
				cmd << " #{shell_quote identifier_to} " if identifier_to
				cmd << " --since=#{shell_quote(options[:since].strftime("%Y-%m-%d %H:%M:%S"))}" if options[:since]
				cmd << " -- #{path}" if path && !path.empty?

				shellout(cmd) do |io|
					files=[]
					changeset = {}
					parsing_descr = 0  #0: not parsing desc or files, 1: parsing desc, 2: parsing files
					revno = 1

					io.each_line do |line|
						if line =~ /^commit ([0-9a-f]{40})$/
							key = "commit"
							value = $1
							if (parsing_descr == 1 || parsing_descr == 2)
								parsing_descr = 0
								revision = Redmine::Scm::Adapters::Revision.new({
									:identifier => changeset[:commit],
									:scmid => changeset[:commit],
									:author => changeset[:author],
									#:time => Time.parse(changeset[:date]),
									:time => Time.rfc2822(changeset[:date]),
									:message => changeset[:description],
									:paths => files
								})
								if block_given?
									yield revision
								else
									revisions << revision
								end
								changeset = {}
								files = []
								revno = revno + 1
							end
							changeset[:commit] = $1
						elsif (parsing_descr == 0) && line =~ /^(\w+):\s*(.*)$/
							key = $1
							value = $2
							if key == "Author"
								changeset[:author] = value
							elsif key == "CommitDate"
								changeset[:date] = value
							end
						elsif (parsing_descr == 0) && line.chomp.to_s == ""
							parsing_descr = 1
							changeset[:description] = ""
						elsif (parsing_descr == 1 || parsing_descr == 2) \
						&& line =~ /^:\d+\s+\d+\s+[0-9a-f.]+\s+[0-9a-f.]+\s+(\w)\s+(.+)$/
							parsing_descr = 2
							fileaction = $1
							filepath = $2
							files << {:action => fileaction, :path => filepath}
						elsif (parsing_descr == 1 || parsing_descr == 2) \
						&& line =~ /^:\d+\s+\d+\s+[0-9a-f.]+\s+[0-9a-f.]+\s+(\w)\d+\s+(\S+)\s+(.+)$/
							parsing_descr = 2
							fileaction = $1
							filepath = $3
							files << {:action => fileaction, :path => filepath}
						elsif (parsing_descr == 1) && line.chomp.to_s == ""
							parsing_descr = 2
						elsif (parsing_descr == 1)
							changeset[:description] << line[4..-1]
						end
					end 

					if changeset[:commit]
						revision = Redmine::Scm::Adapters::Revision.new({
							:identifier => changeset[:commit],
							:scmid => changeset[:commit],
							:author => changeset[:author],
							:time => Time.rfc2822(changeset[:date]),
							:message => changeset[:description],
							:paths => files
						})

						if block_given?
							yield revision
						else
							revisions << revision
						end
					end
				end

				return nil if $? && $?.exitstatus != 0
				revisions
			end
		end
	end
end
