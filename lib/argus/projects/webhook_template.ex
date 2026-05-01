defmodule Argus.Projects.WebhookTemplate do
  @moduledoc """
  JSON webhook body templates with `{{path.to.value}}` placeholders.
  """

  @placeholder ~r/\{\{\s*([a-zA-Z0-9_.]+)\s*\}\}/
  @exact_placeholder ~r/\A\{\{\s*([a-zA-Z0-9_.]+)\s*\}\}\z/

  def default_body do
    Jason.encode!(
      %{
        text:
          "{{event_label}} in {{project.name}}: {{issue.title}}\nLevel: {{issue.level}}\nStatus: {{issue.status}}\nOccurrences: {{issue.occurrence_count}}\n{{url}}"
      },
      pretty: true
    )
  end

  def decode(template) when is_binary(template), do: Jason.decode(template)
  def decode(_template), do: {:error, :invalid_template}

  def render(template, context) when is_binary(template) and is_map(context) do
    with {:ok, %{} = decoded} <- decode(template) do
      {:ok, render_value(decoded, context)}
    else
      {:ok, _other} -> {:error, :template_not_object}
      {:error, reason} -> {:error, reason}
    end
  end

  def render(_template, _context), do: {:error, :invalid_template}

  defp render_value(value, context) when is_map(value) do
    Map.new(value, fn {key, val} -> {key, render_value(val, context)} end)
  end

  defp render_value(value, context) when is_list(value) do
    Enum.map(value, &render_value(&1, context))
  end

  defp render_value(value, context) when is_binary(value) do
    case Regex.run(@exact_placeholder, value) do
      [_, path] ->
        lookup(context, path)

      _ ->
        Regex.replace(@placeholder, value, fn _match, path ->
          context
          |> lookup(path)
          |> stringify()
        end)
    end
  end

  defp render_value(value, _context), do: value

  defp lookup(context, path) do
    path
    |> String.split(".")
    |> Enum.reduce_while(context, fn segment, current ->
      case fetch_segment(current, segment) do
        {:ok, value} -> {:cont, value}
        :error -> {:halt, nil}
      end
    end)
  end

  defp fetch_segment(%{} = map, segment) do
    cond do
      Map.has_key?(map, segment) ->
        {:ok, Map.get(map, segment)}

      match = Enum.find(map, fn {key, _value} -> to_string(key) == segment end) ->
        {:ok, elem(match, 1)}

      true ->
        :error
    end
  end

  defp fetch_segment(_current, _segment), do: :error

  defp stringify(nil), do: ""
  defp stringify(value) when is_binary(value), do: value
  defp stringify(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify(value), do: to_string(value)
end
