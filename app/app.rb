require 'api/control'
require 'api/dj'
require 'api/helpers'
require 'api/library'
require 'api/queue'
require 'api/system'
require 'api/speaker'

module Play
  class App < Sinatra::Base

    # Include our Sinatra Helpers.
    include Play::Helpers

    # Set up sessions and ensure we have a constant session_secret so that in
    # development mode `shotgun` won't regenerate a session secret and
    # invalidate all of our sessions.
    enable :sessions
    set    :session_secret, Play.config.auth_token

    register Mustache::Sinatra
    register Sinatra::Auth::Github

    dir = File.dirname(File.expand_path(__FILE__))

    class Octobouncer < Sinatra::Base
      # Handle bad authenication, clears the session and redirects to login.
      get '/unauthenticated' do
        if session[:user].nil?
          redirect '/'
        else
          session.clear
          redirect '/403.html'
        end
      end
    end

    set :github_options, {
                            :secret    => Play.config.secret,
                            :client_id => Play.config.client_id,
                            :failure_app => Octobouncer,
                            :organization => Play.config.gh_org,
                            :scopes => 'user,offline_access'
                         }

    Pusher.app_id =  Play.config.pusher_app_id
    Pusher.key = Play.config.pusher_key
    Pusher.secret = Play.config.pusher_secret

    Airfoil.enabled = Airfoil.installed?
    Airfoil.audio_source = "System Audio" if Airfoil.installed?

    set :public_folder, "#{dir}/frontend/public"
    set :static, true
    set :mustache, {
      :namespace => Play,
      :templates => "#{dir}/templates",
      :views => "#{dir}/views"
    }

    before do
      return if ENV['RACK_ENV'] == 'test'

      content_type :json

      session_not_required = request.path_info =~ /\/login/ ||
                             request.path_info =~ /\/auth/ ||
                             request.path_info =~ /\/images\/art\/.*.png/

      if session_not_required || @current_user
        true
      else
        login
      end
    end

    def api_request
      !!params[:token] || !!request.env["HTTP_AUTHORIZATION"]
    end

    def login
      if api_request
        token = request.env["HTTP_AUTHORIZATION"] || params[:token] || ""
        login = request.env["HTTP_X_PLAY_LOGIN"] || params[:login] || ""

        if token == Play.config.auth_token
          user = User.find(login)
        else
          user = User.find_by_token(token)
        end

      else
        if Play.config.gh_org && Play.config.gh_org != ''
          github_organization_authenticate!(Play.config.gh_org)
        else
          authenticate!
        end

        user   = User.find(github_user.login)
        user ||= User.create(github_user.login,github_user.email)
      end

      halt 401 if !user

      @current_user = session[:user] = user
    end

    def current_user
      @current_user
    end

    get "/" do
      content_type :html
      mustache :index
    end

    get "/logout" do
      content_type :html
      logout!
      redirect 'https://github.com'
    end

    get "/token" do
      @back_to = params[:back_to]

      content_type :html
      mustache :token, :layout => false
    end
  end
end