# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Crit.Repo.insert!(%Crit.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

if Mix.env() in [:dev, :test] do
  import Ecto.Query
  alias Crit.{Repo, Review, Comment, ReviewRoundSnapshot}

  seed_token = "seedreview12345678901"

  unless Repo.exists?(from r in Review, where: r.token == ^seed_token) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    sample_md = """
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
    """

    review =
      Repo.insert!(%Review{
        token: seed_token,
        delete_token: Nanoid.generate(21),
        review_round: 0,
        last_activity_at: now,
        inserted_at: now,
        updated_at: now
      })

    Repo.insert!(%ReviewRoundSnapshot{
      review_id: review.id,
      round_number: 0,
      file_path: "auth-plan.md",
      content: sample_md,
      position: 0,
      inserted_at: now
    })

    Repo.insert!(%Comment{
      id: "a0000000-0000-0000-0000-000000000001",
      review_id: review.id,
      start_line: 7,
      end_line: 7,
      body:
        "Should we also consider clock skew tolerance? JWT validators usually allow ±30s drift.",
      author_identity: "imported",
      file_path: "auth-plan.md",
      inserted_at: now,
      updated_at: now
    })

    Repo.insert!(%Comment{
      id: "a0000000-0000-0000-0000-000000000002",
      review_id: review.id,
      start_line: 45,
      end_line: 47,
      body:
        "Good list. Also consider: logout should invalidate the access token if we add a token denylist (not needed for MVP with short expiry).",
      author_identity: "imported",
      file_path: "auth-plan.md",
      inserted_at: now,
      updated_at: now
    })

    IO.puts("Seeded dev review at token: #{seed_token}")
    IO.puts("Visit: http://localhost:4000/r/#{seed_token}")
  end
end
