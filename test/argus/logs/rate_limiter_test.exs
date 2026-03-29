defmodule Argus.Logs.RateLimiterTest do
  use ExUnit.Case, async: true

  alias Argus.Logs.RateLimiter

  test "allows up to the threshold and emits summary details on the first drop" do
    {clock, limiter} = start_limiter(max_logs: 2, window_seconds: 60)

    assert :allow = RateLimiter.check(10, server: limiter)
    assert :allow = RateLimiter.check(10, server: limiter)

    assert {:drop, summary} = RateLimiter.check(10, server: limiter)
    assert summary.max_logs == 2
    assert summary.window_seconds == 60
    assert summary.suppression_started_at == current_datetime(clock)

    assert {:drop, :rate_limited} = RateLimiter.check(10, server: limiter)
  end

  test "resets suppression once the window moves forward" do
    {clock, limiter} = start_limiter(max_logs: 1, window_seconds: 10)

    assert :allow = RateLimiter.check(20, server: limiter)
    assert {:drop, _summary} = RateLimiter.check(20, server: limiter)

    advance_clock(clock, 11)

    assert :allow = RateLimiter.check(20, server: limiter)
    assert {:drop, summary} = RateLimiter.check(20, server: limiter)
    assert summary.suppression_started_at == current_datetime(clock)
  end

  test "keeps buckets isolated per project" do
    {_clock, limiter} = start_limiter(max_logs: 1, window_seconds: 60)

    assert :allow = RateLimiter.check(30, server: limiter)
    assert {:drop, _summary} = RateLimiter.check(30, server: limiter)

    assert :allow = RateLimiter.check(31, server: limiter)
  end

  test "fails fast on invalid config" do
    Process.flag(:trap_exit, true)

    assert {:error, {:invalid_rate_limiter_config, :max_logs}} =
             RateLimiter.start_link(
               name: {:global, {__MODULE__, make_ref()}},
               config: [enabled: true, max_logs: 0, window_seconds: 60]
             )
  end

  defp start_limiter(config) do
    now = ~U[2026-03-28 23:30:00Z]

    clock =
      start_supervised!({Agent, fn -> %{mono: 1_000, now: now} end})

    limiter =
      {:global, {__MODULE__, make_ref()}}

    start_supervised!(
      {RateLimiter,
       name: limiter,
       config: Keyword.merge([enabled: true], config),
       now_monotonic_fun: fn -> Agent.get(clock, & &1.mono) end,
       now_datetime_fun: fn -> Agent.get(clock, & &1.now) end}
    )

    {clock, limiter}
  end

  defp advance_clock(clock, seconds) do
    Agent.update(clock, fn state ->
      %{
        mono: state.mono + seconds * 1_000,
        now: DateTime.add(state.now, seconds, :second)
      }
    end)
  end

  defp current_datetime(clock), do: Agent.get(clock, & &1.now)
end
