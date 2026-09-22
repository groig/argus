defmodule ArgusWeb.MetricsLive.IndexTest do
  use ArgusWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  import Argus.AccountsFixtures
  import Argus.WorkspaceFixtures

  setup %{conn: conn} do
    user = user_fixture()
    team = team_fixture()
    _membership = membership_fixture(team, user, :admin)
    project = project_fixture(team, %{"name" => "Billing API"})

    %{conn: log_in_user(conn, user), project: project}
  end

  test "renders a chart and raw metric points", %{conn: conn, project: project} do
    _metric =
      metric_fixture(project, %{
        name: "checkout.duration",
        type: :distribution,
        value: 120.5,
        unit: "millisecond",
        attributes: %{"route" => "/checkout", "release" => "1.2.0"}
      })

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/metrics")

    assert has_element?(view, "#metric-filters")
    assert has_element?(view, "#project-metrics-chart")
    assert has_element?(view, "#metric-points tr", "checkout.duration")
    assert has_element?(view, "#metric-points tr", "millisecond")

    [chart_config] =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query_by_id("project-metrics-chart")
      |> LazyHTML.attribute("data-chart")

    decoded_config = Jason.decode!(chart_config)

    assert decoded_config["chart"]["height"] == "100%"
    assert decoded_config["chart"]["width"] == "100%"
    assert decoded_config["chart"]["redrawOnParentResize"]
    assert decoded_config["xaxis"]["labels"]["show"]
    assert decoded_config["legend"]["position"] == "bottom"
  end

  test "filters metric points by name and type", %{conn: conn, project: project} do
    _counter = metric_fixture(project, %{name: "button_click", type: :counter, value: 5})
    _gauge = metric_fixture(project, %{name: "queue.depth", type: :gauge, value: 9})

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.slug}/metrics")

    render_change(
      form(view, "#metric-filters", %{
        "filters" => %{"name" => "button_click", "type" => "counter", "window" => "1h"}
      })
    )

    assert has_element?(view, "#metric-points tr", "button_click")
    refute has_element?(view, "#metric-points tr", "queue.depth")
  end
end
