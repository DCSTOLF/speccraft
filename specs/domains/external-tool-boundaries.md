# Domain: external-tool-boundaries

Speccraft defers routing for external tools it does not own (code-intel/call-graph) to the user's environment; no brand endorsements in model-loaded, template, or human-facing surfaces.

- Speccraft defers all code-intelligence routing (call-graph / symbol-search tool choice) to whatever tool the user has installed; its skills, commands, and templates do not enumerate or express a preference for a specific tool (spec 0011)
- Templates under `templates/speccraft/` stay stack-agnostic and name no specific external enforcement tool; a code-intel tool may appear only as a neutral example ("such as CodeGraphContext"), never as a recommendation (spec 0011)
- Prescriptive routing prose toward an unowned external tool ("prefer it over grep/find", "use its tools", "the recommended way", "should install ... alongside speccraft") is disallowed in every speccraft surface including human-facing `README.md` and overview docs; neutral labels such as "Recommended companions" are retained (spec 0016)
