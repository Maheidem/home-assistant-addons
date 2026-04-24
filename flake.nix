{
  description = "Home Assistant Add-on Development Environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Container tools
            podman
            podman-compose
            
            # Home Assistant development tools
            hadolint  # Dockerfile linter
            curl      # For testing endpoints
            jq        # JSON processing
            
            # Build and validation tools
            git
            bash
            
            # Optional: useful for debugging
            yq-go     # YAML processing
          ];

          shellHook = ''
            echo "🏠 Home Assistant Add-on Development Environment"
            echo ""
            echo "Claude Terminal:"
            echo "  build-addon     - Build the Claude Terminal add-on"
            echo "  run-addon       - Run Claude Terminal locally on :7681"
            echo "  lint-dockerfile - Lint Claude Terminal's Dockerfile"
            echo "  test-endpoint   - Curl Claude Terminal's endpoint"
            echo ""
            echo "OpenCode:"
            echo "  build-opencode            - Build the OpenCode add-on"
            echo "  run-opencode              - Run OpenCode locally on :7682"
            echo "  lint-opencode-dockerfile  - Lint OpenCode's Dockerfile"
            echo "  test-opencode-endpoint    - Curl OpenCode's endpoint"
            echo ""
            echo "Shared:"
            echo "  validate-addon  - (noop here) HA builder validation needs HA OS"
            echo ""

            # Claude Terminal (uses /config:rw map and the legacy config volume).
            alias build-addon='podman build --build-arg BUILD_FROM=ghcr.io/home-assistant/amd64-base-debian:bookworm -t local/claude-terminal ./claude-terminal'
            alias run-addon='podman run --rm -p 7681:7681 -v $(pwd)/claude-terminal/.local-config:/config local/claude-terminal'
            alias lint-dockerfile='hadolint ./claude-terminal/Dockerfile'
            alias test-endpoint='curl -X GET http://localhost:7681/ || echo "claude-terminal not running. Use: run-addon"'

            # OpenCode (uses addon_config:rw + /data — two mounts for local dev).
            alias build-opencode='podman build --build-arg BUILD_FROM=ghcr.io/home-assistant/amd64-base-debian:bookworm -t local/opencode-terminal ./opencode-terminal'
            alias run-opencode='podman run --rm -p 7682:7682 -v $(pwd)/opencode-terminal/.local-data:/data -v $(pwd)/opencode-terminal/.local-config:/config local/opencode-terminal'
            alias lint-opencode-dockerfile='hadolint ./opencode-terminal/Dockerfile'
            alias test-opencode-endpoint='curl -X GET http://localhost:7682/ || echo "opencode-terminal not running. Use: run-opencode"'

            alias validate-addon='echo "Note: Home Assistant builder validation requires HA OS environment"'
          '';
        };
      });
}