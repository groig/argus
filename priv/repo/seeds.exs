alias Argus.Accounts
alias Argus.Accounts.User
alias Argus.Projects
alias Argus.Projects.Project
alias Argus.Repo
alias Argus.Teams
alias Argus.Teams.Team

import Ecto.Query

admin_email = "admin@argus.local"
admin_password = "changeme123"

admin =
  case Repo.get_by(User, email: admin_email) do
    nil ->
      {:ok, user} =
        Accounts.create_user(%{
          email: admin_email,
          name: "Argus Admin",
          role: :admin,
          password: admin_password,
          password_confirmation: admin_password,
          confirmed: true
        })

      user

    %User{} = user ->
      user =
        user
        |> User.profile_changeset(%{email: admin_email, name: "Argus Admin"},
          validate_unique: false
        )
        |> Ecto.Changeset.change(
          role: :admin,
          confirmed_at: user.confirmed_at || DateTime.utc_now(:second)
        )
        |> Repo.update!()

      if Accounts.get_user_by_email_and_password(admin_email, admin_password) do
        user
      else
        {:ok, {user, _expired_tokens}} =
          Accounts.update_user_password(user, %{
            password: admin_password,
            password_confirmation: admin_password
          })

        user
      end
  end

team =
  case Repo.get_by(Team, name: "Engineering") do
    nil ->
      {:ok, team} = Teams.create_team(%{name: "Engineering"})
      team

    %Team{} = team ->
      team
  end

{:ok, _membership} = Teams.add_member(team, admin, :admin)

project =
  case Repo.one(
         from project in Project,
           where: project.team_id == ^team.id and project.name == "My First Project"
       ) do
    nil ->
      {:ok, project} = Projects.create_project(team, %{name: "My First Project"})
      project

    %Project{} = project ->
      project
  end

IO.puts("Seeded project DSN key: #{project.dsn_key}")
