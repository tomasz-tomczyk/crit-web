defmodule Crit.Integrations do
  @moduledoc """
  Static integration metadata for the /integrations pages.

  Lists supported AI coding agents (Claude Code, Cursor, Copilot, etc.) and
  the reusable component descriptions referenced from each tool's page.
  """

  @tools [
    %{
      id: "claude-code",
      name: "Claude Code",
      tagline: "The full Crit workflow for Claude Code",
      logo: %{
        light: "/images/integrations/claude-code-light.svg",
        dark: "/images/integrations/claude-code-dark.svg"
      },
      page_title: "Crit + Claude Code — plan-mode review for AI agents",
      meta:
        "Install crit's plugin for Claude Code: a /crit slash command, the crit-cli skill, and an automatic plan-mode review hook that opens every plan for inline review before any code is written.",
      intro:
        "Claude Code is the only agent with the plan-mode hook: every plan it writes goes through Crit for inline review before any file edits happen.",
      command: "crit install claude-code",
      components: [:crit_command, :crit_cli_skill, :plan_hook],
      marketplace: %{
        intro:
          "Installs a global Claude Code plugin with the /crit slash command, the crit-cli skill, and the plan-mode hook below. Works across every project.",
        commands: [
          "claude plugin marketplace add tomasz-tomczyk/crit",
          "claude plugin install crit@crit"
        ]
      }
    },
    %{
      id: "cursor",
      name: "Cursor",
      tagline: "Inline review for Cursor",
      logo: %{
        light: "/images/integrations/cursor-light.svg",
        dark: "/images/integrations/cursor-dark.svg"
      },
      page_title: "Crit + Cursor — inline review for plans and code",
      meta:
        "Install crit for Cursor: drops a /crit slash command and the crit-cli skill into .cursor/skills/. Cursor auto-loads them so the agent reviews plans with you before writing code.",
      intro:
        "crit installs the /crit command and the crit-cli helper into .cursor/skills/. Cursor auto-loads them, no extra setup.",
      command: "crit install cursor",
      components: [:crit_command, :crit_cli_skill]
    },
    %{
      id: "github-copilot",
      name: "GitHub Copilot",
      tagline: "Crit as a Copilot Agent Skill",
      logo: %{
        light: "/images/integrations/github-copilot-light.svg",
        dark: "/images/integrations/github-copilot-dark.svg"
      },
      page_title: "Crit + GitHub Copilot — review AI plans inline",
      meta:
        "Install crit as a GitHub Copilot Agent Skill. Drops .github/skills/crit/SKILL.md and .github/skills/crit-cli/SKILL.md so Copilot auto-loads the review workflow.",
      intro:
        "Copilot auto-discovers Agent Skills under .github/skills/ in your repo, or under ~/.copilot/skills/ for a global install.",
      command: "crit install github-copilot",
      components: [:crit_command, :crit_cli_skill]
    },
    %{
      id: "opencode",
      name: "OpenCode",
      tagline: "Crit as an OpenCode skill",
      logo: %{
        light: "/images/integrations/opencode-light.svg",
        dark: "/images/integrations/opencode-dark.svg"
      },
      page_title: "Crit + OpenCode — inline plan review",
      meta:
        "Install crit's OpenCode skill. Drops .opencode/skills/crit/SKILL.md so OpenCode auto-activates the review workflow when you ask it to plan or review changes.",
      intro:
        "OpenCode discovers skills from .opencode/skills/ based on their frontmatter. The crit skill triggers on plan and review requests.",
      command: "crit install opencode",
      components: [:crit_command, :crit_cli_skill]
    },
    %{
      id: "codex",
      name: "Codex",
      tagline: "Crit as a Codex skill",
      logo: %{
        light: "/images/integrations/codex-light.svg",
        dark: "/images/integrations/codex-dark.svg"
      },
      page_title: "Crit + OpenAI Codex CLI — review AI plans inline",
      meta:
        "Install crit's Codex skill. Drops .agents/skills/crit/ and .agents/skills/crit-cli/ so the OpenAI Codex CLI discovers the review workflow automatically.",
      intro:
        "Codex CLI walks up from cwd looking for .agents/skills/, with a global fallback at ~/.agents/skills/. The files follow the cross-tool Agent Skills spec, so any compatible agent loads them.",
      command: "crit install codex",
      components: [:crit_command, :crit_cli_skill]
    },
    %{
      id: "gemini",
      name: "Gemini CLI",
      tagline: "Crit as a Gemini CLI skill",
      logo: %{
        light: "/images/integrations/gemini-light.svg",
        dark: "/images/integrations/gemini-dark.svg"
      },
      page_title: "Crit + Gemini CLI — review AI plans inline",
      meta:
        "Install crit's Gemini CLI integration. Drops a /crit slash command, the crit-cli skill, and merges an exit_plan_mode hook into .gemini/settings.json so Gemini routes every plan through Crit for inline review.",
      intro:
        "Gemini CLI auto-loads commands and skills from .gemini/ (project) and ~/.gemini/ (global). crit installs the /crit command, the crit-cli skill, and an exit_plan_mode hook that hands every plan to Crit before any code is written.",
      command: "crit install gemini",
      components: [:crit_command, :crit_cli_skill]
    },
    %{
      id: "qwen",
      name: "Qwen Code",
      tagline: "Crit as a Qwen Code skill",
      logo: %{
        light: "/images/integrations/qwen-light.svg",
        dark: "/images/integrations/qwen-dark.svg"
      },
      page_title: "Crit + Qwen Code — review AI plans inline",
      meta:
        "Install crit's Qwen Code skill. Drops .qwen/skills/crit/ and .qwen/skills/crit-cli/ so Qwen Code auto-loads the review workflow.",
      intro:
        "Qwen Code auto-discovers skills from .qwen/skills/ (project) and ~/.qwen/skills/ (global). The crit skill activates whenever Qwen plans or reviews code.",
      command: "crit install qwen",
      components: [:crit_command, :crit_cli_skill]
    },
    %{
      id: "hermes",
      name: "Hermes",
      tagline: "Crit as a Hermes skill",
      logo: nil,
      page_title: "Crit + Hermes — review AI plans inline",
      meta:
        "Install crit's Hermes integration. A global install (`cd ~ && crit install hermes`) drops skills into ~/.hermes/skills/ where Hermes auto-discovers them across every project.",
      intro:
        "Hermes auto-discovers skills from ~/.hermes/skills/. Run `crit install hermes` from your home directory for the recommended global setup, or install per-project and add `.hermes/skills` to `external_dirs` under the `skills` section of ~/.hermes/config.yaml.",
      command: "crit install hermes",
      components: [:crit_command, :crit_cli_skill]
    },
    %{
      id: "windsurf",
      name: "Windsurf",
      tagline: "A Windsurf rule for Crit",
      logo: %{
        light: "/images/integrations/windsurf-light.svg",
        dark: "/images/integrations/windsurf-dark.svg"
      },
      page_title: "Crit + Windsurf — review plans before coding",
      meta:
        "Install crit's Windsurf rule. Drops .windsurf/rules/crit.md so Cascade always knows to launch Crit for plan review before writing code.",
      intro:
        "Windsurf's Cascade auto-loads rules from .windsurf/rules/. crit installs a single rule that defines the review loop: write a plan, run crit on it, address each inline comment, implement.",
      command: "crit install windsurf",
      no_global: true,
      components: [:crit_rule]
    },
    %{
      id: "cline",
      name: "Cline",
      tagline: "A Cline rule for Crit",
      logo: nil,
      page_title: "Crit + Cline — review plans before coding",
      meta:
        "Install crit's Cline rule. Drops .clinerules/crit.md so Cline follows the plan-first review loop with inline feedback before any code change.",
      intro:
        "Cline auto-loads every file under .clinerules/. crit drops a single rule there that walks the agent through the review loop. Cline has no skills or slash commands, so the rule carries the workflow.",
      command: "crit install cline",
      components: [:crit_rule]
    },
    %{
      id: "aider",
      name: "Aider",
      tagline: "Crit conventions for Aider",
      logo: nil,
      page_title: "Crit + Aider — inline plan review",
      meta:
        "Use Crit with Aider by appending the crit conventions to your CONVENTIONS.md. Aider then follows the plan-first review loop with inline feedback before any code change.",
      intro:
        "Aider has no skills or plugins. It reads conventions from CONVENTIONS.md (or any file passed via --read or .aider.conf.yml). Append the crit conventions and Aider follows the plan-first review loop on every change.",
      command: nil,
      manual:
        "Append integrations/aider/CONVENTIONS.md from the crit repo to your project's CONVENTIONS.md.",
      components: [:crit_rule]
    }
  ]

  @components %{
    crit_command: %{
      label: "/crit slash command",
      summary:
        "Starts the review loop. The agent launches Crit, waits for your inline comments, then revises until you approve.",
      use_cases: [
        %{
          title: nil,
          desc: nil,
          example_label: "In your agent's chat:",
          example: "/crit"
        }
      ]
    },
    crit_cli_skill: %{
      label: "crit-cli skill",
      summary:
        "Auto-activates when the agent works with review files, shares a review, or syncs to a PR. No manual invocation. Talk to the agent normally and it picks the right crit subcommand.",
      use_cases: [
        %{
          title: "Spawn a team of agents to review the work",
          desc:
            "Your main agent runs /crit and dispatches reviewer subagents. Each one leaves inline comments via crit. You scan the comments and decide which ones to act on.",
          example_label: "In your agent's chat:",
          example:
            "Run /crit and spawn a team of agents to use crit to review the work. I'll decide which comments to proceed with."
        },
        %{
          title: "Review from your phone",
          desc:
            "The share URL renders on mobile, so you can leave inline comments from the couch while the agent keeps grinding.",
          example_label: "In your agent's chat:",
          example: "Share the current review with crit and send me the link."
        }
      ]
    },
    plan_hook: %{
      label: "Plan-mode review hook",
      summary:
        "Intercepts Claude Code's ExitPlanMode and sends the plan to Crit for inline review. You comment line-by-line, the agent revises, and plan mode doesn't exit until you approve. Ships only with the marketplace plugin.",
      use_cases: [
        %{
          title: nil,
          desc: nil,
          example_label: "Disable per-shell or globally:",
          example: "export CRIT_PLAN_REVIEW=off"
        }
      ]
    },
    crit_rule: %{
      label: "Crit rule",
      summary:
        "A single rules file the agent loads for every conversation in this project. It defines the review loop: write a plan, launch crit $PLAN_FILE, read the resulting review file, address each comment, repeat.",
      use_cases: [
        %{
          title: nil,
          desc: nil,
          example_label: "Prompt the agent:",
          example: "Write a plan for the auth refactor, then run crit on it."
        }
      ]
    }
  }

  @doc "Returns the list of supported integration tools."
  def tools, do: @tools

  @doc "Returns the map of reusable component descriptions keyed by id."
  def components, do: @components

  @doc """
  Looks up a tool by its `id`.

  Returns `{:ok, tool}` or `:error` if no tool matches.
  """
  def get_tool(id) when is_binary(id) do
    case Enum.find(@tools, &(&1.id == id)) do
      nil -> :error
      tool -> {:ok, tool}
    end
  end

  @doc """
  Fetches a component by id, raising a useful error if it's missing.

  Used from templates where a missing key is a programming error (a tool's
  `:components` list referenced a component that doesn't exist).
  """
  def fetch_component!(id) when is_atom(id) do
    case Map.fetch(@components, id) do
      {:ok, component} ->
        component

      :error ->
        raise ArgumentError,
              "unknown integration component #{inspect(id)} — " <>
                "check Crit.Integrations.@components for valid keys"
    end
  end
end
