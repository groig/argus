defmodule ArgusWeb.Router do
  use ArgusWeb, :router

  import ArgusWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ArgusWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :agent_api do
    plug ArgusWeb.Plugs.ApiAuth
  end

  scope "/", ArgusWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/users/register", PageController, :not_found

    live_session :public, on_mount: [{ArgusWeb.UserAuth, :mount_current_scope}] do
      live "/login", UserLive.Login, :new
      live "/invitations/:token", UserLive.Invitation, :show
    end

    post "/login", UserSessionController, :create
    delete "/logout", UserSessionController, :delete
    post "/invitations/:token", InvitationController, :accept
  end

  scope "/", ArgusWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :authenticated,
      on_mount: [{ArgusWeb.UserAuth, :require_authenticated}] do
      live "/projects", ProjectLive.Index, :index
      live "/projects/:slug/issues", IssuesLive.Index, :index
      live "/projects/:slug/issues/:id", IssuesLive.Show, :show
      live "/projects/:slug/logs", LogsLive.Index, :index
      live "/projects/:slug/logs/:id", LogsLive.Show, :show
      live "/projects/:slug/metrics", MetricsLive.Index, :index
      live "/projects/:slug/settings", ProjectLive.Settings, :show
      live "/teams/:id/settings", TeamLive.Settings, :show
      live "/settings", UserLive.Settings, :edit
      live "/admin", AdminLive.Index, :index
    end

    post "/settings/password", UserSessionController, :update_password
  end

  scope "/api", ArgusWeb do
    pipe_through :api

    options "/:project_id/store/", IngestController, :options
    options "/:project_id/envelope/", IngestController, :options
    post "/:project_id/store/", IngestController, :store
    post "/:project_id/envelope/", IngestController, :envelope
  end

  # Markdown API for agents, authenticated with personal API tokens.
  scope "/api/v1", ArgusWeb do
    pipe_through :agent_api

    get "/", AgentController, :index
    get "/projects", AgentController, :projects
    get "/projects/:slug/issues", AgentController, :issues
    get "/projects/:slug/issues/:id", AgentController, :issue
    post "/projects/:slug/issues/:id/resolve", AgentController, :resolve
    get "/projects/:slug/issues/:id/occurrences", AgentController, :occurrences
    get "/projects/:slug/issues/:id/occurrences/:occurrence_id", AgentController, :occurrence
  end

  if Application.compile_env(:argus, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ArgusWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
