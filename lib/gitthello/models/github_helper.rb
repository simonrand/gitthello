module Gitthello
  class GithubHelper
    attr_reader :milestone_bucket

    def initialize(oauth_token, repo_for_new_cards, repos_to_consider)
      @github            = Github.new(:oauth_token => oauth_token)
      @user, @repo       = repo_for_new_cards.split(/\//)
      @repos_to_consider = repos_to_consider
    end

    def create_milestone(title, desc, due)
      @github.issues.milestones.
        create( :user => @user, :repo => @repo, :title => title, :description => desc, :due_on => due)
    end

    # TODO
    # def issue_closed?(user, repo, number)
    #   get_issue(user,repo,number).state == "closed"
    # end

    # def close_issue(user, repo, number)
    #   @github.issues.edit(user, repo, number.to_i, :state => "closed")
    # end

    def add_trello_url(milestone, url)
      owner, repo, number = repo_owner(milestone), repo_name(milestone), milestone.number
      description = milestone.description || ""

      unless description =~ /\[Trello Card\]/ or
          description =~ /\[Added by trello\]/
        repeatthis do
          @github.issues.milestones.
            update(owner, repo, number.to_i,
                 :description => description + "\n\n\n[Trello Card](#{url})")
        end
      end
    end

    def retrieve_milestones
      @milestone_bucket = []

      @repos_to_consider.split(/,/).map { |a| a.split(/\//)}.
        each do |repo_owner,repo_name|
          puts "Checking #{repo_owner}/#{repo_name}"
          repeatthis do
            @github.issues.milestones.
              list(:user => repo_owner, :repo => repo_name, :state => "open",
                   :per_page => 100).
              sort_by { |a| a.number.to_i }
          end.each do |milestone|
            (@milestone_bucket) << [repo_name,milestone]
          end
      end

      puts "Found #{@milestone_bucket.count} #{'milestone'.pluralize(@milestone_bucket.count)}"
    end

    def new_milestones_to_trello(trello_helper)
      milestone_bucket.each do |repo_name, milestone|
        # TODO Align dates
        next if trello_helper.has_card?(milestone)

        prefix = repo_name.sub(/^mops./,'').downcase

        card = trello_helper.
          create_todo_card("[%s] %s" % [prefix, milestone["title"]],
                           milestone["description"], milestone["html_url"],
                           milestone["due_on"])
        add_trello_url(milestone, card.url)
      end
    end

    private

    def repo_owner(milestone)
      # assumes the that the url is something like:
      #   https://api.github.com/repos/<repo_owner>/<repo_name>/milestones/<Title>
      milestone["url"].split("/")[-4]
    end

    def repo_name(milestone)
      # assumes the that the url is something like:
      #   https://api.github.com/repos/<repo_owner>/<repo_name>/milestones/<Title>
      milestone["url"].split("/")[-3]
    end

    def repeatthis(cnt=5,&block)
      last_exception = nil
      cnt.times do
        begin
          return yield
        rescue Exception => e
          last_exception = e
          sleep 0.1
          next
        end
      end
      raise last_exception
    end
  end
end
