defmodule Argus.TeamsTest do
  use Argus.DataCase, async: true

  import Argus.AccountsFixtures
  import Argus.WorkspaceFixtures

  alias Argus.Teams
  alias Argus.Teams.Team

  describe "add_member/3" do
    test "returns a changeset error instead of raising when the team is gone" do
      team = team_fixture()
      {:ok, _} = Repo.delete(team)

      assert {:error, changeset} = Teams.add_member(team, user_fixture())
      assert %{team_id: ["does not exist"]} = errors_on(changeset)
    end
  end

  describe "get_team/1" do
    test "accepts integer and string ids and returns nil for anything else" do
      team = team_fixture()

      assert %Team{} = Teams.get_team(team.id)
      assert %Team{} = Teams.get_team(Integer.to_string(team.id))
      assert Teams.get_team("not-an-id") == nil
      assert Teams.get_team(nil) == nil
      assert Teams.get_team(-1) == nil
    end
  end
end
