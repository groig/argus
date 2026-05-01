defmodule Argus.Projects.WebhookTemplateTest do
  use ExUnit.Case, async: true

  alias Argus.Projects.WebhookTemplate

  test "renders placeholders inside JSON strings" do
    template = ~s({"text":"{{event_label}} in {{project.name}}: {{issue.title}}\\n{{url}}"})

    context = %{
      event_label: "A new issue was detected",
      project: %{name: "Payments"},
      issue: %{title: "RuntimeError: boom"},
      url: "https://argus.test/issues/1"
    }

    assert {:ok, body} = WebhookTemplate.render(template, context)

    assert body == %{
             "text" =>
               "A new issue was detected in Payments: RuntimeError: boom\nhttps://argus.test/issues/1"
           }
  end

  test "preserves native JSON values for exact placeholders" do
    template = ~s({"issue":"{{issue}}","tags":"{{tags}}","missing":"{{missing.value}}"})

    context = %{
      issue: %{id: 123, title: "RuntimeError: boom"},
      tags: %{"environment" => "prod"}
    }

    assert {:ok, body} = WebhookTemplate.render(template, context)

    assert body["issue"] == %{id: 123, title: "RuntimeError: boom"}
    assert body["tags"] == %{"environment" => "prod"}
    assert body["missing"] == nil
  end

  test "rejects invalid JSON and non-object templates" do
    assert {:error, %Jason.DecodeError{}} = WebhookTemplate.render("{", %{})
    assert {:error, :template_not_object} = WebhookTemplate.render(~s(["{{issue.title}}"]), %{})
  end
end
