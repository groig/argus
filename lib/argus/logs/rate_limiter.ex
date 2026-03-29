defmodule Argus.Logs.RateLimiter do
  @moduledoc """
  Sliding-window log rate limiting keyed by project.
  """

  use GenServer

  @default_config [enabled: false, max_logs: 1_000, window_seconds: 60]

  defstruct enabled: false,
            max_logs: 1_000,
            window_seconds: 60,
            window_ms: 60_000,
            projects: %{},
            now_monotonic_fun: nil,
            now_datetime_fun: nil

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def check(project_id, opts \\ []) when is_integer(project_id) do
    server = Keyword.get(opts, :server, __MODULE__)
    GenServer.call(server, {:check, project_id})
  end

  @impl true
  def init(opts) do
    config = opts[:config] || Application.get_env(:argus, __MODULE__, [])

    with {:ok, settings} <- validate_config(config) do
      {:ok,
       %__MODULE__{
         enabled: settings.enabled,
         max_logs: settings.max_logs,
         window_seconds: settings.window_seconds,
         window_ms: settings.window_seconds * 1_000,
         projects: %{},
         now_monotonic_fun:
           opts[:now_monotonic_fun] || fn -> System.monotonic_time(:millisecond) end,
         now_datetime_fun: opts[:now_datetime_fun] || fn -> DateTime.utc_now(:second) end
       }}
    end
  end

  @impl true
  def handle_call({:check, _project_id}, _from, %__MODULE__{enabled: false} = state) do
    {:reply, :allow, state}
  end

  def handle_call({:check, project_id}, _from, %__MODULE__{} = state) do
    now_mono = state.now_monotonic_fun.()
    now_datetime = state.now_datetime_fun.()
    cutoff = now_mono - state.window_ms

    project_state =
      state.projects
      |> Map.get(project_id, %{timestamps: [], suppressing?: false, suppression_started_at: nil})
      |> trim_project_state(cutoff)

    {reply, updated_project_state} =
      if length(project_state.timestamps) < state.max_logs do
        {:allow,
         %{
           timestamps: project_state.timestamps ++ [now_mono],
           suppressing?: false,
           suppression_started_at: nil
         }}
      else
        if project_state.suppressing? do
          {{:drop, :rate_limited}, project_state}
        else
          summary = %{
            max_logs: state.max_logs,
            window_seconds: state.window_seconds,
            suppression_started_at: now_datetime
          }

          {{:drop, summary},
           %{
             project_state
             | suppressing?: true,
               suppression_started_at: now_datetime
           }}
        end
      end

    {:reply, reply, put_project_state(state, project_id, updated_project_state)}
  end

  defp validate_config(config) do
    merged =
      @default_config
      |> Keyword.merge(config)
      |> Enum.into(%{})

    cond do
      not is_boolean(merged.enabled) ->
        {:stop, {:invalid_rate_limiter_config, :enabled}}

      not is_integer(merged.max_logs) or merged.max_logs <= 0 ->
        {:stop, {:invalid_rate_limiter_config, :max_logs}}

      not is_integer(merged.window_seconds) or merged.window_seconds <= 0 ->
        {:stop, {:invalid_rate_limiter_config, :window_seconds}}

      true ->
        {:ok, merged}
    end
  end

  defp trim_project_state(project_state, cutoff) do
    timestamps = Enum.drop_while(project_state.timestamps, &(&1 <= cutoff))

    %{
      timestamps: timestamps,
      suppressing?: project_state.suppressing? and timestamps != [],
      suppression_started_at:
        if(project_state.suppressing? and timestamps != [],
          do: project_state.suppression_started_at,
          else: nil
        )
    }
  end

  defp put_project_state(state, project_id, %{timestamps: []} = project_state) do
    projects =
      if project_state.suppressing? do
        Map.put(state.projects, project_id, project_state)
      else
        Map.delete(state.projects, project_id)
      end

    %{state | projects: projects}
  end

  defp put_project_state(state, project_id, project_state) do
    %{state | projects: Map.put(state.projects, project_id, project_state)}
  end
end
