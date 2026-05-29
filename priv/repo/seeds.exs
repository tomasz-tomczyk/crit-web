# Seeds for local development.
#
#     mix run priv/repo/seeds.exs
#     mix ecto.reset          # drops, creates, migrates, then seeds
#
# All reviews are tied to a seeded GitHub user so they appear on the dashboard.
# Tokens are deterministic so you can bookmark them.

if Mix.env() == :dev do
  import Ecto.Query
  alias Crit.{Repo, User, Review, Comment, ReviewRoundSnapshot}
  alias Crit.Organizations.{Organization, OrganizationMembership}

  now = DateTime.utc_now() |> DateTime.truncate(:second)
  now_naive = DateTime.to_naive(now)
  yesterday = DateTime.add(now, -86_400, :second)
  yesterday_naive = DateTime.to_naive(yesterday)
  last_week = DateTime.add(now, -7 * 86_400, :second)
  last_week_naive = DateTime.to_naive(last_week)

  # ── Deterministic IDs ──────────────────────────────────────────────────

  seed_user_id = "00000000-0000-0000-0000-000000000001"

  # ── Seed user (matches local GitHub OAuth) ─────────────────────────────

  user =
    case Repo.get(User, seed_user_id) do
      nil ->
        Repo.insert!(%User{
          id: seed_user_id,
          provider: "github",
          provider_uid: "182303",
          name: "Tomasz Tomczyk",
          email: "me@tomasztomczyk.com",
          avatar_url: "https://avatars.githubusercontent.com/u/182303?v=4",
          inserted_at: last_week,
          updated_at: now
        })

      existing ->
        existing
    end

  # Helper to insert a review only if its token doesn't already exist.
  seed_review = fn token, attrs ->
    if Repo.exists?(from r in Review, where: r.token == ^token) do
      nil
    else
      review =
        Repo.insert!(%Review{
          token: token,
          delete_token: "del_" <> token,
          review_round: attrs[:review_round] || 0,
          cli_args: attrs[:cli_args] || [],
          user_id: attrs[:user_id] || user.id,
          organization_id: attrs[:organization_id],
          visibility: attrs[:visibility] || :unlisted,
          last_activity_at: attrs[:last_activity_at] || now,
          inserted_at: attrs[:inserted_at] || now,
          updated_at: attrs[:updated_at] || now
        })

      for snap <- attrs[:snapshots] || [] do
        Repo.insert!(%ReviewRoundSnapshot{
          review_id: review.id,
          round_number: snap.round_number,
          file_path: snap.file_path,
          content: snap.content,
          position: snap[:position] || 0,
          status: snap[:status] || :modified,
          inserted_at: attrs[:inserted_at_naive] || now_naive
        })
      end

      for c <- attrs[:comments] || [] do
        parent =
          Repo.insert!(%Comment{
            id: c.id,
            review_id: review.id,
            start_line: c[:start_line],
            end_line: c[:end_line],
            body: c.body,
            author_identity: c[:author_identity] || "seed-author",
            author_display_name: c[:author_display_name] || "Alice",
            file_path: c[:file_path],
            scope: c[:scope] || "line",
            resolved: c[:resolved] || false,
            review_round: c[:review_round] || 0,
            quote: c[:quote],
            inserted_at: c[:inserted_at] || now,
            updated_at: c[:updated_at] || now
          })

        for reply <- c[:replies] || [] do
          Repo.insert!(%Comment{
            id: reply.id,
            review_id: review.id,
            parent_id: parent.id,
            body: reply.body,
            author_identity: reply[:author_identity] || "seed-replier",
            author_display_name: reply[:author_display_name] || "Bob",
            scope: parent.scope,
            file_path: parent.file_path,
            start_line: parent.start_line,
            end_line: parent.end_line,
            review_round: parent.review_round,
            inserted_at: reply[:inserted_at] || now,
            updated_at: reply[:updated_at] || now
          })
        end
      end

      review
    end
  end

  # ════════════════════════════════════════════════════════════════════════
  # 1. DEMO REVIEW — single file, used by homepage "Try a demo" link
  #    Token: seedreview12345678901 (matches config :demo_review_token)
  # ════════════════════════════════════════════════════════════════════════

  seed_review.("seedreview12345678901", %{
    last_activity_at: now,
    inserted_at: last_week,
    inserted_at_naive: last_week_naive,
    cli_args: ["auth-plan.md"],
    snapshots: [
      %{
        round_number: 0,
        file_path: "auth-plan.md",
        content: """
        # Authentication System Plan

        A plan for implementing JWT-based authentication for the API.

        ## Overview

        We'll use short-lived access tokens (15 min) with refresh token rotation stored in Redis.

        ## Implementation

        ### Token Generation

        ```go
        func generateToken(userID string) (string, error) {
            claims := jwt.MapClaims{
                "sub": userID,
                "exp": time.Now().Add(15 * time.Minute).Unix(),
            }
            return jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(secret)
        }
        ```

        ### API Endpoints

        | Method | Path | Description |
        |--------|------|-------------|
        | POST | /auth/login | Exchange credentials for tokens |
        | POST | /auth/refresh | Get new access token |
        | DELETE | /auth/logout | Revoke refresh token |

        ### Dependencies

        - `github.com/golang-jwt/jwt/v5` for token generation
        - Redis for refresh token storage and revocation

        ## Architecture

        ```mermaid
        sequenceDiagram
            Client->>API: POST /auth/login
            API-->>Client: access_token + refresh_token
            Client->>API: GET /resource (Bearer token)
            API-->>Client: 200 OK
            Client->>API: POST /auth/refresh
            API-->>Client: new access_token
        ```

        ## Security Considerations

        - Rotate refresh tokens on every use (one-time use)
        - Store refresh token hash in Redis, not raw value
        - Set `httponly` and `secure` on the refresh token cookie
        - Rate-limit login endpoint: 5 attempts per minute per IP
        """,
        position: 0
      }
    ],
    comments: [
      %{
        id: "a0000000-0000-0000-0000-000000000001",
        file_path: "auth-plan.md",
        start_line: 7,
        end_line: 7,
        body:
          "Should we also consider clock skew tolerance? JWT validators usually allow ±30s drift.",
        author_display_name: "Alice"
      },
      %{
        id: "a0000000-0000-0000-0000-000000000002",
        file_path: "auth-plan.md",
        start_line: 29,
        end_line: 31,
        body:
          "Good list. Also consider: logout should invalidate the access token if we add a token denylist (not needed for MVP with short expiry).",
        author_display_name: "Bob"
      }
    ]
  })

  # ════════════════════════════════════════════════════════════════════════
  # 2. MULTI-FILE REVIEW — Go project with 3 files, file-scoped comment
  # ════════════════════════════════════════════════════════════════════════

  seed_review.("seed-multi-file-00001", %{
    last_activity_at: yesterday,
    inserted_at: yesterday,
    inserted_at_naive: yesterday_naive,
    cli_args: ["main.go", "handler.go", "README.md"],
    snapshots: [
      %{
        round_number: 0,
        file_path: "main.go",
        content: ~S"""
        package main

        import (
        	"fmt"
        	"log"
        	"net/http"
        	"os"
        )

        func main() {
        	port := os.Getenv("PORT")
        	if port == "" {
        		port = "8080"
        	}

        	mux := http.NewServeMux()
        	mux.HandleFunc("/api/health", healthHandler)
        	mux.HandleFunc("/api/users", usersHandler)
        	mux.HandleFunc("/api/users/", userByIDHandler)

        	log.Printf("Starting server on :%s", port)
        	if err := http.ListenAndServe(fmt.Sprintf(":%s", port), mux); err != nil {
        		log.Fatal(err)
        	}
        }
        """,
        position: 0
      },
      %{
        round_number: 0,
        file_path: "handler.go",
        content: ~S"""
        package main

        import (
        	"encoding/json"
        	"net/http"
        	"strings"
        )

        type User struct {
        	ID    string `json:"id"`
        	Name  string `json:"name"`
        	Email string `json:"email"`
        }

        var users = []User{
        	{ID: "1", Name: "Alice", Email: "alice@example.com"},
        	{ID: "2", Name: "Bob", Email: "bob@example.com"},
        }

        func healthHandler(w http.ResponseWriter, r *http.Request) {
        	w.Header().Set("Content-Type", "application/json")
        	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
        }

        func usersHandler(w http.ResponseWriter, r *http.Request) {
        	if r.Method != http.MethodGet {
        		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
        		return
        	}
        	w.Header().Set("Content-Type", "application/json")
        	json.NewEncoder(w).Encode(users)
        }

        func userByIDHandler(w http.ResponseWriter, r *http.Request) {
        	id := strings.TrimPrefix(r.URL.Path, "/api/users/")
        	for _, u := range users {
        		if u.ID == id {
        			w.Header().Set("Content-Type", "application/json")
        			json.NewEncoder(w).Encode(u)
        			return
        		}
        	}
        	http.Error(w, "not found", http.StatusNotFound)
        }
        """,
        position: 1
      },
      %{
        round_number: 0,
        file_path: "README.md",
        content: """
        # User API

        A simple REST API for managing users.

        ## Endpoints

        - `GET /api/health` — health check
        - `GET /api/users` — list all users
        - `GET /api/users/:id` — get user by ID

        ## Running

        ```bash
        go run .
        ```

        Server starts on port 8080 (override with `PORT` env var).
        """,
        position: 2
      }
    ],
    comments: [
      %{
        id: "b0000000-0000-0000-0000-000000000001",
        file_path: "main.go",
        start_line: 11,
        end_line: 13,
        body:
          "Consider using a config struct instead of reading env vars inline. Makes testing easier.",
        author_display_name: "Alice"
      },
      %{
        id: "b0000000-0000-0000-0000-000000000002",
        file_path: "handler.go",
        start_line: 15,
        end_line: 18,
        body:
          "Hardcoded users should be replaced with a database. For now, at least add a `sync.RWMutex` if you plan to add write endpoints.",
        author_display_name: "Charlie"
      },
      %{
        id: "b0000000-0000-0000-0000-000000000003",
        file_path: "handler.go",
        start_line: 35,
        end_line: 35,
        body: "This is a linear scan — fine for 2 users, won't scale. Use a map lookup.",
        author_display_name: "Alice"
      },
      %{
        id: "b0000000-0000-0000-0000-000000000004",
        file_path: "README.md",
        scope: "file",
        body: "Nice docs! Maybe add a section on error responses and status codes.",
        author_display_name: "Bob"
      }
    ]
  })

  # ════════════════════════════════════════════════════════════════════════
  # 3. THREADED COMMENTS — replies, resolved threads, review-scoped,
  #    markdown in comments, quoted text
  # ════════════════════════════════════════════════════════════════════════

  seed_review.("seed-threaded-comm01", %{
    last_activity_at: yesterday,
    inserted_at: yesterday,
    inserted_at_naive: yesterday_naive,
    cli_args: ["config.yaml"],
    snapshots: [
      %{
        round_number: 0,
        file_path: "config.yaml",
        content: """
        # Application Configuration
        app:
          name: myservice
          version: 1.0.0
          environment: production

        server:
          host: 0.0.0.0
          port: 8080
          read_timeout: 30s
          write_timeout: 30s
          max_connections: 1000

        database:
          driver: postgres
          host: db.internal
          port: 5432
          name: myservice_prod
          pool_size: 25
          ssl_mode: require

        cache:
          driver: redis
          host: cache.internal
          port: 6379
          ttl: 5m
          max_memory: 256mb

        logging:
          level: info
          format: json
          output: stdout

        monitoring:
          enabled: true
          metrics_port: 9090
          health_check_path: /healthz
          traces_endpoint: https://otel.internal:4317
        """,
        position: 0
      }
    ],
    comments: [
      # Resolved thread with replies
      %{
        id: "c0000000-0000-0000-0000-000000000001",
        file_path: "config.yaml",
        start_line: 8,
        end_line: 8,
        body:
          "Binding to `0.0.0.0` in production is fine, but make sure the firewall rules are tight.",
        author_display_name: "Alice",
        resolved: true,
        replies: [
          %{
            id: "c0000000-0000-0000-0000-000000000010",
            body:
              "Good point. We have security groups limiting ingress to the load balancer only.",
            author_display_name: "Bob"
          },
          %{
            id: "c0000000-0000-0000-0000-000000000011",
            body: "Confirmed, marking as resolved.",
            author_display_name: "Alice"
          }
        ]
      },
      # Active thread with back-and-forth
      %{
        id: "c0000000-0000-0000-0000-000000000002",
        file_path: "config.yaml",
        start_line: 19,
        end_line: 19,
        body:
          "Pool size 25 seems high. What's the expected connection count per instance? We usually start at 10.",
        author_display_name: "Charlie",
        replies: [
          %{
            id: "c0000000-0000-0000-0000-000000000020",
            body:
              "We're running 4 instances, so 100 total connections. The DB can handle 200. 25 per instance gives us headroom for burst traffic.",
            author_display_name: "Bob"
          },
          %{
            id: "c0000000-0000-0000-0000-000000000021",
            body:
              "Fair enough. Maybe add a comment in the config explaining the math so future readers don't wonder.",
            author_display_name: "Charlie"
          }
        ]
      },
      # Review-scoped comment
      %{
        id: "c0000000-0000-0000-0000-000000000003",
        scope: "review",
        body:
          "Overall looks good. Two things to address before merging:\n\n1. The pool size question above\n2. Consider adding a `retry` section for the database connection\n\nNon-blocking: the monitoring config could use alerting thresholds.",
        author_display_name: "Alice"
      },
      # Comment with rich markdown and quoted text
      %{
        id: "c0000000-0000-0000-0000-000000000004",
        file_path: "config.yaml",
        start_line: 27,
        end_line: 27,
        body: """
        The `ttl: 5m` feels short for a production cache. Consider:

        - **Session data**: 30m minimum
        - **API responses**: depends on staleness tolerance
        - **Static config**: could be hours

        Here's what we use in the billing service:

        ```yaml
        cache:
          ttl_default: 15m
          ttl_sessions: 30m
          ttl_static: 1h
        ```

        See the Redis docs on eviction for `max_memory` policy options.
        """,
        author_display_name: "Diana",
        quote: "  ttl: 5m"
      }
    ]
  })

  # ════════════════════════════════════════════════════════════════════════
  # 4. MULTI-ROUND REVIEW — 2 revisions, shows diff between rounds
  #    Round 0: original Python parser
  #    Round 1: refactored with dataclass, error handling, validation
  # ════════════════════════════════════════════════════════════════════════

  seed_review.("seed-multi-round-001", %{
    review_round: 1,
    last_activity_at: now,
    inserted_at: last_week,
    inserted_at_naive: last_week_naive,
    updated_at: now,
    cli_args: ["parser.py"],
    snapshots: [
      # Round 0 — original version
      %{
        round_number: 0,
        file_path: "parser.py",
        content:
          String.trim_leading("""
          import re
          from typing import List, Dict, Optional

          class ConfigParser:
              # Parse INI-style configuration files.

              def __init__(self, path: str):
                  self.path = path
                  self.data: Dict[str, Dict[str, str]] = {}

              def parse(self) -> Dict[str, Dict[str, str]]:
                  current_section = "default"
                  self.data[current_section] = {}

                  with open(self.path) as f:
                      for line in f:
                          line = line.strip()
                          if not line or line.startswith("#"):
                              continue
                          if line.startswith("[") and line.endswith("]"):
                              current_section = line[1:-1]
                              self.data[current_section] = {}
                          elif "=" in line:
                              key, value = line.split("=", 1)
                              self.data[current_section][key.strip()] = value.strip()

                  return self.data

              def get(self, section: str, key: str) -> Optional[str]:
                  return self.data.get(section, {}).get(key)

              def sections(self) -> List[str]:
                  return list(self.data.keys())
          """),
        position: 0,
        status: :modified
      },
      # Round 1 — revised with dataclass, error handling, strict mode
      %{
        round_number: 1,
        file_path: "parser.py",
        content:
          String.trim_leading("""
          import re
          from pathlib import Path
          from typing import List, Dict, Optional
          from dataclasses import dataclass, field

          class ParseError(Exception):
              # Raised when configuration file cannot be parsed.
              def __init__(self, path: str, line_number: int, message: str):
                  self.path = path
                  self.line_number = line_number
                  super().__init__(f"{path}:{line_number}: {message}")

          @dataclass
          class ConfigParser:
              # Parse INI-style configuration files.
              #
              # Supports sections, key=value pairs, comments (#), and
              # inline comments. Values are stripped of surrounding whitespace.

              path: Path
              strict: bool = False
              data: Dict[str, Dict[str, str]] = field(default_factory=dict, init=False)
              _parsed: bool = field(default=False, init=False)

              def __post_init__(self):
                  self.path = Path(self.path)
                  if not self.path.exists():
                      raise FileNotFoundError(f"Config file not found: {self.path}")

              def parse(self) -> Dict[str, Dict[str, str]]:
                  if self._parsed:
                      return self.data

                  current_section = "default"
                  self.data[current_section] = {}

                  with open(self.path) as f:
                      for line_number, raw_line in enumerate(f, start=1):
                          line = raw_line.strip()

                          # Skip empty lines and full-line comments
                          if not line or line.startswith("#"):
                              continue

                          # Section header
                          if line.startswith("["):
                              match = re.match(r"^\\\\[\\\\w.-]+\\\\]$", line)
                              if not match:
                                  if self.strict:
                                      raise ParseError(str(self.path), line_number, f"malformed section: {line}")
                                  continue
                              current_section = line[1:-1]
                              self.data.setdefault(current_section, {})
                              continue

                          # Key = value
                          if "=" in line:
                              key, _, value = line.partition("=")
                              key = key.strip()
                              value = value.split("#", 1)[0].strip()  # strip inline comments

                              if not key:
                                  if self.strict:
                                      raise ParseError(str(self.path), line_number, "empty key")
                                  continue

                              self.data[current_section][key] = value
                          elif self.strict:
                              raise ParseError(str(self.path), line_number, f"unrecognized line: {line}")

                  self._parsed = True
                  return self.data

              def get(self, section: str, key: str, default: Optional[str] = None) -> Optional[str]:
                  return self.data.get(section, {}).get(key, default)

              def sections(self) -> List[str]:
                  return [s for s in self.data.keys() if s != "default"]

              def has_section(self, section: str) -> bool:
                  return section in self.data
          """),
        position: 0,
        status: :modified
      }
    ],
    comments: [
      # Comment on round 0 — now resolved after revision
      %{
        id: "d0000000-0000-0000-0000-000000000001",
        file_path: "parser.py",
        start_line: 14,
        end_line: 14,
        body:
          "No error handling if the file doesn't exist — this will raise an uncaught `FileNotFoundError`.",
        author_display_name: "Alice",
        review_round: 0,
        resolved: true,
        replies: [
          %{
            id: "d0000000-0000-0000-0000-000000000010",
            body: "Fixed in the revision — added `__post_init__` validation.",
            author_display_name: "Bob"
          }
        ]
      },
      # Another round 0 comment, also resolved
      %{
        id: "d0000000-0000-0000-0000-000000000002",
        file_path: "parser.py",
        start_line: 23,
        end_line: 24,
        body:
          "The `split(\"=\", 1)` approach won't handle values containing `=` correctly if quoted. Consider using `partition` instead.",
        author_display_name: "Charlie",
        review_round: 0,
        resolved: true,
        replies: [
          %{
            id: "d0000000-0000-0000-0000-000000000020",
            body: "Switched to `partition` in the updated version, thanks!",
            author_display_name: "Bob"
          }
        ]
      },
      # Comment on round 1 — still open
      %{
        id: "d0000000-0000-0000-0000-000000000003",
        file_path: "parser.py",
        start_line: 47,
        end_line: 47,
        body:
          "Nice use of `re.match` for section validation. One edge case: section names with spaces like `[my section]` are rejected. Is that intentional?",
        author_display_name: "Alice",
        review_round: 1
      },
      # Review-level comment on the revision
      %{
        id: "d0000000-0000-0000-0000-000000000004",
        scope: "review",
        body:
          "Great improvement! The `@dataclass` refactor is much cleaner. The `strict` mode is a nice touch.\n\nOne concern: `_parsed` caching means calling `parse()` after manually modifying `self.data` could return stale results. Maybe add an `invalidate()` method or document the contract.",
        author_display_name: "Charlie",
        review_round: 1
      }
    ]
  })

  # ════════════════════════════════════════════════════════════════════════
  # 5. MARKDOWN-RICH COMMENTS — tables, code blocks, blockquotes
  # ════════════════════════════════════════════════════════════════════════

  seed_review.("seed-markdown-comm01", %{
    last_activity_at: yesterday,
    inserted_at: yesterday,
    inserted_at_naive: yesterday_naive,
    cli_args: ["deploy.sh"],
    snapshots: [
      %{
        round_number: 0,
        file_path: "deploy.sh",
        content: ~S"""
        #!/bin/bash
        set -euo pipefail

        APP_NAME="${1:?Usage: deploy.sh <app-name> <environment>}"
        ENVIRONMENT="${2:?Usage: deploy.sh <app-name> <environment>}"
        IMAGE_TAG=$(git rev-parse --short HEAD)

        echo "Deploying $APP_NAME to $ENVIRONMENT (image: $IMAGE_TAG)"

        # Build and push Docker image
        docker build -t "registry.internal/$APP_NAME:$IMAGE_TAG" .
        docker push "registry.internal/$APP_NAME:$IMAGE_TAG"

        # Update Kubernetes deployment
        kubectl set image "deployment/$APP_NAME" \
          "$APP_NAME=registry.internal/$APP_NAME:$IMAGE_TAG" \
          -n "$ENVIRONMENT"

        # Wait for rollout
        kubectl rollout status "deployment/$APP_NAME" \
          -n "$ENVIRONMENT" \
          --timeout=300s

        echo "Deploy complete: $APP_NAME@$IMAGE_TAG -> $ENVIRONMENT"
        """,
        position: 0
      }
    ],
    comments: [
      %{
        id: "e0000000-0000-0000-0000-000000000001",
        file_path: "deploy.sh",
        start_line: 2,
        end_line: 2,
        body: """
        `set -euo pipefail` is great, but be aware of some gotchas:

        | Flag | Behavior | Gotcha |
        |------|----------|--------|
        | `-e` | Exit on error | Doesn't trigger in `if` conditions or `\\|\\|` chains |
        | `-u` | Error on undefined vars | `$@` and `$*` are exempt |
        | `-o pipefail` | Pipe returns rightmost failure | Can mask the _actual_ error |

        For more robust error handling, consider adding a trap:

        ```bash
        trap 'echo "Error on line $LINENO"; exit 1' ERR
        ```
        """,
        author_display_name: "Alice",
        quote: "set -euo pipefail"
      },
      %{
        id: "e0000000-0000-0000-0000-000000000002",
        file_path: "deploy.sh",
        start_line: 11,
        end_line: 12,
        body: """
        Two concerns here:

        1. **No build cache** — every deploy builds from scratch. Add `--cache-from`:
           ```bash
           docker pull "registry.internal/$APP_NAME:latest" || true
           docker build --cache-from "registry.internal/$APP_NAME:latest" ...
           ```

        2. **No multi-platform build** — if you ever need ARM, switch to `docker buildx build`

        > Also worth noting: `docker push` will fail silently if auth has expired. Add a `docker login` check.
        """,
        author_display_name: "Charlie"
      },
      %{
        id: "e0000000-0000-0000-0000-000000000003",
        file_path: "deploy.sh",
        start_line: 20,
        end_line: 22,
        body: """
        The 300s timeout is fine, but consider adding a **readiness check** after rollout:

        ```bash
        # Verify the new pods are actually serving traffic
        ENDPOINT=$(kubectl get svc "$APP_NAME" -n "$ENVIRONMENT" -o jsonpath='{.spec.clusterIP}')
        curl -sf "http://$ENDPOINT/healthz" || {
          echo "Health check failed - rolling back"
          kubectl rollout undo "deployment/$APP_NAME" -n "$ENVIRONMENT"
          exit 1
        }
        ```

        Without this, `rollout status` only confirms pods are *running*, not *healthy*.
        """,
        author_display_name: "Diana",
        replies: [
          %{
            id: "e0000000-0000-0000-0000-000000000030",
            body:
              "Good idea. We have readiness probes configured in the deployment manifest, so `rollout status` does wait for health. But an explicit smoke test is still a good belt-and-suspenders approach.",
            author_display_name: "Bob"
          }
        ]
      }
    ]
  })

  # ════════════════════════════════════════════════════════════════════════
  # 6. ALL RESOLVED — every comment resolved (clean review state)
  # ════════════════════════════════════════════════════════════════════════

  seed_review.("seed-all-resolved-01", %{
    last_activity_at: last_week,
    inserted_at: last_week,
    inserted_at_naive: last_week_naive,
    cli_args: ["utils.go"],
    snapshots: [
      %{
        round_number: 0,
        file_path: "utils.go",
        content: ~S"""
        package utils

        import (
        	"crypto/rand"
        	"encoding/hex"
        	"fmt"
        	"strings"
        	"time"
        )

        // GenerateID creates a random hex-encoded ID of the given byte length.
        func GenerateID(byteLen int) string {
        	b := make([]byte, byteLen)
        	_, _ = rand.Read(b)
        	return hex.EncodeToString(b)
        }

        // Retry calls fn up to maxAttempts times with exponential backoff.
        func Retry(maxAttempts int, fn func() error) error {
        	var lastErr error
        	for i := 0; i < maxAttempts; i++ {
        		if err := fn(); err != nil {
        			lastErr = err
        			time.Sleep(time.Duration(1<<uint(i)) * 100 * time.Millisecond)
        			continue
        		}
        		return nil
        	}
        	return fmt.Errorf("after %d attempts: %w", maxAttempts, lastErr)
        }

        // Slugify converts a string to a URL-friendly slug.
        func Slugify(s string) string {
        	s = strings.ToLower(strings.TrimSpace(s))
        	s = strings.ReplaceAll(s, " ", "-")
        	return s
        }
        """,
        position: 0
      }
    ],
    comments: [
      %{
        id: "f0000000-0000-0000-0000-000000000001",
        file_path: "utils.go",
        start_line: 14,
        end_line: 14,
        body:
          "Ignoring the error from `rand.Read` is fine on Linux (always succeeds) but document the assumption.",
        author_display_name: "Alice",
        resolved: true
      },
      %{
        id: "f0000000-0000-0000-0000-000000000002",
        file_path: "utils.go",
        start_line: 24,
        end_line: 24,
        body:
          "The backoff caps at ~3.2s for 5 attempts. Consider adding jitter to avoid thundering herd.",
        author_display_name: "Charlie",
        resolved: true,
        replies: [
          %{
            id: "f0000000-0000-0000-0000-000000000020",
            body: "Added jitter. Good catch.",
            author_display_name: "Bob"
          }
        ]
      },
      %{
        id: "f0000000-0000-0000-0000-000000000003",
        file_path: "utils.go",
        start_line: 33,
        end_line: 36,
        body:
          "`Slugify` doesn't handle special characters or unicode. OK for internal use, but don't expose to user input without sanitizing.",
        author_display_name: "Alice",
        resolved: true
      }
    ]
  })

  # ════════════════════════════════════════════════════════════════════════
  # 7. NO COMMENTS — empty state, clean file view
  # ════════════════════════════════════════════════════════════════════════

  seed_review.("seed-no-comments-01", %{
    last_activity_at: now,
    inserted_at: now,
    cli_args: ["Makefile"],
    snapshots: [
      %{
        round_number: 0,
        file_path: "Makefile",
        content: ~S"""
        .PHONY: build test lint clean

        APP_NAME := myapp
        VERSION  := $(shell git describe --tags --always)

        build:
        	go build -ldflags "-X main.version=$(VERSION)" -o bin/$(APP_NAME) .

        test:
        	go test -race -cover ./...

        lint:
        	golangci-lint run ./...

        clean:
        	rm -rf bin/ coverage/

        docker:
        	docker build -t $(APP_NAME):$(VERSION) .

        .DEFAULT_GOAL := build
        """,
        position: 0
      }
    ]
  })

  # ════════════════════════════════════════════════════════════════════════
  # 8. PUBLIC REVIEW — visibility: :public, indexable + listed in sitemap
  # ════════════════════════════════════════════════════════════════════════

  seed_review.("seed-public-review01", %{
    visibility: :public,
    last_activity_at: now,
    inserted_at: now,
    cli_args: ["public-demo.md"],
    snapshots: [
      %{
        round_number: 0,
        file_path: "public-demo.md",
        content: """
        # Public review demo

        This review has `visibility: :public` — it's indexable by search
        engines and appears in `/sitemap.xml`. Use it to preview the
        public-state UI: the green "Public" badge, no "Make public" button,
        and a `<link rel="canonical">` in the head.
        """,
        position: 0
      }
    ]
  })

  # ════════════════════════════════════════════════════════════════════════
  # ORGANIZATIONS — Acme org with email/password members for manual testing
  #
  # Your GitHub user (Tomasz) is the admin. Two local-auth users let you
  # log in as a regular member to verify permission boundaries.
  #
  #   alice@example.com / password1234  (member)
  #   bob@example.com   / password1234  (member)
  # ════════════════════════════════════════════════════════════════════════

  seed_org_user_id_alice = "00000000-0000-0000-0000-000000000010"
  seed_org_user_id_bob = "00000000-0000-0000-0000-000000000011"
  seed_org_id = "00000000-0000-0000-0000-000000000100"

  seed_local_user = fn id, name, email ->
    case Repo.get(User, id) do
      nil ->
        %User{}
        |> User.registration_changeset(%{
          "email" => email,
          "password" => "password1234",
          "name" => name
        })
        |> Ecto.Changeset.put_change(:id, id)
        |> Ecto.Changeset.put_change(:inserted_at, last_week)
        |> Ecto.Changeset.put_change(:updated_at, now)
        |> Repo.insert!()

      existing ->
        existing
    end
  end

  alice = seed_local_user.(seed_org_user_id_alice, "Alice Johnson", "alice@example.com")
  bob = seed_local_user.(seed_org_user_id_bob, "Bob Smith", "bob@example.com")

  acme =
    case Repo.get(Organization, seed_org_id) do
      nil ->
        Repo.insert!(%Organization{
          id: seed_org_id,
          name: "Acme",
          slug: "acme",
          inserted_at: last_week,
          updated_at: now
        })

      existing ->
        existing
    end

  seed_membership = fn org, member_user, role ->
    unless Repo.exists?(
             from m in OrganizationMembership,
               where: m.organization_id == ^org.id and m.user_id == ^member_user.id
           ) do
      Repo.insert!(%OrganizationMembership{
        organization_id: org.id,
        user_id: member_user.id,
        role: role,
        inserted_at: last_week,
        updated_at: now
      })
    end
  end

  seed_membership.(acme, user, :admin)
  seed_membership.(acme, alice, :member)
  seed_membership.(acme, bob, :member)

  # ════════════════════════════════════════════════════════════════════════
  # ORG-SCOPED REVIEWS — every combination of owner × visibility
  #
  # Visibility matrix when org_id is set:
  #   :organization — shown in org views, org members only
  #   :unlisted     — hidden from org views, org members only (with link)
  #   :public       — shown in org views, anyone can view
  # ════════════════════════════════════════════════════════════════════════

  # Admin-owned, visibility: :organization (default for org reviews)
  seed_review.("seed-org-admin-org01", %{
    user_id: user.id,
    organization_id: acme.id,
    visibility: :organization,
    last_activity_at: now,
    inserted_at: yesterday,
    inserted_at_naive: yesterday_naive,
    cli_args: ["architecture.md"],
    snapshots: [
      %{
        round_number: 0,
        file_path: "architecture.md",
        content: """
        # Architecture Decision Record: Event Sourcing

        ## Status
        Proposed

        ## Context
        We need to track all state changes for audit compliance.
        The current CRUD model loses history on every update.

        ## Decision
        Adopt event sourcing for the billing domain. Events are
        immutable and stored in an append-only log. Projections
        derive current state for queries.

        ## Consequences
        - Full audit trail for free
        - Replay capability for debugging
        - Higher complexity in the billing service
        - Need to handle schema evolution for events
        """,
        position: 0
      }
    ],
    comments: [
      %{
        id: "a0000000-0000-0000-0001-000000000001",
        file_path: "architecture.md",
        start_line: 14,
        end_line: 16,
        body:
          "Have we considered CQRS alongside this? Separate read/write models would help with query performance.",
        author_display_name: "Alice"
      }
    ]
  })

  # Admin-owned, visibility: :unlisted (org-private but hidden from listing)
  seed_review.("seed-org-admin-unl01", %{
    user_id: user.id,
    organization_id: acme.id,
    visibility: :unlisted,
    last_activity_at: yesterday,
    inserted_at: yesterday,
    inserted_at_naive: yesterday_naive,
    cli_args: ["draft-rfc.md"],
    snapshots: [
      %{
        round_number: 0,
        file_path: "draft-rfc.md",
        content: """
        # RFC: Database Migration Strategy (DRAFT)

        **Status:** Draft — not ready for team review yet.

        This is a work-in-progress proposal for migrating from
        PostgreSQL 14 to 17. Sharing the link with select people
        for early feedback before publishing to the full org.
        """,
        position: 0
      }
    ]
  })

  # Admin-owned, visibility: :public (anyone can view, shown in org listing)
  seed_review.("seed-org-admin-pub01", %{
    user_id: user.id,
    organization_id: acme.id,
    visibility: :public,
    last_activity_at: now,
    inserted_at: last_week,
    inserted_at_naive: last_week_naive,
    cli_args: ["onboarding.md"],
    snapshots: [
      %{
        round_number: 0,
        file_path: "onboarding.md",
        content: """
        # Developer Onboarding Guide

        Welcome to the team! This guide covers everything you need
        to get your local environment running.

        ## Prerequisites

        - Docker Desktop
        - Go 1.22+
        - Node.js 20+ (for frontend tooling)

        ## First Day Checklist

        1. Clone the monorepo
        2. Run `make setup` (installs deps, seeds DB)
        3. Run `make dev` (starts all services)
        4. Open http://localhost:3000

        ## Team Norms

        - PRs need one approval
        - Write tests for new endpoints
        - Use conventional commits
        """,
        position: 0
      }
    ],
    comments: [
      %{
        id: "a0000000-0000-0000-0001-000000000002",
        file_path: "onboarding.md",
        start_line: 20,
        end_line: 22,
        body: "Should we add a note about which Slack channels to join?",
        author_display_name: "Bob"
      }
    ]
  })

  # Member (Alice)-owned, visibility: :organization
  seed_review.("seed-org-alice-org01", %{
    user_id: alice.id,
    organization_id: acme.id,
    visibility: :organization,
    last_activity_at: now,
    inserted_at: now,
    cli_args: ["api-redesign.md"],
    snapshots: [
      %{
        round_number: 0,
        file_path: "api-redesign.md",
        content: """
        # API v2 Redesign Notes

        ## Breaking Changes

        - Remove `/api/v1/users/search` — use query params on `/api/v2/users`
        - Pagination switches from offset to cursor-based
        - Error responses follow RFC 7807 (Problem Details)

        ## New Endpoints

        | Method | Path                | Description        |
        |--------|---------------------|--------------------|
        | GET    | /api/v2/users       | List (cursor-based)|
        | POST   | /api/v2/users       | Create             |
        | GET    | /api/v2/users/:id   | Get by ID          |
        | PATCH  | /api/v2/users/:id   | Partial update     |
        | DELETE | /api/v2/users/:id   | Soft delete        |
        """,
        position: 0
      }
    ],
    comments: [
      %{
        id: "a0000000-0000-0000-0001-000000000003",
        file_path: "api-redesign.md",
        start_line: 5,
        end_line: 5,
        body: "How long do we maintain v1 alongside v2? Suggest a 6-month deprecation window.",
        author_display_name: "Bob"
      },
      %{
        id: "a0000000-0000-0000-0001-000000000004",
        scope: "review",
        body:
          "Looks solid. Let's discuss the cursor-based pagination format at standup — there are a few options.",
        author_display_name: "Tomasz Tomczyk"
      }
    ]
  })

  # Member (Alice)-owned, visibility: :unlisted
  seed_review.("seed-org-alice-unl01", %{
    user_id: alice.id,
    organization_id: acme.id,
    visibility: :unlisted,
    last_activity_at: yesterday,
    inserted_at: yesterday,
    inserted_at_naive: yesterday_naive,
    cli_args: ["scratch.py"],
    snapshots: [
      %{
        round_number: 0,
        file_path: "scratch.py",
        content: """
        # Quick benchmark — not for team review
        import timeit

        def approach_a():
            return [x**2 for x in range(1000)]

        def approach_b():
            return list(map(lambda x: x**2, range(1000)))

        print("List comp:", timeit.timeit(approach_a, number=10000))
        print("Map/lambda:", timeit.timeit(approach_b, number=10000))
        """,
        position: 0
      }
    ]
  })

  # Member (Bob)-owned, visibility: :organization
  seed_review.("seed-org-bob-org0001", %{
    user_id: bob.id,
    organization_id: acme.id,
    visibility: :organization,
    last_activity_at: yesterday,
    inserted_at: yesterday,
    inserted_at_naive: yesterday_naive,
    cli_args: ["bugfix-notes.md"],
    snapshots: [
      %{
        round_number: 0,
        file_path: "bugfix-notes.md",
        content: """
        # Bug: Race condition in session cleanup

        ## Symptom
        Users randomly logged out during peak traffic.

        ## Root Cause
        The session cleanup job and the auth middleware both read/write
        the session store without locking. Under high concurrency, the
        cleanup deletes a session between the middleware's read and
        the response's Set-Cookie.

        ## Fix
        Added a Redis WATCH/MULTI transaction around session refresh.
        The cleanup job now uses SCAN with a cursor instead of KEYS.

        ## Verification
        - Load test at 2x peak: 0 spurious logouts over 1 hour
        - Session cleanup latency: p99 dropped from 200ms to 15ms
        """,
        position: 0
      }
    ],
    comments: [
      %{
        id: "a0000000-0000-0000-0001-000000000005",
        file_path: "bugfix-notes.md",
        start_line: 14,
        end_line: 15,
        body: "Nice write-up. Can we add this to the incident log wiki too?",
        author_display_name: "Alice"
      }
    ]
  })

  # Member (Bob)-owned, visibility: :public
  seed_review.("seed-org-bob-pub0001", %{
    user_id: bob.id,
    organization_id: acme.id,
    visibility: :public,
    last_activity_at: last_week,
    inserted_at: last_week,
    inserted_at_naive: last_week_naive,
    cli_args: ["style-guide.md"],
    snapshots: [
      %{
        round_number: 0,
        file_path: "style-guide.md",
        content: """
        # Go Style Guide (Acme Team)

        ## Naming
        - Exported functions: `PascalCase`
        - Unexported: `camelCase`
        - Acronyms: `HTTPClient`, not `HttpClient`

        ## Error Handling
        - Always wrap errors: `fmt.Errorf("op failed: %w", err)`
        - Define sentinel errors for package boundaries
        - Never ignore errors silently (use `_ = fn()` if intentional)

        ## Testing
        - Table-driven tests for functions with multiple cases
        - Use `testify/assert` for assertions
        - Test files: `foo_test.go` next to `foo.go`
        """,
        position: 0
      }
    ]
  })

  # Orphaned author — review belongs to org but author account was deleted.
  # user_id is nil (simulates what happens after delete_user nilifies org reviews).
  seed_review.("seed-org-orphan-0001", %{
    user_id: nil,
    organization_id: acme.id,
    visibility: :organization,
    last_activity_at: last_week,
    inserted_at: last_week,
    inserted_at_naive: last_week_naive,
    cli_args: ["retro.md"],
    snapshots: [
      %{
        round_number: 0,
        file_path: "retro.md",
        content: """
        # Sprint Retro — Week 23

        ## What went well
        - Shipped the auth migration on time
        - Zero downtime deploy

        ## What could improve
        - PR review turnaround was slow this week
        - Flaky test in CI blocked 3 merges

        ## Action items
        - [ ] Set up auto-merge for green PRs
        - [ ] Quarantine flaky tests in a separate suite
        """,
        position: 0
      }
    ],
    comments: [
      %{
        id: "a0000000-0000-0000-0001-000000000006",
        file_path: "retro.md",
        start_line: 12,
        end_line: 12,
        body: "We should set a 24h SLA for PR reviews. Thoughts?",
        author_display_name: "Former Member"
      }
    ]
  })

  # ════════════════════════════════════════════════════════════════════════
  # PREVIEW REVIEW — shared static page (html + css + js + png) with
  #   DOM-anchored comments. review_type: :preview. Token: preview-demo-0000
  #
  #   Renders in an iframe with the preview chrome. The .png snapshot is
  #   stored Base64-encoded (encoding: "base64") to exercise the raw
  #   controller's decode path; the text assets are stored raw (encoding nil).
  #   Comments carry a `dom_anchor` map targeting real selectors in index.html.
  # ════════════════════════════════════════════════════════════════════════

  preview_demo_dir = Path.join(__DIR__, "seed_assets/preview_demo")
  read_demo_asset = fn name -> File.read!(Path.join(preview_demo_dir, name)) end

  unless Repo.exists?(from r in Review, where: r.token == "preview-demo-0000") do
    preview_review =
      Repo.insert!(%Review{
        token: "preview-demo-0000",
        delete_token: "del_preview-demo-0000",
        review_round: 0,
        cli_args: ["index.html"],
        user_id: user.id,
        review_type: :preview,
        visibility: :unlisted,
        last_activity_at: now,
        inserted_at: now,
        updated_at: now
      })

    # {file_path, content, encoding}. Text assets raw; the PNG Base64-encoded.
    preview_files = [
      {"index.html", read_demo_asset.("index.html"), nil},
      {"style.css", read_demo_asset.("style.css"), nil},
      {"app.js", read_demo_asset.("app.js"), nil},
      {"logo.png", Base.encode64(read_demo_asset.("logo.png")), "base64"}
    ]

    for {{file_path, content, encoding}, position} <- Enum.with_index(preview_files) do
      Repo.insert!(%ReviewRoundSnapshot{
        review_id: preview_review.id,
        round_number: 0,
        file_path: file_path,
        content: content,
        position: position,
        status: :modified,
        encoding: encoding,
        inserted_at: now_naive
      })
    end

    # Open comment anchored to the hero <h1>.
    Repo.insert!(%Comment{
      id: "e1000000-0000-0000-0000-000000000001",
      review_id: preview_review.id,
      body:
        "Strong opener. Could we A/B a more concrete value prop, e.g. lead with the go/no-go signal?",
      author_display_name: "Alice",
      scope: "file",
      file_path: "index.html",
      resolved: false,
      dom_anchor: %{
        "pathname" => "/",
        "css_selector" => "h1.hero",
        "tag_chain" => ["body", "main.card", "h1.hero"],
        "outer_html" => "<h1 class=\"hero\">Ship calmer releases.</h1>"
      },
      inserted_at: now,
      updated_at: now
    })

    # Resolved comment anchored to the CTA button.
    Repo.insert!(%Comment{
      id: "e1000000-0000-0000-0000-000000000002",
      review_id: preview_review.id,
      body: "CTA reads clearly and the counter interaction works. Approving this one.",
      author_display_name: "Bob",
      scope: "file",
      file_path: "index.html",
      resolved: true,
      dom_anchor: %{
        "pathname" => "/",
        "css_selector" => "#cta",
        "tag_chain" => ["body", "main.card", "button#cta"],
        "outer_html" => "<button class=\"cta\" id=\"cta\">Start free — 0 deploys watched</button>"
      },
      inserted_at: now,
      updated_at: now
    })
  end

  # ── Summary ────────────────────────────────────────────────────────────

  reviews = [
    {"seedreview12345678901", "Demo (homepage)", "single file, basic comments"},
    {"seed-multi-file-00001", "Multi-file", "3 files (Go + MD), file-scoped comment"},
    {"seed-threaded-comm01", "Threaded", "replies, resolved threads, review-scoped, markdown"},
    {"seed-multi-round-001", "Multi-round", "2 revisions with diff, outdated comments"},
    {"seed-markdown-comm01", "Markdown comments", "tables, code blocks, blockquotes"},
    {"seed-all-resolved-01", "All resolved", "every comment marked resolved"},
    {"seed-no-comments-01", "No comments", "clean file view, empty state"},
    {"seed-public-review01", "Public review", "visibility: :public — indexable, in sitemap"},
    {"preview-demo-0000", "Preview (iframe)",
     "html+css+js+png, review_type: :preview, DOM-anchored comments"}
  ]

  IO.puts("\n  Seeded #{length(reviews)} reviews for #{user.name}:\n")

  for {token, name, desc} <- reviews do
    IO.puts("    #{String.pad_trailing(name, 20)} http://localhost:4000/r/#{token}")
    IO.puts("    #{String.pad_trailing("", 20)} #{desc}\n")
  end

  IO.puts("  Dashboard: http://localhost:4000/dashboard")
  IO.puts("  (Log in with GitHub to see all reviews)\n")

  IO.puts("  Organization: Acme (http://localhost:4000/orgs/acme)")
  IO.puts("    admin:  #{user.name} (GitHub login)")
  IO.puts("    member: alice@example.com / password1234")
  IO.puts("    member: bob@example.com   / password1234\n")

  org_reviews = [
    {"seed-org-admin-org01", "Admin / :organization",
     "architecture.md — visible in org listing, members only"},
    {"seed-org-admin-unl01", "Admin / :unlisted",
     "draft-rfc.md — hidden from listing, members only with link"},
    {"seed-org-admin-pub01", "Admin / :public",
     "onboarding.md — visible in org listing, anyone can view"},
    {"seed-org-alice-org01", "Alice / :organization",
     "api-redesign.md — member-owned, members only"},
    {"seed-org-alice-unl01", "Alice / :unlisted",
     "scratch.py — member-owned, hidden, members only with link"},
    {"seed-org-bob-org0001", "Bob / :organization",
     "bugfix-notes.md — member-owned, members only"},
    {"seed-org-bob-pub0001", "Bob / :public", "style-guide.md — member-owned, anyone can view"},
    {"seed-org-orphan-0001", "Orphaned author",
     "retro.md — author deleted, review persists under org"}
  ]

  IO.puts("  Org-scoped reviews (#{length(org_reviews)}):\n")

  for {token, label, desc} <- org_reviews do
    IO.puts("    #{String.pad_trailing(label, 28)} http://localhost:4000/r/#{token}")
    IO.puts("    #{String.pad_trailing("", 28)} #{desc}\n")
  end
end
