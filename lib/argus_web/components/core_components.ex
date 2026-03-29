defmodule ArgusWeb.CoreComponents do
  @moduledoc """
  Shared UI components for Argus.
  """

  use Phoenix.Component
  use Gettext, backend: ArgusWeb.Gettext

  alias Phoenix.LiveView.JS

  attr :id, :string, default: nil
  attr :flash, :map, default: %{}
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], required: true
  attr :rest, :global
  slot :inner_block

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <.toast
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      kind={@kind}
      title={@title}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      {@rest}
    >
      {msg}
    </.toast>
    """
  end

  attr :rest, :global, include: ~w(href navigate patch method download name value disabled type)
  attr :variant, :string, values: ~w(primary secondary ghost danger), default: "primary"
  attr :size, :string, values: ~w(xs sm md), default: "md"
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    classes = [
      "inline-flex cursor-pointer items-center justify-center gap-2 rounded-sm font-medium transition duration-150 focus:outline-none focus:ring-2 focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-55",
      button_variant(assigns.variant),
      button_size(assigns.size),
      assigns.class
    ]

    assigns = assign(assigns, :classes, classes)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@classes} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@classes} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField
  attr :errors, :list, default: []
  attr :checked, :boolean, default: nil
  attr :prompt, :string, default: nil
  attr :options, :list, default: []
  attr :multiple, :boolean, default: false
  attr :class, :any, default: nil

  attr :rest, :global,
    include:
      ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step phx-change phx-debounce)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <label class="flex items-center gap-3 text-sm text-zinc-700">
      <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} form={@rest[:form]} />
      <input
        id={@id}
        type="checkbox"
        name={@name}
        value="true"
        checked={@checked}
        class="h-4 w-4 rounded-sm border-zinc-300 bg-white text-sky-600 focus:ring-sky-500"
        {@rest}
      />
      <span>{@label}</span>
    </label>
    <.error :for={msg <- @errors}>{msg}</.error>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="space-y-2">
      <label
        :if={@label}
        for={@id}
        class="text-[11px] font-semibold uppercase tracking-[0.14em] text-zinc-500"
      >
        {@label}
      </label>
      <select
        id={@id}
        name={@name}
        class={[
          "w-full rounded-sm border bg-white px-4 py-3 text-sm text-zinc-900 outline-none transition focus:border-sky-500 focus:ring-2 focus:ring-sky-500/15",
          @errors != [] && "border-red-300",
          @errors == [] && "border-zinc-200",
          @class
        ]}
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Phoenix.HTML.Form.options_for_select(@options, @value)}
      </select>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="space-y-2">
      <label
        :if={@label}
        for={@id}
        class="text-[11px] font-semibold uppercase tracking-[0.14em] text-zinc-500"
      >
        {@label}
      </label>
      <textarea
        id={@id}
        name={@name}
        class={[
          "min-h-28 w-full rounded-sm border bg-white px-4 py-3 text-sm text-zinc-900 outline-none transition focus:border-sky-500 focus:ring-2 focus:ring-sky-500/15",
          @errors != [] && "border-red-300",
          @errors == [] && "border-zinc-200",
          @class
        ]}
        {@rest}
      >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(assigns) do
    ~H"""
    <div class="space-y-2">
      <label
        :if={@label}
        for={@id}
        class="text-[11px] font-semibold uppercase tracking-[0.14em] text-zinc-500"
      >
        {@label}
      </label>
      <input
        id={@id}
        type={@type}
        name={@name}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        class={[
          "w-full rounded-sm border bg-white px-4 py-3 text-sm text-zinc-900 outline-none transition focus:border-sky-500 focus:ring-2 focus:ring-sky-500/15",
          @errors != [] && "border-red-300",
          @errors == [] && "border-zinc-200",
          @class
        ]}
        {@rest}
      />
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <p class="flex items-center gap-2 text-sm text-red-600">
      <.icon name="hero-exclamation-circle" class="size-4" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between lg:gap-6">
      <div class="space-y-2">
        <h1 class="text-3xl font-semibold tracking-tight text-zinc-950">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="max-w-3xl text-sm leading-6 text-zinc-500">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div :if={@actions != []} class="flex shrink-0 flex-wrap items-center gap-3">
        {render_slot(@actions)}
      </div>
    </header>
    """
  end

  attr :kind, :string, required: true
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def badge(assigns) do
    ~H"""
    <span class={[badge_variant(@kind), @class]}>
      <span class={["size-1.5 rounded-full", badge_dot(@kind)]} />
      {render_slot(@inner_block)}
    </span>
    """
  end

  attr :id, :string, default: nil
  attr :at, :any, required: true
  attr :format, :string, default: "default"
  attr :class, :string, default: nil

  def relative_time(assigns) do
    assigns =
      if assigns.id do
        assigns
      else
        assign(
          assigns,
          :id,
          "relative-time-" <> Integer.to_string(System.unique_integer([:positive, :monotonic]))
        )
      end

    screenshot_mode? = screenshot_mode?()
    assigns = assign(assigns, :screenshot_mode?, screenshot_mode?)

    ~H"""
    <time
      id={@id}
      class={["whitespace-nowrap text-sm text-zinc-500", @class]}
      phx-hook={if @screenshot_mode?, do: nil, else: "RelativeTime"}
      phx-update={if @screenshot_mode?, do: nil, else: "ignore"}
      data-timestamp={to_iso8601(@at)}
      title={if @screenshot_mode?, do: format_absolute(@at, "default"), else: nil}
    >
      {if @screenshot_mode?, do: format_absolute(@at, @format), else: format_relative(@at)}
    </time>
    """
  end

  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :icon, :string, default: "hero-sparkles"
  slot :action

  def empty_state(assigns) do
    ~H"""
    <div class="flex min-h-72 flex-col items-center justify-center border border-zinc-200 bg-white px-8 py-12 text-center">
      <div class="flex h-14 w-14 items-center justify-center border border-zinc-200 bg-slate-50 text-zinc-300">
        <.icon name={@icon} class="size-7" />
      </div>
      <h2 class="text-xl font-semibold tracking-tight text-zinc-950">{@title}</h2>
      <p :if={@description} class="mt-3 max-w-md text-sm leading-6 text-zinc-500">{@description}</p>
      <div :if={@action != []} class="mt-6 flex items-center gap-3">{render_slot(@action)}</div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :stream, :boolean, default: false
  attr :row_id, :any, default: nil
  attr :class, :string, default: nil

  slot :col, required: true do
    attr :label, :string, required: true
    attr :class, :string
  end

  def table(assigns) do
    ~H"""
    <div class={["border border-zinc-200 bg-white", @class]}>
      <table class="min-w-full divide-y divide-zinc-200/80 text-sm">
        <thead class="bg-slate-50 text-left text-[11px] font-semibold uppercase tracking-[0.14em] text-zinc-500">
          <tr>
            <th :for={col <- @col} class="px-5 py-3.5">{col.label}</th>
          </tr>
        </thead>
        <tbody id={@id} phx-update={@stream && "stream"} class="divide-y divide-zinc-100 bg-white">
          <tr
            :for={row <- @rows}
            id={@row_id && @row_id.(row)}
            class="align-top text-zinc-700 transition hover:bg-slate-50"
          >
            <td :for={col <- @col} class={["px-5 py-4", col[:class]]}>{render_slot(col, row)}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr :rest, :global,
    include: ~w(href navigate patch method type disabled phx-click phx-value-id phx-value-modal)

  attr :class, :any, default: nil
  attr :icon, :string, default: nil
  slot :inner_block, required: true

  def action_button(assigns) do
    ~H"""
    <.button
      variant="secondary"
      size="xs"
      class={[
        "gap-1.5 border-zinc-200 bg-white px-2.5 py-1.5 text-[11px] font-medium text-zinc-700 hover:border-sky-200 hover:bg-sky-50 hover:text-sky-700",
        @class
      ]}
      {@rest}
    >
      <.icon :if={@icon} name={@icon} class="size-3.5 shrink-0" />
      {render_slot(@inner_block)}
    </.button>
    """
  end

  attr :id, :string, required: true
  attr :class, :any, default: nil

  slot :item, required: true do
    attr :navigate, :string
    attr :patch, :string
    attr :href, :string
    attr :method, :string
    attr :phx_click, :string
    attr :phx_value_id, :any
    attr :class, :string
  end

  def overflow_menu(assigns) do
    ~H"""
    <details id={@id} class={["group relative", @class]}>
      <summary class="flex list-none cursor-pointer items-center justify-center border border-zinc-200 bg-white p-1.5 text-zinc-500 transition hover:border-sky-200 hover:bg-sky-50 hover:text-sky-700 group-open:border-zinc-300 group-open:bg-zinc-50 group-open:text-zinc-700 [&::-webkit-details-marker]:hidden">
        <.icon name="hero-ellipsis-horizontal-mini" class="size-4" />
      </summary>
      <div class="absolute right-0 top-full z-30 mt-2 w-44 rounded-md border border-zinc-200 bg-white p-1.5 shadow-[0_22px_60px_rgba(15,23,42,0.18)] ring-1 ring-zinc-950/5">
        <%= for item <- @item do %>
          <.link
            navigate={item[:navigate]}
            patch={item[:patch]}
            href={item[:href]}
            method={item[:method]}
            phx-click={item[:phx_click]}
            phx-value-id={item[:phx_value_id]}
            class={[
              "block px-3 py-2 text-sm text-zinc-700 transition hover:bg-slate-50 hover:text-zinc-950",
              item[:class]
            ]}
          >
            {render_slot(item)}
          </.link>
        <% end %>
      </div>
    </details>
    """
  end

  attr :open, :boolean, default: false
  attr :title, :string, required: true
  attr :id, :string, default: "drawer"
  slot :inner_block, required: true

  def drawer(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "fixed inset-y-0 right-0 z-40 w-full max-w-xl border-l border-zinc-200 bg-white shadow-[0_18px_48px_rgba(15,23,42,0.16)] transition-transform duration-200",
        @open && "translate-x-0",
        !@open && "translate-x-full"
      ]}
    >
      <div class="border-b border-zinc-200 px-6 py-4">
        <h3 class="text-lg font-semibold text-zinc-950">{@title}</h3>
      </div>
      <div class="overflow-y-auto px-6 py-6">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  attr :id, :string, default: nil
  attr :kind, :atom, values: [:info, :error], default: :info
  attr :title, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def toast(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "pointer-events-auto w-full max-w-sm border bg-white px-4 py-3 shadow-[0_14px_40px_rgba(15,23,42,0.12)]",
        toast_shell(@kind)
      ]}
      {@rest}
    >
      <div class="flex items-start gap-3">
        <div class={[
          "mt-0.5 flex h-7 w-7 items-center justify-center rounded-sm",
          toast_icon_bg(@kind)
        ]}>
          <.icon name={toast_icon(@kind)} class={["size-4", toast_icon_color(@kind)]} />
        </div>
        <div class="flex-1 space-y-1">
          <p :if={@title} class="text-sm font-semibold text-zinc-950">{@title}</p>
          <p class="text-sm leading-6 text-zinc-600">{render_slot(@inner_block)}</p>
        </div>
      </div>
    </div>
    """
  end

  attr :id, :string, default: nil
  attr :value, :string, required: true
  attr :label, :string, default: nil
  attr :toast_message, :string, default: "Copied to clipboard"
  attr :compact, :boolean, default: false
  attr :tooltip, :string, default: nil
  attr :class, :string, default: nil

  def copy_to_clipboard(assigns) do
    assigns =
      if assigns.id do
        assigns
      else
        assign(assigns, :id, "copy-" <> Integer.to_string(:erlang.phash2(assigns.value)))
      end

    ~H"""
    <%= if @compact do %>
      <button
        id={@id}
        type="button"
        title={@tooltip || @value}
        phx-hook="ClipboardCopy"
        data-copy-value={@value}
        data-copy-toast={@toast_message}
        class={[
          "max-w-full cursor-pointer overflow-hidden text-ellipsis whitespace-nowrap font-mono text-xs text-zinc-500 transition hover:text-sky-700 hover:underline",
          @class
        ]}
      >
        {@label || @value}
      </button>
    <% else %>
      <div class={[
        "flex items-center gap-3 border border-zinc-200 bg-white px-4 py-3",
        @class
      ]}>
        <code class="min-w-0 flex-1 overflow-hidden text-ellipsis whitespace-nowrap text-xs text-zinc-700">
          {@label || @value}
        </code>
        <button
          id={@id}
          type="button"
          title={@tooltip || @value}
          phx-hook="ClipboardCopy"
          data-copy-value={@value}
          data-copy-toast={@toast_message}
          class="cursor-pointer rounded-sm border border-zinc-200 bg-slate-50 px-3 py-1.5 text-xs font-medium text-zinc-700 transition hover:border-sky-200 hover:bg-sky-50 hover:text-sky-700"
        >
          Copy
        </button>
      </div>
    <% end %>
    """
  end

  attr :id, :string, required: true
  attr :open, :boolean, default: false
  attr :title, :string, required: true
  slot :inner_block, required: true
  slot :actions

  def modal(assigns) do
    ~H"""
    <div
      :if={@open}
      id={@id}
      class="fixed inset-0 z-50 flex items-center justify-center bg-zinc-950/45 px-4 backdrop-blur-[2px]"
    >
      <div class="w-full max-w-md border border-zinc-200 bg-white p-6 shadow-[0_24px_60px_rgba(15,23,42,0.18)]">
        <h3 class="text-lg font-semibold text-zinc-950">{@title}</h3>
        <div class="mt-4 text-sm leading-6 text-zinc-600">{render_slot(@inner_block)}</div>
        <div :if={@actions != []} class="mt-6 flex justify-end gap-3">{render_slot(@actions)}</div>
      </div>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 200,
      transition: {"transition ease-out duration-200", "opacity-0", "opacity-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 150,
      transition: {"transition ease-in duration-150", "opacity-100", "opacity-0"}
    )
  end

  def translate_error({msg, opts}) do
    if count = opts[:count] do
      Gettext.dngettext(ArgusWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(ArgusWeb.Gettext, "errors", msg, opts)
    end
  end

  defp button_variant("primary"),
    do:
      "bg-sky-600 text-white shadow-[0_1px_0_rgba(255,255,255,0.04)] hover:bg-sky-700 focus:ring-sky-300"

  defp button_variant("secondary"),
    do:
      "border border-zinc-200 bg-white text-zinc-900 shadow-[0_1px_0_rgba(15,23,42,0.03)] hover:border-sky-200 hover:bg-sky-50 hover:text-sky-700 focus:ring-sky-300"

  defp button_variant("ghost"),
    do: "bg-transparent text-zinc-600 hover:bg-white hover:text-sky-700 focus:ring-sky-300"

  defp button_variant("danger"), do: "bg-red-600 text-white hover:bg-red-700 focus:ring-red-300"

  defp button_size("xs"), do: "px-2.5 py-1.5 text-xs"
  defp button_size("sm"), do: "px-3.5 py-2 text-xs"
  defp button_size("md"), do: "px-4.5 py-2.5 text-sm"

  defp badge_variant(kind) when kind in ["error", :error],
    do:
      "inline-flex items-center gap-1.5 rounded-sm bg-red-50 px-2.5 py-1 text-xs font-semibold uppercase tracking-[0.12em] text-red-700"

  defp badge_variant(kind) when kind in ["warning", :warning],
    do:
      "inline-flex items-center gap-1.5 rounded-sm bg-amber-50 px-2.5 py-1 text-xs font-semibold uppercase tracking-[0.12em] text-amber-700"

  defp badge_variant(kind) when kind in ["info", :info],
    do:
      "inline-flex items-center gap-1.5 rounded-sm bg-sky-50 px-2.5 py-1 text-xs font-semibold uppercase tracking-[0.12em] text-sky-700"

  defp badge_variant(kind) when kind in ["resolved", :resolved],
    do:
      "inline-flex items-center gap-1.5 rounded-sm bg-emerald-50 px-2.5 py-1 text-xs font-semibold uppercase tracking-[0.12em] text-emerald-700"

  defp badge_variant(kind) when kind in ["ignored", :ignored],
    do:
      "inline-flex items-center gap-1.5 rounded-sm bg-zinc-100 px-2.5 py-1 text-xs font-semibold uppercase tracking-[0.12em] text-zinc-600"

  defp badge_variant(kind) when kind in ["unresolved", :unresolved],
    do:
      "inline-flex items-center gap-1.5 rounded-sm bg-red-50 px-2.5 py-1 text-xs font-semibold uppercase tracking-[0.12em] text-red-700"

  defp badge_variant(_kind),
    do:
      "inline-flex items-center gap-1.5 rounded-sm bg-zinc-100 px-2.5 py-1 text-xs font-semibold uppercase tracking-[0.12em] text-zinc-600"

  defp badge_dot(kind) when kind in ["error", :error, "unresolved", :unresolved], do: "bg-red-500"
  defp badge_dot(kind) when kind in ["warning", :warning], do: "bg-amber-500"
  defp badge_dot(kind) when kind in ["info", :info], do: "bg-sky-500"
  defp badge_dot(kind) when kind in ["resolved", :resolved], do: "bg-emerald-500"
  defp badge_dot(kind) when kind in ["ignored", :ignored], do: "bg-zinc-400"
  defp badge_dot(_kind), do: "bg-zinc-400"

  defp toast_icon(:info), do: "hero-information-circle"
  defp toast_icon(:error), do: "hero-exclamation-circle"
  defp toast_icon_bg(:info), do: "bg-sky-100"
  defp toast_icon_bg(:error), do: "bg-red-100"
  defp toast_icon_color(:info), do: "text-sky-700"
  defp toast_icon_color(:error), do: "text-red-700"
  defp toast_shell(:info), do: "border-sky-200"
  defp toast_shell(:error), do: "border-red-200"

  defp to_iso8601(%DateTime{} = at), do: DateTime.to_iso8601(at)

  defp to_iso8601(%NaiveDateTime{} = at) do
    at
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_iso8601()
  end

  defp to_iso8601(at), do: to_string(at)

  defp format_absolute(%DateTime{} = at, "compact"), do: Calendar.strftime(at, "%m-%d %H:%M")

  defp format_absolute(%DateTime{} = at, _format),
    do: Calendar.strftime(at, "%Y-%m-%d %H:%M UTC")

  defp format_absolute(%NaiveDateTime{} = at, format) do
    at
    |> DateTime.from_naive!("Etc/UTC")
    |> format_absolute(format)
  end

  defp format_absolute(_, _format), do: ""

  defp format_relative(%DateTime{} = at) do
    seconds = DateTime.diff(DateTime.utc_now(), at)
    humanize_seconds(seconds)
  end

  defp format_relative(%NaiveDateTime{} = at) do
    at
    |> DateTime.from_naive!("Etc/UTC")
    |> format_relative()
  end

  defp format_relative(_), do: ""

  defp screenshot_mode? do
    Application.get_env(:argus, :ui, [])
    |> Keyword.get(:screenshot_mode, false)
  end

  defp humanize_seconds(seconds) when seconds < 60, do: "#{seconds}s ago"
  defp humanize_seconds(seconds) when seconds < 3_600, do: "#{div(seconds, 60)}m ago"
  defp humanize_seconds(seconds) when seconds < 86_400, do: "#{div(seconds, 3_600)}h ago"
  defp humanize_seconds(seconds), do: "#{div(seconds, 86_400)}d ago"
end
