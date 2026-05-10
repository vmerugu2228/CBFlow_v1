#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# CBFlow - Bash Shell Completions
# Source this file to enable tab completion for cbflow commands
# Usage: source /path/to/PD/completions/cbflow.bash
#   or:  eval "$(cbflow --completions bash)"
# ══════════════════════════════════════════════════════════════════════════════

_cbflow_get_projects() {
    local projects_file="${CBFLOW_CORE_DIR:-}/config/master_projects.json"
    if [[ -f "$projects_file" ]]; then
        python3 -c "import json; f=open('$projects_file'); d=json.load(f); print(' '.join(d.get('projects',{}).keys()))" 2>/dev/null
    fi
}

_cbflow_get_flow_types() {
    local config_dir="${CBFLOW_CORE_DIR:-}/config/flow"
    if [[ -d "$config_dir" ]]; then
        # Try to get from node_configs directory
        local version_dir
        for version_dir in "$config_dir"/v*/node_configs "$config_dir"/workspace/node_configs; do
            if [[ -d "$version_dir" ]]; then
                ls "$version_dir"/*_config.tcl 2>/dev/null | sed 's/.*\///' | sed 's/_config\.tcl//' | tr '\n' ' '
                return
            fi
        done
    fi
    echo "SYNTH FP PNR STA LEC EMIR PV ECO CLP POPT FCFP"
}

_cbflow_get_releases() {
    local releases_dir="${CBFLOW_CORE_DIR:-}/releases"
    if [[ -d "$releases_dir" ]]; then
        ls -d "$releases_dir"/v* 2>/dev/null | xargs -I{} basename {} | tr '\n' ' '
    fi
}

_cbflow_completions() {
    local cur prev words cword
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    cword=$COMP_CWORD

    # Level 1: main commands
    if [[ ${cword} -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "workspace run flow --version --help" -- "${cur}") )
        return 0
    fi

    local main_cmd="${COMP_WORDS[1]}"

    # Level 2: subcommands
    if [[ ${cword} -eq 2 ]]; then
        case "${main_cmd}" in
            workspace)
                COMPREPLY=( $(compgen -W "template create status list-runs clean validate" -- "${cur}") )
                ;;
            run)
                COMPREPLY=( $(compgen -W "all stage interactive status retrace clean validate logs report show-graph list-nodes list-branches release-info targets gen-makefile lsf-status email autoppt checklist help" -- "${cur}") )
                ;;
            flow)
                COMPREPLY=( $(compgen -W "types info stages nodes check project version release config plugin metrics dashboard checklist qor-report trending library-manager mmmc-manager" -- "${cur}") )
                ;;
        esac
        return 0
    fi

    local sub_cmd="${COMP_WORDS[2]}"

    # Level 3: sub-subcommands and options
    case "${main_cmd}" in
        workspace)
            case "${sub_cmd}" in
                init)
                    case "${prev}" in
                        --project)
                            local projects=$(_cbflow_get_projects)
                            COMPREPLY=( $(compgen -W "${projects}" -- "${cur}") )
                            ;;
                        --flow)
                            local flows=$(_cbflow_get_flow_types)
                            COMPREPLY=( $(compgen -W "${flows}" -- "${cur}") )
                            ;;
                        *)
                            COMPREPLY=( $(compgen -W "--project --flow --release --force" -- "${cur}") )
                            ;;
                    esac
                    ;;
                template)
                    case "${prev}" in
                        --flow|-t)
                            local flows=$(_cbflow_get_flow_types)
                            COMPREPLY=( $(compgen -W "${flows}" -- "${cur}") )
                            ;;
                        --output|-o)
                            COMPREPLY=( $(compgen -f -X '!*.tcl' -- "${cur}") )
                            ;;
                        *)
                            COMPREPLY=( $(compgen -W "--flow --output" -- "${cur}") )
                            ;;
                    esac
                    ;;
                create)
                    case "${prev}" in
                        --config|-c)
                            COMPREPLY=( $(compgen -f -X '!*.tcl' -- "${cur}") )
                            ;;
                        *)
                            COMPREPLY=( $(compgen -W "--config --force" -- "${cur}") )
                            ;;
                    esac
                    ;;
                clean)
                    COMPREPLY=( $(compgen -W "--confirm" -- "${cur}") )
                    ;;
            esac
            ;;
        run)
            case "${sub_cmd}" in
                stage)
                    case "${prev}" in
                        --name|-n)
                            local flows=$(_cbflow_get_flow_types)
                            COMPREPLY=( $(compgen -W "${flows}" -- "${cur}") )
                            ;;
                        *)
                            COMPREPLY=( $(compgen -W "--name -n" -- "${cur}") )
                            ;;
                    esac
                    ;;
                all)
                    COMPREPLY=( $(compgen -W "--validate --lsf --queue --collect-metrics" -- "${cur}") )
                    ;;
                status)
                    COMPREPLY=( $(compgen -W "--details -d --output -o" -- "${cur}") )
                    ;;
                retrace)
                    COMPREPLY=( $(compgen -W "--from" -- "${cur}") )
                    ;;
                clean)
                    COMPREPLY=( $(compgen -W "--confirm" -- "${cur}") )
                    ;;
                interactive)
                    case "${prev}" in
                        --load|-l)
                            # Complete with node names from .stamps/ or work/ dirs
                            local nodes=""
                            if [[ -d "work" ]]; then
                                for d in work/*/; do
                                    local flow_dir="$d"
                                    for nd in ${flow_dir}*/; do
                                        nodes="$nodes $(basename $nd)"
                                    done
                                done
                            fi
                            COMPREPLY=( $(compgen -W "${nodes}" -- "${cur}") )
                            ;;
                        *)
                            COMPREPLY=( $(compgen -W "--load -l" -- "${cur}") )
                            ;;
                    esac
                    ;;
                email)
                    case "${prev}" in
                        --template|-t)
                            COMPREPLY=( $(compgen -W "run-creation run-status run-summary checklist reminder release-update" -- "${cur}") )
                            ;;
                        *)
                            COMPREPLY=( $(compgen -W "--to --template -t --subject -s --message -m --due-date --milestone --attach --preview --html" -- "${cur}") )
                            ;;
                    esac
                    ;;
                autoppt)
                    case "${prev}" in
                        --format|-f)
                            COMPREPLY=( $(compgen -W "pptx html" -- "${cur}") )
                            ;;
                        *)
                            COMPREPLY=( $(compgen -W "--format -f --output -o" -- "${cur}") )
                            ;;
                    esac
                    ;;
                checklist)
                    case "${prev}" in
                        --milestone|-m)
                            COMPREPLY=( $(compgen -W "FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO MTO" -- "${cur}") )
                            ;;
                        --phase|-p)
                            COMPREPLY=( $(compgen -W "P0 P1 P2 P3" -- "${cur}") )
                            ;;
                        --format|-f)
                            COMPREPLY=( $(compgen -W "text json html" -- "${cur}") )
                            ;;
                        *)
                            COMPREPLY=( $(compgen -W "--milestone -m --phase -p --format -f --list --sign-off --approver --project" -- "${cur}") )
                            ;;
                    esac
                    ;;
                show-graph)
                    COMPREPLY=( $(compgen -W "--detail -d" -- "${cur}") )
                    ;;
                add-node)
                    COMPREPLY=( $(compgen -W "--node -n --type -t --dep -d" -- "${cur}") )
                    ;;
                delete-node)
                    COMPREPLY=( $(compgen -W "--node -n" -- "${cur}") )
                    ;;
                create-branch)
                    COMPREPLY=( $(compgen -W "--branch -b --from" -- "${cur}") )
                    ;;
                delete-branch)
                    COMPREPLY=( $(compgen -W "--branch -b --from" -- "${cur}") )
                    ;;
                validate)
                    case "${prev}" in
                        --type)
                            COMPREPLY=( $(compgen -W "all config inputs exit" -- "${cur}") )
                            ;;
                        *)
                            COMPREPLY=( $(compgen -W "--type --stage" -- "${cur}") )
                            ;;
                    esac
                    ;;
                lsf-status)
                    COMPREPLY=( $(compgen -W "--flow" -- "${cur}") )
                    ;;
                logs)
                    COMPREPLY=( $(compgen -W "--list -l --tail -t --search -s --level --file -f" -- "${cur}") )
                    ;;
                update)
                    case "${prev}" in
                        --release|-r)
                            local releases=$(_cbflow_get_releases)
                            COMPREPLY=( $(compgen -W "${releases}" -- "${cur}") )
                            ;;
                        *)
                            COMPREPLY=( $(compgen -W "--release -r --no-backup" -- "${cur}") )
                            ;;
                    esac
                    ;;
            esac
            ;;
        flow)
            case "${sub_cmd}" in
                info|stages|nodes)
                    case "${prev}" in
                        --flow)
                            local flows=$(_cbflow_get_flow_types)
                            COMPREPLY=( $(compgen -W "${flows}" -- "${cur}") )
                            ;;
                        *)
                            COMPREPLY=( $(compgen -W "--flow" -- "${cur}") )
                            ;;
                    esac
                    ;;
                project)
                    if [[ ${cword} -eq 3 ]]; then
                        COMPREPLY=( $(compgen -W "list info create delete manage" -- "${cur}") )
                    fi
                    ;;
                version)
                    if [[ ${cword} -eq 3 ]]; then
                        COMPREPLY=( $(compgen -W "list copy create set-current get-current diff status" -- "${cur}") )
                    fi
                    ;;
                release)
                    if [[ ${cword} -eq 3 ]]; then
                        COMPREPLY=( $(compgen -W "generate-config create list info set-current validate components diff help" -- "${cur}") )
                    else
                        local release_sub="${COMP_WORDS[3]}"
                        case "${release_sub}" in
                            diff)
                                case "${prev}" in
                                    --v1|--v2)
                                        local releases=$(_cbflow_get_releases)
                                        COMPREPLY=( $(compgen -W "${releases}" -- "${cur}") )
                                        ;;
                                    --format)
                                        COMPREPLY=( $(compgen -W "text json markdown" -- "${cur}") )
                                        ;;
                                    *)
                                        COMPREPLY=( $(compgen -W "--v1 --v2 --format" -- "${cur}") )
                                        ;;
                                esac
                                ;;
                            create)
                                case "${prev}" in
                                    --type|-t)
                                        COMPREPLY=( $(compgen -W "patch minor major" -- "${cur}") )
                                        ;;
                                    *)
                                        COMPREPLY=( $(compgen -W "--config -c --type -t --version -v --desc -d --force" -- "${cur}") )
                                        ;;
                                esac
                                ;;
                            info|set-current|validate)
                                case "${prev}" in
                                    --version|-v)
                                        local releases=$(_cbflow_get_releases)
                                        COMPREPLY=( $(compgen -W "${releases}" -- "${cur}") )
                                        ;;
                                    *)
                                        COMPREPLY=( $(compgen -W "--version -v" -- "${cur}") )
                                        ;;
                                esac
                                ;;
                        esac
                    fi
                    ;;
                config)
                    if [[ ${cword} -eq 3 ]]; then
                        COMPREPLY=( $(compgen -W "manage-flow manage-node manage-tech validate status" -- "${cur}") )
                    fi
                    ;;
                plugin)
                    if [[ ${cword} -eq 3 ]]; then
                        COMPREPLY=( $(compgen -W "register unregister scaffold list" -- "${cur}") )
                    fi
                    ;;
                metrics)
                    if [[ ${cword} -eq 3 ]]; then
                        COMPREPLY=( $(compgen -W "collect report export" -- "${cur}") )
                    fi
                    ;;
                dashboard)
                    if [[ ${cword} -eq 3 ]]; then
                        COMPREPLY=( $(compgen -W "start stop" -- "${cur}") )
                    fi
                    ;;
                checklist)
                    if [[ ${cword} -eq 3 ]]; then
                        COMPREPLY=( $(compgen -W "generate status sign-off list waiver" -- "${cur}") )
                    else
                        case "${prev}" in
                            --milestone) COMPREPLY=( $(compgen -W "FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO MTO" -- "${cur}") ) ;;
                            --format)    COMPREPLY=( $(compgen -W "text json html" -- "${cur}") ) ;;
                            --action)    COMPREPLY=( $(compgen -W "list add revoke" -- "${cur}") ) ;;
                            *)           COMPREPLY=( $(compgen -W "--milestone --run-dir --project --phase --format --approver --action" -- "${cur}") ) ;;
                        esac
                    fi
                    ;;
                qor-report)
                    if [[ ${cword} -eq 3 ]]; then
                        COMPREPLY=( $(compgen -W "generate compare summary" -- "${cur}") )
                    else
                        case "${prev}" in
                            --format) COMPREPLY=( $(compgen -W "text json csv html" -- "${cur}") ) ;;
                            --milestone) COMPREPLY=( $(compgen -W "FP_EXIT PLACE_EXIT CTS_EXIT PRO_EXIT BTO MTO" -- "${cur}") ) ;;
                            *) COMPREPLY=( $(compgen -W "--run-dir --milestone --format -o --run-dir1 --run-dir2 --project --flow" -- "${cur}") ) ;;
                        esac
                    fi
                    ;;
                trending)
                    if [[ ${cword} -eq 3 ]]; then
                        COMPREPLY=( $(compgen -W "report baseline check record stats" -- "${cur}") )
                    else
                        case "${COMP_WORDS[3]}" in
                            baseline)
                                if [[ ${cword} -eq 4 ]]; then
                                    COMPREPLY=( $(compgen -W "set show" -- "${cur}") )
                                fi
                                ;;
                        esac
                        case "${prev}" in
                            --metric) COMPREPLY=( $(compgen -W "wns tns power utilization drc" -- "${cur}") ) ;;
                            --project) local p=$(_cbflow_get_projects); COMPREPLY=( $(compgen -W "${p}" -- "${cur}") ) ;;
                            --flow) local f=$(_cbflow_get_flow_types); COMPREPLY=( $(compgen -W "${f}" -- "${cur}") ) ;;
                            *) COMPREPLY=( $(compgen -W "--project --flow --metric --last --run-dir --milestone" -- "${cur}") ) ;;
                        esac
                    fi
                    ;;
                library-manager)
                    if [[ ${cword} -eq 3 ]]; then
                        COMPREPLY=( $(compgen -W "scan create check list verify generate-mmmc" -- "${cur}") )
                    else
                        case "${prev}" in
                            --format) COMPREPLY=( $(compgen -W "text json" -- "${cur}") ) ;;
                            --path)   COMPREPLY=( $(compgen -d -- "${cur}") ) ;;
                            --track)  COMPREPLY=( $(compgen -W "9T 7.5T 6.75T" -- "${cur}") ) ;;
                            *)        COMPREPLY=( $(compgen -W "--path --recursive --format --output --tech-config --tech-node --track --verbose --corner --voltage --temp" -- "${cur}") ) ;;
                        esac
                    fi
                    ;;
                mmmc-manager)
                    if [[ ${cword} -eq 3 ]]; then
                        COMPREPLY=( $(compgen -W "create show validate generate-view-def add-mode remove-mode" -- "${cur}") )
                    else
                        case "${prev}" in
                            --config) COMPREPLY=( $(compgen -f -X '!*.tcl' -- "${cur}") ) ;;
                            --output) COMPREPLY=( $(compgen -f -- "${cur}") ) ;;
                            *)        COMPREPLY=( $(compgen -W "--interactive --config --output --corners --voltages --temps --modes --name --desc --freq --sdc" -- "${cur}") ) ;;
                        esac
                    fi
                    ;;
            esac
            ;;
    esac

    return 0
}

complete -F _cbflow_completions cbflow
