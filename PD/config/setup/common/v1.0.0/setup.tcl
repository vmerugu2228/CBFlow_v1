# CBflow Global Setup — applies to ALL flows, ALL stages
# Priority: LOWEST

# Global flow_proc hook: add design info header to every stage
flow_proc_prepend start_stage {
    handle_info "═══════════════════════════════════════════"
    handle_info "  CBflow Global Hook: Design=$::env(CBFLOW_DESIGN_NAME)"
    handle_info "  Flow=$::env(CBFLOW_FLOW_TYPE) Release=$::env(CBFLOW_RELEASE_VERSION)"
    handle_info "═══════════════════════════════════════════"
}
